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
            padding: padding,
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

