import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_secure_storage.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/auth_repository.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/core/models/user_models.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final mode = ref.watch(serverConfigProvider.select((s) => s.mode));
  if (mode == SessionMode.demo) {
    return DemoAuthRepository();
  }
  return RestAuthRepository(client: ref.watch(tbApiClientProvider));
});

/// Manages JWT login/refresh/2FA/QR/OAuth2/Demo authentication lifecycle.
class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    await ref.read(serverConfigProvider.notifier).initialize();

    final mode = ref.read(serverConfigProvider).mode;
    if (mode == SessionMode.demo) {
      return const AuthUnauthenticated();
    }

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;
    final storage = ref.read(tbStorageProvider);
    final token = await storage.read(TbStorageKeys.accessToken);
    final refreshToken = await storage.read(TbStorageKeys.refreshToken);

    if (gen != client.sessionGeneration) {
      return const AuthUnauthenticated();
    }
    if (token == null || token.isEmpty) {
      return const AuthUnauthenticated();
    }

    try {
      final validToken = await client.coordinator.getAccessTokenForRequest();
      if (gen != client.sessionGeneration ||
          validToken == null ||
          validToken.isEmpty) {
        return const AuthUnauthenticated();
      }
      final currentRefresh =
          await storage.read(TbStorageKeys.refreshToken) ?? refreshToken ?? '';
      final user = await ref.read(authRepositoryProvider).getCurrentUser();
      if (gen != client.sessionGeneration) {
        return const AuthUnauthenticated();
      }

      final session = _buildSession(
        accessToken: validToken,
        refreshToken: currentRefresh,
        user: user,
      );
      unawaited(ref.read(telemetryWsServiceProvider).connect());
      unawaited(ref.read(serverConfigProvider.notifier).probeServerVersion());
      return AuthAuthenticated(
        session: session,
        user: user,
        mode: SessionMode.live,
      );
    } catch (_) {
      if (gen == client.sessionGeneration) {
        await storage.deleteAll();
      }
      return const AuthUnauthenticated();
    }
  }

  /// Authenticates with ThingsBoard PE username/password (handling 2FA scopes).
  Future<void> login(String email, String password) async {
    final configCtrl = ref.read(serverConfigProvider.notifier);
    if (ref.read(serverConfigProvider).mode != SessionMode.live) {
      await configCtrl.setSessionMode(SessionMode.live, invalidateAuth: false);
    }

    final client = ref.read(tbApiClientProvider);
    final gen = client.resetSessionScope('Login started');
    final repo = ref.read(authRepositoryProvider);

    state = const AsyncLoading<AuthState>();
    try {
      final loginResp = await repo.login(email.trim(), password);
      if (gen != client.sessionGeneration) return;
      await _processLoginResponse(loginResp, gen: gen, mode: SessionMode.live);
    } catch (error, stackTrace) {
      if (gen != client.sessionGeneration) return;
      state = AsyncError<AuthState>(error, stackTrace);
    }
  }

  /// Enters offline Demo Mode backed by deterministic seeded repositories.
  Future<void> loginDemo() async {
    final configCtrl = ref.read(serverConfigProvider.notifier);
    await configCtrl.setSessionMode(SessionMode.demo, invalidateAuth: false);

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;
    final repo = ref.read(authRepositoryProvider);

    final loginResp = await repo.login('tenant@thingsboard.org', 'demo');
    final user = await repo.getCurrentUser();
    if (gen != client.sessionGeneration) return;

    final session = _buildSession(
      accessToken: loginResp.token,
      refreshToken: loginResp.refreshToken ?? '',
      user: user,
    );
    state = AsyncData<AuthState>(
      AuthAuthenticated(session: session, user: user, mode: SessionMode.demo),
    );
  }

  /// Completes 2FA verification for [AuthMfaVerificationRequired].
  Future<void> verifyTwoFa({
    required String providerType,
    required String verificationCode,
  }) async {
    final current = state.valueOrNull;
    if (current is! AuthMfaVerificationRequired) return;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;
    final repo = ref.read(authRepositoryProvider);

    final loginResp = await repo.checkTwoFaVerificationCode(
      preAuthToken: current.preAuthToken,
      providerType: providerType,
      verificationCode: verificationCode,
    );
    if (gen != client.sessionGeneration) return;
    await _processLoginResponse(loginResp, gen: gen, mode: SessionMode.live);
  }

  /// Requests an OTP code for [AuthMfaVerificationRequired].
  Future<void> sendTwoFaCode(String providerType) async {
    final current = state.valueOrNull;
    if (current is! AuthMfaVerificationRequired) return;
    await ref
        .read(authRepositoryProvider)
        .sendTwoFaVerificationCode(
          preAuthToken: current.preAuthToken,
          providerType: providerType,
        );
  }

  /// Completes mandatory MFA configuration for [AuthMfaConfigurationRequired].
  Future<void> completeMfaConfiguration() async {
    final current = state.valueOrNull;
    if (current is! AuthMfaConfigurationRequired) return;

    final client = ref.read(tbApiClientProvider);
    final gen = client.sessionGeneration;
    final repo = ref.read(authRepositoryProvider);

    final loginResp = await repo.authenticateByMfaConfigurationToken(
      current.preAuthToken,
    );
    if (gen != client.sessionGeneration) return;
    await _processLoginResponse(loginResp, gen: gen, mode: SessionMode.live);
  }

  /// Cancels an in-progress 2FA/MFA flow and returns to unauthenticated state.
  void cancelMfa() {
    ref.read(tbApiClientProvider).resetSessionScope('MFA cancelled');
    state = const AsyncData<AuthState>(AuthUnauthenticated());
  }

  /// Exchanges a scanned QR login secret for a JWT session.
  Future<void> loginWithQrSecret(String secret) async {
    final configCtrl = ref.read(serverConfigProvider.notifier);
    if (ref.read(serverConfigProvider).mode != SessionMode.live) {
      await configCtrl.setSessionMode(SessionMode.live, invalidateAuth: false);
    }
    final client = ref.read(tbApiClientProvider);
    final gen = client.resetSessionScope('QR login');
    state = const AsyncLoading<AuthState>();
    try {
      final resp = await ref
          .read(authRepositoryProvider)
          .loginByQrSecret(secret);
      if (gen != client.sessionGeneration) return;
      await _processLoginResponse(resp, gen: gen, mode: SessionMode.live);
    } catch (error, stackTrace) {
      if (gen != client.sessionGeneration) return;
      state = AsyncError<AuthState>(error, stackTrace);
    }
  }

  /// Completes external OAuth2 callback deep-link delivery.
  Future<void> completeOAuth2({
    required String accessToken,
    String? refreshToken,
  }) async {
    final configCtrl = ref.read(serverConfigProvider.notifier);
    if (ref.read(serverConfigProvider).mode != SessionMode.live) {
      await configCtrl.setSessionMode(SessionMode.live, invalidateAuth: false);
    }
    final client = ref.read(tbApiClientProvider);
    final gen = client.resetSessionScope('OAuth2 login');
    state = const AsyncLoading<AuthState>();
    try {
      await _processLoginResponse(
        LoginResponse(token: accessToken, refreshToken: refreshToken),
        gen: gen,
        mode: SessionMode.live,
      );
    } catch (error, stackTrace) {
      if (gen != client.sessionGeneration) return;
      state = AsyncError<AuthState>(error, stackTrace);
    }
  }

  Future<void> requestPasswordReset(String email) {
    return ref.read(authRepositoryProvider).requestPasswordReset(email.trim());
  }

  /// Signs out, increments `sessionGeneration`, closes WS, and clears stored secrets.
  Future<void> logout() async {
    final mode = ref.read(serverConfigProvider).mode;
    final client = ref.read(tbApiClientProvider);
    final repo = ref.read(authRepositoryProvider);

    if (mode == SessionMode.live) {
      try {
        await repo.logout();
      } catch (_) {
        // Best-effort server logout; always complete local cleanup.
      }
    }

    client.resetSessionScope('User logout');
    await ref.read(telemetryWsServiceProvider).resetSession();
    await ref.read(tbStorageProvider).deleteAll();
    state = const AsyncData<AuthState>(AuthUnauthenticated());
  }

  /// Re-reads the rotated JWT pair from storage (after `changePassword`),
  /// refreshes the session in [AuthState] and re-authenticates the shared WS.
  Future<void> syncSessionTokens() async {
    final current = state.valueOrNull;
    if (current is! AuthAuthenticated || current.mode != SessionMode.live) {
      return;
    }
    final storage = ref.read(tbStorageProvider);
    final gen = ref.read(tbApiClientProvider).sessionGeneration;
    // Logout / host switch / invalidation during the awaits discards the result.
    bool stale() =>
        gen != ref.read(tbApiClientProvider).sessionGeneration ||
        !identical(state.valueOrNull, current);
    final access = await storage.read(TbStorageKeys.accessToken);
    if (stale() || access == null || access.isEmpty) return;
    final refresh =
        await storage.read(TbStorageKeys.refreshToken) ??
        current.session.refreshToken;
    if (stale()) return;
    state = AsyncData<AuthState>(
      AuthAuthenticated(
        session: _buildSession(
          accessToken: access,
          refreshToken: refresh,
          user: current.user,
        ),
        user: current.user,
        mode: current.mode,
      ),
    );
    await ref.read(telemetryWsServiceProvider).reauthenticate();
  }

  /// Invoked when background token refresh fails or host/mode resets.
  Future<void> handleSessionInvalidated() async {
    await ref.read(telemetryWsServiceProvider).resetSession();
    state = const AsyncData<AuthState>(AuthUnauthenticated());
  }

  Future<void> _processLoginResponse(
    LoginResponse loginResp, {
    required int gen,
    required SessionMode mode,
  }) async {
    final client = ref.read(tbApiClientProvider);
    final repo = ref.read(authRepositoryProvider);
    final storage = ref.read(tbStorageProvider);

    if (loginResp.scope == Authority.preVerificationToken) {
      final providers = await repo.getTwoFaProviders(loginResp.token);
      if (gen != client.sessionGeneration) return;
      state = AsyncData<AuthState>(
        AuthMfaVerificationRequired(
          preAuthToken: loginResp.token,
          providers: providers,
        ),
      );
      return;
    }

    if (loginResp.scope == Authority.mfaConfigurationToken) {
      state = AsyncData<AuthState>(
        AuthMfaConfigurationRequired(preAuthToken: loginResp.token),
      );
      return;
    }

    if (loginResp.token.isEmpty) {
      throw const TbFailure(
        type: TbFailureType.invalidCredentials,
        message: 'Empty access token received from server.',
      );
    }

    await storage.write(TbStorageKeys.accessToken, loginResp.token);
    if (loginResp.refreshToken != null && loginResp.refreshToken!.isNotEmpty) {
      await storage.write(TbStorageKeys.refreshToken, loginResp.refreshToken!);
    }

    if (gen != client.sessionGeneration) {
      await storage.deleteAll();
      return;
    }

    final user = await repo.getCurrentUser();
    if (gen != client.sessionGeneration) {
      await storage.deleteAll();
      return;
    }

    final session = _buildSession(
      accessToken: loginResp.token,
      refreshToken: loginResp.refreshToken ?? '',
      user: user,
    );

    if (mode == SessionMode.live) {
      unawaited(ref.read(telemetryWsServiceProvider).connect());
      unawaited(ref.read(serverConfigProvider.notifier).probeServerVersion());
    }

    state = AsyncData<AuthState>(
      AuthAuthenticated(session: session, user: user, mode: mode),
    );
  }

  TbAuthSession _buildSession({
    required String accessToken,
    required String refreshToken,
    required TbUserProfile user,
  }) {
    final claims = JwtDecoder.tryDecode(accessToken);
    final exp = (claims?['exp'] as num?)?.toInt();
    return TbAuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: user.id.isNotEmpty
          ? user.id
          : (claims?['userId'] as String? ?? ''),
      email: user.email.isNotEmpty
          ? user.email
          : (claims?['sub'] as String? ?? ''),
      authority: user.authority,
      tenantId: user.tenantId ?? (claims?['tenantId'] as String?),
      customerId: user.customerId ?? (claims?['customerId'] as String?),
      expiresAt: exp != null
          ? DateTime.fromMillisecondsSinceEpoch(exp * 1000)
          : null,
    );
  }
}

final authProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
