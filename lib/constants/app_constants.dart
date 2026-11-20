abstract final class ThingsboardAppConstants {
  static const defaultApiEndpoint = 'https://thingsboard.democloud.xyz/';

  static const thingsBoardApiEndpoint = String.fromEnvironment(
    'thingsboardApiEndpoint',
    defaultValue: defaultApiEndpoint,
  );

  static const thingsboardOAuth2CallbackUrlScheme = String.fromEnvironment(
    'thingsboardOAuth2CallbackUrlScheme',
    defaultValue: 'org.thingsboard.pe.app.auth',
  );

  static const thingsboardIOSAppSecret = String.fromEnvironment(
    'thingsboardIosAppSecret',
  );

  static const thingsboardAndroidAppSecret = String.fromEnvironment(
    'thingsboardAndroidAppSecret',
  );

  static const ignoreRegionSelection = true;
}
