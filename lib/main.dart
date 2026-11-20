import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/routes/router.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_theme_utils.dart';
import 'package:toastification/toastification.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  runApp(const ProviderScope(child: ThingsboardDemoCloudApp()));
}

class ThingsboardDemoCloudApp extends ConsumerWidget {
  const ThingsboardDemoCloudApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return ToastificationWrapper(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'ThingsBoard PE',
        themeMode: themeMode,
        theme: tbLightTheme(),
        darkTheme: tbDarkTheme(),
        routerConfig: router,
      ),
    );
  }
}
