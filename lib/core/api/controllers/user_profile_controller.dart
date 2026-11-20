import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_secure_storage.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/server_config_controller.dart';
import 'package:thingsboard_democloud_app/core/api/repositories/user_profile_repository.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/user_models.dart';

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  final sessionScope = ref.watch(
    serverConfigProvider.select((s) => (s.mode, s.sessionGeneration)),
  );
  if (sessionScope.$1 == SessionMode.demo) {
    return DemoUserProfileRepository(ref.read(userProfileProvider));
  }
  return RestUserProfileRepository(client: ref.watch(tbApiClientProvider));
});

/// Authenticated user profile, settings, and password-change controller.
class UserProfileController extends AutoDisposeAsyncNotifier<TbUserProfile> {
  @override
  Future<TbUserProfile> build() {
    return ref.watch(userProfileRepositoryProvider).getUserProfile();
  }

  Future<void> updateProfile(TbUserProfile updated) async {
    final saved = await ref
        .read(userProfileRepositoryProvider)
        .updateUserProfile(updated);
    state = AsyncData(saved);
  }

  Future<void> updateGeneralSettings(Map<String, dynamic> settings) async {
    await ref
        .read(userProfileRepositoryProvider)
        .updateGeneralSettings(settings);
    ref.invalidate(userGeneralSettingsProvider);
  }

  /// Changes password and persists the returned fresh `JwtPair` in [TbStorage].
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final mode = ref.read(serverConfigProvider).mode;
    final pair = await ref
        .read(userProfileRepositoryProvider)
        .changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
    if (mode == SessionMode.live && pair.token.isNotEmpty) {
      final storage = ref.read(tbStorageProvider);
      await storage.write(TbStorageKeys.accessToken, pair.token);
      if (pair.refreshToken != null && pair.refreshToken!.isNotEmpty) {
        await storage.write(TbStorageKeys.refreshToken, pair.refreshToken!);
      }
    }
  }
}

final userProfileControllerProvider =
    AsyncNotifierProvider.autoDispose<UserProfileController, TbUserProfile>(
      UserProfileController.new,
    );

final userGeneralSettingsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
      return ref.watch(userProfileRepositoryProvider).getGeneralSettings();
    });
