import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/crease_theme.dart';

/// Daylight Glass frosted panel with 1px hairline border and diffuse shadow.
/// Uses subtle blur so it stays smooth even on budget Android devices.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.borderColor,
    this.borderWidth = 1.0,
    this.fillColor,
    this.padding,
    this.blurSigma = 10.0,
    this.elevationShadow = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? borderColor;
  final double borderWidth;
  final Color? fillColor;
  final EdgeInsetsGeometry? padding;
  final double blurSigma;
  final bool elevationShadow;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.35)
        : const Color(0xFF0A0C0C).withValues(alpha: 0.06);

    final isBottomSheet =
        borderRadius.bottomLeft == Radius.zero &&
        borderRadius.bottomRight == Radius.zero;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomSafe = (isBottomSheet && !keyboardOpen)
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    final resolvedPadding = padding?.resolve(Directionality.of(context));
    final effectivePadding = bottomSafe > 0
        ? EdgeInsets.fromLTRB(
            resolvedPadding?.left ?? 0,
            resolvedPadding?.top ?? 0,
            resolvedPadding?.right ?? 0,
            (resolvedPadding?.bottom ?? 0) + bottomSafe,
          )
        : padding;

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: elevationShadow
            ? [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: effectivePadding,
            decoration: BoxDecoration(
              color: fillColor ?? c.surfaceGlass,
              borderRadius: borderRadius,
              border: Border.all(
                color: borderColor ?? c.hairline,
                width: borderWidth,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

