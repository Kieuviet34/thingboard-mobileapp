import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TbAppBar extends StatelessWidget implements PreferredSizeWidget {
  TbAppBar({
    super.key,
    this.leading,
    this.title,
    this.actions,
    this.elevation = 8,
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
    return Column(
      children: [
        AppBar(
          automaticallyImplyLeading: false,
          leadingWidth: leadingWidget is EmptyLeading ? 20 : 40,
          titleSpacing: 4,
          leading: leadingWidget,
          title: buildTitle(context),
          actions: actions,
          elevation: elevation ?? 8,
          shadowColor: shadowColor ?? const Color(0xFFFFFFFF).withAlpha(150),
          centerTitle: false,
        ),
        if (showLoadingIndicator) const LinearProgressIndicator(),
      ],
    );
  }

  Widget getLeading(BuildContext context) {
    if (leading != null) return leading!;

    if (canGoBack && context.canPop()) {
      return IconButton(
        icon: backIcon ?? const Icon(Icons.arrow_back),
        onPressed: context.pop,
      );
    }
    return const EmptyLeading();
  }

  Widget? buildTitle(BuildContext context) {
    if (title == null) {
      return title;
    }
    if (title is Text) {
      final text = title! as Text;
      return AutoSizeText(
        text.data ?? '',
        maxLines: 1,
        style: text.style,
        minFontSize: text.style?.fontSize ?? 12,
      );
    }
    return title;
  }
}

class EmptyLeading extends StatelessWidget {
  const EmptyLeading({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox();
  }
}
