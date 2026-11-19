import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:thingsboard_democloud_app/constants/assets_path.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/o_auth_button.dart';

class OAuth2ClientInfo {
  const OAuth2ClientInfo({
    required this.name,
    required this.icon,
    this.url,
  });

  final String name;
  final String icon;
  final String? url;
}

class OAuthButtons extends StatelessWidget {
  const OAuthButtons({
    super.key,
    required this.clients,
    required this.onButtonPressed,
  });
  final void Function(OAuth2ClientInfo) onButtonPressed;
  final List<OAuth2ClientInfo> clients;

  @override
  Widget build(BuildContext context) {
    return clients.length == 1 && clients.first.name == 'qr'
        ? Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OAuthButton(
              logo: SvgPicture.asset(
                ThingsboardImage.oauth2Logos['qr-code-logo']!,
                colorFilter: ColorFilter.mode(
                  Theme.of(context).colorScheme.primary,
                  BlendMode.srcIn,
                ),
              ),
              onTap: () => onButtonPressed(clients.first),
              title: 'Scan QR code',
            ),
          ],
        )
        : Row(
          spacing: 10,
          children:
              clients
                  .map(
                    (e) => Expanded(
                      child: OAuthButton(
                        logo: _getOauth2ButtonLogo(context, e),
                        onTap: () => onButtonPressed(e),
                      ),
                    ),
                  )
                  .toList(),
        );
  }
}

const _monochromeLogos = {'github-logo', 'apple-logo', 'qr-code', 'qr-code-logo'};

Widget _getOauth2ButtonLogo(BuildContext context, OAuth2ClientInfo info) {
  final String? svgPath = ThingsboardImage.oauth2Logos[info.icon];

  if (svgPath != null) {
    return SizedBox(
      width: 24,
      height: 24,
      child: SvgPicture.asset(
        svgPath,
        colorFilter:
            _monochromeLogos.contains(info.icon)
                ? ColorFilter.mode(
                  Theme.of(context).colorScheme.primary,
                  BlendMode.srcIn,
                )
                : null,
      ),
    );
  }

  return const SizedBox(width: 24, height: 24, child: Icon(Icons.login));
}
