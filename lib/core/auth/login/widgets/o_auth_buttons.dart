import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/constants/assets_path.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/o_auth_button.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

class OAuth2ClientInfo {
  const OAuth2ClientInfo({required this.name, required this.icon, this.url});

  factory OAuth2ClientInfo.fromModel(OAuth2ClientModel model) =>
      OAuth2ClientInfo(name: model.name, icon: model.icon, url: model.url);

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
    if (clients.isEmpty) {
      return const SizedBox.shrink();
    }

    if (clients.length == 1 && clients.first.name == 'qr') {
      return Center(
        child: OAuthButton(
          logo: _getOauth2ButtonLogo(context, clients.first),
          onTap: () => onButtonPressed(clients.first),
          title: 'Scan QR code',
          semanticLabel: 'Scan QR code',
        ),
      );
    }

    return Wrap(
      spacing: DesignTokens.spacing8,
      runSpacing: DesignTokens.spacing8,
      alignment: WrapAlignment.center,
      children: clients
          .map(
            (e) => OAuthButton(
              logo: _getOauth2ButtonLogo(context, e),
              title: e.name == 'qr' ? 'QR' : e.name,
              semanticLabel: e.name == 'qr'
                  ? 'Scan QR code'
                  : 'Sign in with ${e.name}',
              onTap: () => onButtonPressed(e),
            ),
          )
          .toList(),
    );
  }
}

const _monochromeLogos = {
  'github-logo',
  'apple-logo',
  'qr-code',
  'qr-code-logo',
};

Widget _getOauth2ButtonLogo(BuildContext context, OAuth2ClientInfo info) {
  if (info.name == 'qr' ||
      info.icon == 'qr-code-logo' ||
      info.icon == 'qr-code') {
    return TbIcon(
      TbIconKind.qrFrame,
      size: DesignTokens.iconSmall,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  final String? svgPath = ThingsboardImage.oauth2Logos[info.icon];
  if (svgPath != null) {
    return SizedBox(
      width: DesignTokens.iconSmall,
      height: DesignTokens.iconSmall,
      child: SvgPicture.asset(
        svgPath,
        colorFilter: _monochromeLogos.contains(info.icon)
            ? ColorFilter.mode(
                Theme.of(context).colorScheme.primary,
                BlendMode.srcIn,
              )
            : null,
      ),
    );
  }

  return TbIcon(
    TbIconKind.gateway,
    size: DesignTokens.iconSmall,
    color: Theme.of(context).colorScheme.primary,
  );
}
