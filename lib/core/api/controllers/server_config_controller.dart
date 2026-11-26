import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme_utils.dart';
import 'package:thingsboard_democloud_app/constants/app_constants.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_app_preferences.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_secure_storage.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/server_config_repository.dart';
import 'package:thingsboard_democloud_app/core/api/ws/telemetry_ws_service.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Boundary provider for secure credential storage (`flutter_secure_storage`).
final tbStorageProvider = Provider<TbStorage>((ref) {
  return FlutterSecureStorageImpl();
});

/// Boundary provider for non-secret host/UI preferences (`shared_preferences`).
final tbAppPreferencesProvider = Provider<TbAppPreferences>((ref) {
  return SharedPreferencesImpl();
});

/// Optional [HttpClientAdapter] override for deterministic Dio boundary tests.
final tbHttpClientAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

/// Optional WebSocket channel factory override for boundary tests.
final wsChannelFactoryProvider = Provider<WebSocketChannel Function(Uri)>((
  ref,
) {
  return WebSocketChannel.connect;
});

/// Shared [TbApiClient] singleton managing `Dio`, single-flight refresh, and `CancelToken`s.
final tbApiClientProvider = Provider<TbApiClient>((ref) {
  final storage = ref.watch(tbStorageProvider);
  final adapter = ref.watch(tbHttpClientAdapterProvider);
  return TbApiClient(
    baseUrl: ThingsboardAppConstants.thingsBoardApiEndpoint,
    storage: storage,
    httpClientAdapter: adapter,
    onSessionInvalidated: () {
      Future<void>.microtask(
        () => ref.read(authProvider.notifier).handleSessionInvalidated(),
      );
    },
  );
});

/// Shared [Dio] HTTP client pointing to the active ThingsBoard endpoint.
final dioClientProvider = Provider<Dio>((ref) {
  return ref.watch(tbApiClientProvider).dio;
});

/// Shared `wss://<host>/api/ws` WebSocket service kept alive across screens.
final telemetryWsServiceProvider = Provider<TbWebSocketService>((ref) {
  final client = ref.watch(tbApiClientProvider);
  final channelFactory = ref.watch(wsChannelFactoryProvider);

  final service = TbWebSocketService(
    wsUriProvider: () => TbWebSocketService.buildWsUri(client.baseUrl),
    tokenProvider: () => client.coordinator.getAccessTokenForRequest(),
    channelFactory: channelFactory,
    onAuthFailure: (_) {
      Future<void>.microtask(
        () => ref.read(authProvider.notifier).handleSessionInvalidated(),
      );
    },
  );

  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

/// Live connection state stream for [TbWebSocketService].
final wsConnectionStateProvider = StreamProvider<WsConnectionState>((
  ref,
) async* {
  final service = ref.watch(telemetryWsServiceProvider);
  yield service.currentState;
  yield* service.connectionStateStream;
});

final serverConfigRepositoryProvider = Provider<ServerConfigRepository>((ref) {
  return RestServerConfigRepository(client: ref.watch(tbApiClientProvider));
});

/// Manages active ThingsBoard base URL, [SessionMode] (`live` vs `demo`), and server capabilities.
class ServerConfigController extends Notifier<ServerConfigState> {
  bool _initialized = false;

  @override
  ServerConfigState build() {
    return ServerConfigState(
      baseUrl: ThingsboardAppConstants.thingsBoardApiEndpoint,
    );
  }

  /// Loads persisted host/mode/theme preferences once on startup and probes public capabilities.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = ref.read(tbAppPreferencesProvider);
    final baseUrl = await prefs.getServerBaseUrl();
    final mode = await prefs.getSessionMode();
    final themeMode = await prefs.getThemeMode();

    final normalizedBaseUrl = _normalize(baseUrl);
    final client = ref.read(tbApiClientProvider);
    if (client.baseUrl != normalizedBaseUrl) {
      client.switchBaseUrl(normalizedBaseUrl);
    }

    ref.read(themeModeProvider.notifier).setThemeMode(themeMode);

    state = state.copyWith(
      baseUrl: normalizedBaseUrl,
      mode: mode,
      themeMode: themeMode,
      sessionGeneration: client.sessionGeneration,
    );

    if (mode == SessionMode.live) {
      await fetchPublicCapabilities();
    }
  }

  /// Fetches password policy, OAuth2 clients, and optional PE mobile metadata (graceful 404).
  Future<void> fetchPublicCapabilities() async {
    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;
    final repo = ref.read(serverConfigRepositoryProvider);
    final platform = resolveMobilePlatformName();
    const pkgName = 'org.thingsboard.pe.app';

    try {
      final results = await Future.wait([
        repo.fetchPasswordPolicy().catchError((_) => null),
        repo
            .fetchOAuth2Clients(pkgName: pkgName, platform: platform)
            .catchError((_) => const <OAuth2ClientModel>[]),
        repo
            .fetchMobileInfo(pkgName: pkgName, platform: platform)
            .catchError((_) => null),
      ]);

      if (gen != client.sessionGeneration) return;

      final policy = results[0] as UserPasswordPolicy?;
      final oauthClients = results[1] as List<OAuth2ClientModel>;
      final mobileInfo = results[2] as LoginMobileInfo?;

      state = state.copyWith(
        passwordPolicy: policy,
        oauthClients: oauthClients.isNotEmpty
            ? oauthClients
            : (mobileInfo?.oAuth2Clients ?? const <OAuth2ClientModel>[]),
        mobileInfo: mobileInfo,
        clearMobileInfo: mobileInfo == null,
      );
    } catch (_) {
      // Capability probing is strictly best-effort on login screen.
    }
  }

  /// Probes authenticated `/api/system/info` to cache server version.
  Future<void> probeServerVersion() async {
    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;
    final repo = ref.read(serverConfigRepositoryProvider);
    try {
      final version = await repo.fetchSystemVersion();
      if (gen != client.sessionGeneration) return;
      state = state.copyWith(
        serverVersion: version,
        clearServerVersion: version == null,
      );
    } catch (_) {
      // Optional capability check; ignore errors.
    }
  }

  /// Atomically switches target host URL, clearing tokens, WS, and cached host state.
  Future<void> switchServerUrl(String newUrl) async {
    final normalized = _normalize(newUrl);
    final client = ref.read(tbApiClientProvider);
    final prefs = ref.read(tbAppPreferencesProvider);
    final storage = ref.read(tbStorageProvider);
    final ws = ref.read(telemetryWsServiceProvider);

    final newGen = client.resetSessionScope('Server URL switched');
    client.switchBaseUrl(normalized);
    await ws.resetSession();
    await storage.deleteAll();
    await prefs.setServerBaseUrl(normalized);
    await prefs.setSessionMode(SessionMode.live);

    state = state.copyWith(
      baseUrl: normalized,
      mode: SessionMode.live,
      oauthClients: const [],
      clearMobileInfo: true,
      clearServerVersion: true,
      sessionGeneration: client.sessionGeneration,
    );

    if (newGen <= client.sessionGeneration) {
      await ref.read(authProvider.notifier).handleSessionInvalidated();
      await fetchPublicCapabilities();
    }
  }

  /// Atomically switches between [SessionMode.live] and [SessionMode.demo].
  Future<void> setSessionMode(
    SessionMode mode, {
    bool invalidateAuth = true,
  }) async {
    final client = ref.read(tbApiClientProvider);
    final prefs = ref.read(tbAppPreferencesProvider);
    final storage = ref.read(tbStorageProvider);
    final ws = ref.read(telemetryWsServiceProvider);

    final gen = client.resetSessionScope('SessionMode changed to ${mode.name}');
    await ws.resetSession();
    if (mode == SessionMode.demo) {
      await storage.deleteAll();
    }
    await prefs.setSessionMode(mode);

    state = state.copyWith(
      mode: mode,
      clearServerVersion: true,
      sessionGeneration: gen,
    );

    if (invalidateAuth) {
      await ref.read(authProvider.notifier).handleSessionInvalidated();
    }
  }

  static String _normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return ThingsboardAppConstants.thingsBoardApiEndpoint;
    }
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'https://$trimmed';
    return withScheme.endsWith('/') ? withScheme : '$withScheme/';
  }
}

final serverConfigProvider =
    NotifierProvider<ServerConfigController, ServerConfigState>(
      ServerConfigController.new,
    );
