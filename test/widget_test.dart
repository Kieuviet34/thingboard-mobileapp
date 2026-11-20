import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/constants/app_constants.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/main.dart';

import 'helpers/fake_app_preferences.dart';
import 'helpers/fake_secure_storage.dart';
import 'helpers/fake_ws_channel.dart';
import 'helpers/mock_dio_adapter.dart';

void main() {
  testWidgets('Login & Forgot Password UI replica smoke test', (
    WidgetTester tester,
  ) async {
    expect(
      ThingsboardAppConstants.thingsBoardApiEndpoint,
      'https://thingsboard.democloud.xyz/',
    );

    final adapter = MockDioAdapter();
    adapter.on(
      'GET',
      '/api/noauth/userPasswordPolicy',
      (_) => MockDioAdapter.jsonResponse({'minimumLength': 6}),
    );
    adapter.on(
      'POST',
      '/api/noauth/oauth2Clients',
      (_) => MockDioAdapter.jsonResponse([]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tbStorageProvider.overrideWithValue(FakeSecureStorage()),
          tbAppPreferencesProvider.overrideWithValue(FakeAppPreferences()),
          tbHttpClientAdapterProvider.overrideWithValue(adapter),
          wsChannelFactoryProvider.overrideWithValue(
            (_) => FakeWebSocketChannel(),
          ),
        ],
        child: const ThingsboardDemoCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Login to your account'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Try Demo Mode'), findsOneWidget);
  });
}
