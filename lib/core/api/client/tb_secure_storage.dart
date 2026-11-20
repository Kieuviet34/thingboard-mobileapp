import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage boundary strictly for sensitive credentials (JWT access/refresh tokens, API key).
abstract interface class TbStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// Keys used in [TbStorage]. Never store non-secret preferences here.
abstract final class TbStorageKeys {
  static const accessToken = 'tb_jwt_access_token';
  static const refreshToken = 'tb_jwt_refresh_token';
  static const apiKey = 'tb_api_key';
}

/// Production [TbStorage] backed by `flutter_secure_storage`.
final class FlutterSecureStorageImpl implements TbStorage {
  FlutterSecureStorageImpl({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
