import 'package:flutter/material.dart';

class AnimatedVisibilityWidget extends StatelessWidget {
  const AnimatedVisibilityWidget({
    super.key,
    required this.show,
    required this.child,
  });

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: show ? child : const SizedBox.shrink(),
    );
  }
}
