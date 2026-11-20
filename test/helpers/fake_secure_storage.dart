import 'package:thingsboard_democloud_app/core/api/client/tb_secure_storage.dart';

/// In-memory [TbStorage] fake for unit tests.
class FakeSecureStorage implements TbStorage {
  FakeSecureStorage({Map<String, String>? initial})
    : _store = Map<String, String>.from(initial ?? const {});

  final Map<String, String> _store;
  Object? errorOnRead;
  Object? errorOnWrite;

  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_store);

  @override
  Future<String?> read(String key) async {
    if (errorOnRead != null) throw errorOnRead!;
    return _store[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (errorOnWrite != null) throw errorOnWrite!;
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _store.clear();
  }
}
