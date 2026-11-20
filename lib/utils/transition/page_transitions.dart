import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';

/// Material 3 GPU-safe page transition builder honoring `disableAnimations`.
class FadeOpenPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeOpenPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double>? secondaryAnimation,
    Widget child,
  ) {
    if (context != null && MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return FadeOpenPageTransition(routeAnimation: animation, child: child);
  }
}

class FadeOpenPageTransition extends StatelessWidget {
  FadeOpenPageTransition({
    super.key,
    required Animation<double> routeAnimation,
    required this.child,
  }) : _positionAnimation = routeAnimation.drive(
         _leftRightTween.chain(_fastOutSlowInTween),
       ),
       _opacityAnimation = routeAnimation.drive(_easeInTween);

  static final Tween<Offset> _leftRightTween = Tween<Offset>(
    begin: const Offset(0.18, 0.0),
    end: Offset.zero,
  );
  static final Animatable<double> _fastOutSlowInTween = CurveTween(
    curve: Curves.easeOutCubic,
  );
  static final Animatable<double> _easeInTween = CurveTween(
    curve: Curves.easeIn,
  );

  final Animation<Offset> _positionAnimation;
  final Animation<double> _opacityAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return SlideTransition(
      position: _positionAnimation,
      child: FadeTransition(opacity: _opacityAnimation, child: child),
    );
  }
}

/// GoRouter M3 fade-through / shared-axis transition page with reduced-motion fallback.
CustomTransitionPage<T> tbFadeThroughTransitionPage<T>({
  required LocalKey key,
  required Widget child,
  Duration duration = DesignTokens.motionMedium,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: DesignTokens.motionFast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) {
        return child;
      }
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      final slide = Tween<Offset>(
        begin: const Offset(0.04, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}
