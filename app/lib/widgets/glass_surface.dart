import 'package:flutter/material.dart';

import '../theme/crease_theme.dart';

/// Crisp architectural elevated surface used for cards and bottom sheets.
/// Replaces heavy BackdropFilter blurs with high-contrast solid surfaces,
/// 1px hairline borders, and subtle tinted elevation so frames stay locked
/// at 60–120fps even on budget Android phones in bright sunlight.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(CreaseRadius.card),
    ),
    this.borderColor,
    this.borderWidth = 1.0,
    this.fillColor,
    this.padding,
    this.blurSigma = 0.0,
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

    final borderSide = BorderSide(
      color: borderColor ?? c.hairline,
      width: borderWidth,
    );

    return Container(
      decoration: BoxDecoration(
        color: fillColor ?? (isBottomSheet ? c.surfaceSheet : c.surfaceGlass),
        borderRadius: borderRadius,
        border: isBottomSheet
            ? Border(top: borderSide, left: borderSide, right: borderSide)
            : Border.fromBorderSide(borderSide),
        boxShadow: elevationShadow
            ? [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: isBottomSheet ? 0.45 : 0.24)
                      : const Color(0xFF101315).withValues(
                          alpha: isBottomSheet ? 0.08 : 0.035,
                        ),
                  blurRadius: isBottomSheet ? 24 : 10,
                  offset: Offset(0, isBottomSheet ? -4 : 2),
                  spreadRadius: isBottomSheet ? 0 : -2,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Padding(
          padding: effectivePadding ?? EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }
}
