import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/auth_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/tenant_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/tenant_repository.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';
import 'package:thingsboard_democloud_app/core/models/user_models.dart';
import 'package:thingsboard_democloud_app/modules/tenant/tenant_page.dart';
import 'package:thingsboard_democloud_app/widgets/tb_list_row.dart';
import 'package:thingsboard_democloud_app/widgets/tb_metric_pill.dart';
import 'package:thingsboard_democloud_app/widgets/tb_section_card.dart';

import '../../helpers/fake_app_preferences.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_ws_channel.dart';
import '../../helpers/mock_dio_adapter.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._state);
  final AuthState _state;

  @override
  Future<AuthState> build() async => _state;
}

class _DemoServerController extends ServerConfigController {
  @override
  ServerConfigState build() => const ServerConfigState(
    baseUrl: 'https://thingsboard.democloud.xyz/',
    mode: SessionMode.demo,
  );
}

AuthAuthenticated _authFor(Authority authority) {
  return AuthAuthenticated(
    session: TbAuthSession(
      accessToken: 'jwt',
      refreshToken: 'refresh',
      userId: 'u-1',
      email: 'admin@democloud.xyz',
      authority: authority,
      tenantId: 'demo-tenant-1',
    ),
    user: TbUserProfile(
      id: 'u-1',
      email: 'admin@democloud.xyz',
      authority: authority,
      tenantId: 'demo-tenant-1',
      firstName: 'Tenant',
      lastName: 'Admin',
    ),
    mode: SessionMode.demo,
  );
}

void main() {
  Widget buildApp({
    required Authority authority,
    TenantRepository? repo,
    ThemeData? theme,
    double textScale = 1.0,
  }) {
    final tenantRepo = repo ?? DemoTenantRepository();
    return ProviderScope(
      overrides: [
        tbStorageProvider.overrideWithValue(FakeSecureStorage()),
        tbAppPreferencesProvider.overrideWithValue(
          FakeAppPreferences(sessionMode: SessionMode.demo),
        ),
        tbHttpClientAdapterProvider.overrideWithValue(MockDioAdapter()),
        wsChannelFactoryProvider.overrideWithValue(
          (_) => FakeWebSocketChannel(),
        ),
        serverConfigProvider.overrideWith(_DemoServerController.new),
        authProvider.overrideWith(
          () => _StubAuthController(_authFor(authority)),
        ),
        tenantRepositoryProvider.overrideWithValue(tenantRepo),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: MaterialApp(
          theme: theme ?? tbLightTheme(),
          home: const TenantPage(),
        ),
      ),
    );
  }

  group('TenantPage M3 UI & RBAC tests', () {
    testWidgets(
      'TENANT_ADMIN views overview, edits tenant title, and switches to Views & Edges tabs',
      (tester) async {
        final demoRepo = DemoTenantRepository();
        await tester.pumpWidget(
          buildApp(authority: Authority.tenantAdmin, repo: demoRepo),
        );
        await tester.pumpAndSettle();

        expect(find.text('ThingsBoard DemoCloud Tenant'), findsOneWidget);
        expect(find.byType(TbMetricPill), findsWidgets);

        final editBtn = find.byKey(const Key('edit_tenant_button'));
        final editSize = tester.getSize(editBtn);
        expect(
          editSize.width,
          greaterThanOrEqualTo(DesignTokens.minTouchTarget),
        );
        expect(
          editSize.height,
          greaterThanOrEqualTo(DesignTokens.minTouchTarget),
        );

        await tester.tap(editBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('tenant_title_field')),
          'Updated DemoCloud Org',
        );
        await tester.tap(find.byKey(const Key('save_tenant_button')));
        await tester.pumpAndSettle();

        expect(find.text('Updated DemoCloud Org'), findsOneWidget);

        // Switch to Entity Views tab
        await tester.tap(find.text('Views'));
        await tester.pumpAndSettle();
        expect(find.text('Public Flood Telemetry View'), findsOneWidget);

        // Switch to Edges tab
        await tester.tap(find.text('Edges'));
        await tester.pumpAndSettle();
        expect(find.text('Flood Station Edge GW-01'), findsOneWidget);
      },
    );

    testWidgets(
      'SYS_ADMIN lists tenants, creates a new tenant, and switches to Profiles tab',
      (tester) async {
        final demoRepo = DemoTenantRepository();
        await tester.pumpWidget(
          buildApp(authority: Authority.sysAdmin, repo: demoRepo),
        );
        await tester.pumpAndSettle();

        expect(find.text('Regional Water Authority'), findsOneWidget);

        await tester.tap(find.byKey(const Key('add_tenant_fab')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('tenant_title_field')),
          'New Metro Tenant',
        );
        await tester.tap(find.byKey(const Key('save_tenant_button')));
        await tester.pumpAndSettle();

        expect(find.text('New Metro Tenant'), findsOneWidget);

        // Switch to Profiles tab
        await tester.tap(find.text('Profiles'));
        await tester.pumpAndSettle();
        expect(find.text('Enterprise IoT'), findsOneWidget);
      },
    );

    testWidgets('TENANT_ADMIN overview, views and edges use section cards', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp(authority: Authority.tenantAdmin));
      await tester.pumpAndSettle();

      expect(find.text('Organization'), findsOneWidget);
      expect(find.byType(TbSectionCard), findsWidgets);
      expect(find.byType(TbListRow), findsWidgets);

      await tester.tap(find.text('Views'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(TbSectionCard),
          matching: find.text('Views'),
        ),
        findsOneWidget,
      );
      expect(find.byType(TbListRow), findsWidgets);

      await tester.tap(find.text('Edges').first);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(TbSectionCard),
          matching: find.text('Edges'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SYS_ADMIN tenant row opens editor with Details and Contact', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp(authority: Authority.sysAdmin));
      await tester.pumpAndSettle();

      expect(find.byType(TbListRow), findsWidgets);
      final row = find.ancestor(
        of: find.text('Regional Water Authority'),
        matching: find.byType(TbListRow),
      );
      final size = tester.getSize(row);
      expect(size.height, greaterThanOrEqualTo(DesignTokens.minTouchTarget));

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.text('Edit Tenant'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Contact'), findsOneWidget);
      expect(find.byKey(const Key('tenant_title_field')), findsOneWidget);
    });

    testWidgets(
      'CUSTOMER_USER sees Access Restricted state and Dark 2.0x text scale renders cleanly',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            authority: Authority.customerUser,
            theme: tbDarkTheme(),
            textScale: 2.0,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Access Restricted'), findsOneWidget);
      },
    );
  });
}
