import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:thingsboard_democloud_app/config/themes/app_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';

class QrCodeScannerPage extends StatelessWidget {
  const QrCodeScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cameraBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Scan QR code',
          style: TbTextStyles.titleXs.copyWith(color: Colors.white),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(
                  Icons.qr_code_scanner,
                  color: Colors.white70,
                  size: 80,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Align QR code within the frame to login',
              style: TbTextStyles.bodyMedium.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
