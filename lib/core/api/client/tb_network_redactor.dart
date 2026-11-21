import 'dart:convert';

/// Masks credentials before anything reaches the in-app network inspector.
///
/// The inspector keeps recent requests in memory and shows them on screen, so
/// passwords, JWTs, OTP codes, device access tokens and QR login secrets must
/// never be stored there. All methods are pure and never mutate their input.
abstract final class TbNetworkRedactor {
  static const String mask = '***';

  /// Exact normalised names (lower case, no `_`/`-`/space) that are secrets but
  /// contain none of the keywords in [_sensitiveFragments].
  static const Set<String> _sensitiveKeys = {
    'otp',
    'pin',
    'passcode',
    'verificationcode',
    'emailcode',
    'smscode',
    'credentialsid', // device ACCESS_TOKEN lives here
    'credentialsvalue',
  };

  /// A normalised key containing any of these is a secret, so new field names
  /// are covered without a code change (activateToken, idToken, confirmPassword,
  /// clientSecret, ...). `statusCode`/`errorCode` stay readable on purpose.
  static const List<String> _sensitiveFragments = [
    'password',
    'token',
    'secret',
    'apikey',
  ];

  static final RegExp _separators = RegExp(r'[_\-\s]');
  static final RegExp _headerHints = RegExp(r'auth|token|cookie|secret|key');
  static final RegExp _kvInText = RegExp(
    r'(\b[\w\-]*(?:password|token|secret|apikey)[\w\-]*'
    r'|\b(?:verificationCode|emailCode|smsCode|passcode|otp|pin|credentialsId|credentialsValue))'
    r'=([^&\s"]+)',
    caseSensitive: false,
  );
  static final RegExp _jsonPairInText = RegExp(
    r'"([^"\\]+)"\s*:\s*"((?:[^"\\]|\\.)*)"',
  );
  static final RegExp _jsonTruncatedInText = RegExp(
    r'"([^"\\]+)"\s*:\s*"[^"]*$',
  );
  static final RegExp _qrInText = RegExp(r'(/noauth/qr/)[^/?\s"]+');

  static bool isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(_separators, '');
    return _sensitiveKeys.contains(normalized) ||
        _sensitiveFragments.any(normalized.contains);
  }

  /// Deep copy of a JSON-like body with sensitive values masked.
  static dynamic redactBody(dynamic body) {
    if (body is Map) {
      return <dynamic, dynamic>{
        for (final entry in body.entries)
          entry.key:
              entry.value != null &&
                  entry.key is String &&
                  isSensitiveKey(entry.key as String)
              ? mask
              : redactBody(entry.value),
      };
    }
    if (body is List) {
      return <dynamic>[for (final value in body) redactBody(value)];
    }
    if (body is String) {
      final trimmed = body.trimLeft();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return jsonEncode(redactBody(jsonDecode(body)));
        } catch (_) {
          return redactText(body);
        }
      }
      return redactText(body);
    }
    return body;
  }

  /// Masks sensitive query parameters and the QR login secret in a URL.
  static String redactUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return redactText(url);

    final segments = uri.pathSegments;
    final qrIndex = segments.indexOf('qr');
    final hasQrSecret =
        qrIndex >= 1 &&
        segments[qrIndex - 1] == 'noauth' &&
        qrIndex + 1 < segments.length;
    final query = uri.queryParametersAll;
    final hasSensitiveQuery = query.keys.any(isSensitiveKey);
    final hasUserInfo = uri.userInfo.isNotEmpty; // https://user:PASS@host
    if (!hasQrSecret && !hasSensitiveQuery && !hasUserInfo) return url;

    return uri
        .replace(
          userInfo: hasUserInfo ? mask : null,
          pathSegments: hasQrSecret
              ? [
                  ...segments.take(qrIndex + 1),
                  mask,
                  ...segments.skip(qrIndex + 2),
                ]
              : null,
          queryParameters: hasSensitiveQuery
              ? {
                  for (final entry in query.entries)
                    entry.key: isSensitiveKey(entry.key)
                        ? [for (final _ in entry.value) mask]
                        : entry.value,
                }
              : null,
        )
        .toString();
  }

  /// Masks `key=value` secrets, `"key": "value"` JSON fragments (also cut off
  /// mid-value) and QR paths inside free text such as error messages.
  static String redactText(String text) => text
      .replaceAllMapped(_kvInText, (m) => '${m[1]}=$mask')
      .replaceAllMapped(
        _jsonPairInText,
        (m) => isSensitiveKey(m[1]!) ? '"${m[1]}": "$mask"' : m[0]!,
      )
      .replaceAllMapped(
        _jsonTruncatedInText,
        (m) => isSensitiveKey(m[1]!) ? '"${m[1]}": "$mask' : m[0]!,
      )
      .replaceAllMapped(_qrInText, (m) => '${m[1]}$mask');

  /// Masks credential-bearing headers (authorization, tokens, cookies, keys).
  ///
  /// Authorization-style headers keep the familiar `Bearer ***` shape.
  static Map<String, dynamic> redactHeaders(Map<String, dynamic> headers) => {
    for (final entry in headers.entries)
      entry.key: switch (entry.key.toLowerCase()) {
        final key when key.contains('auth') => 'Bearer $mask',
        final key when _headerHints.hasMatch(key) => mask,
        _ => entry.value,
      },
  };
}
