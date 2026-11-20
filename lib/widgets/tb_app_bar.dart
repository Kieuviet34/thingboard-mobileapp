import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';

/// Material 3 app bar with accessible `>=48dp` back control and optional progress bar.
class TbAppBar extends StatelessWidget implements PreferredSizeWidget {
  TbAppBar({
    super.key,
    this.leading,
    this.title,
    this.actions,
    this.elevation = 0,
    this.shadowColor,
    this.showLoadingIndicator = false,
    this.canGoBack = true,
    this.backIcon,
  }) : preferredSize = Size.fromHeight(
         kToolbarHeight + (showLoadingIndicator ? 4 : 0),
       );

  final Widget? leading;
  final Widget? title;
  final List<Widget>? actions;
  final double? elevation;
  final Color? shadowColor;
  final bool showLoadingIndicator;
  final bool canGoBack;
  final Widget? backIcon;

  @override
  final Size preferredSize;

  @override
  Widget build(BuildContext context) {
    final leadingWidget = getLeading(context);
    final isEmptyLeading = leadingWidget is EmptyLeading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppBar(
          automaticallyImplyLeading: false,
          leadingWidth: isEmptyLeading ? 16 : DesignTokens.minTouchTarget,
          titleSpacing: isEmptyLeading ? 0 : DesignTokens.spacing4,
          leading: leadingWidget,
          title: buildTitle(context),
          actions: actions,
          elevation: elevation,
          shadowColor: shadowColor,
          centerTitle: false,
        ),
        if (showLoadingIndicator) const LinearProgressIndicator(),
      ],
    );
  }

  Widget getLeading(BuildContext context) {
    if (leading != null) return leading!;

    final router = GoRouter.maybeOf(context);
    if (canGoBack && router != null && router.canPop()) {
      return IconButton(
        tooltip: 'Back',
        constraints: const BoxConstraints(
          minWidth: DesignTokens.minTouchTarget,
          minHeight: DesignTokens.minTouchTarget,
        ),
        icon: backIcon ?? const Icon(Icons.arrow_back),
        onPressed: router.pop,
      );
    }
    return const EmptyLeading();
  }

  Widget? buildTitle(BuildContext context) {
    if (title == null) return null;
    if (title is Text) {
      final text = title! as Text;
      final baseStyle = text.style ?? Theme.of(context).textTheme.titleLarge;
      return AutoSizeText(
        text.data ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
        minFontSize: 12,
      );
    }
    return title;
  }
}

class EmptyLeading extends StatelessWidget {
  const EmptyLeading({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
