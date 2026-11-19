import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/constants/app_constants.dart';
import 'package:thingsboard_democloud_app/main.dart';

void main() {
  testWidgets('Login & Forgot Password UI replica smoke test', (
    WidgetTester tester,
  ) async {
    expect(
      ThingsboardAppConstants.thingsBoardApiEndpoint,
      'https://thingsboard.democloud.xyz/',
    );

    await tester.pumpWidget(
      const ProviderScope(child: ThingsboardDemoCloudApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Login to your account'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });
}
