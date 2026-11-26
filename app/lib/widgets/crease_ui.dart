import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/local_event_store.dart';
import '../theme/crease_theme.dart';

/// Minimalist geometric Crease brand emblem: popping crease line + seam mark.
class CreaseMark extends StatelessWidget {
  const CreaseMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CreaseMarkPainter(
          bg: c.pitchGreen,
          line: Colors.white,
        ),
      ),
    );
  }
}

class _CreaseMarkPainter extends CustomPainter {
  const _CreaseMarkPainter({required this.bg, required this.line});

  final Color bg;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.28),
    );
    canvas.drawRRect(rrect, Paint()..color = bg);

    final stroke = Paint()
      ..color = line
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Popping crease horizontal bar
    final creaseY = size.height * 0.68;
    canvas.drawLine(
      Offset(size.width * 0.2, creaseY),
      Offset(size.width * 0.8, creaseY),
      stroke,
    );

    // Three clean wicket/stump verticals rising behind the crease
    final topY = size.height * 0.24;
    final bottomY = size.height * 0.54;
    for (final xFrac in const [0.35, 0.5, 0.65]) {
      canvas.drawLine(
        Offset(size.width * xFrac, topY),
        Offset(size.width * xFrac, bottomY),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CreaseMarkPainter oldDelegate) =>
      oldDelegate.bg != bg || oldDelegate.line != line;
}

/// Tactile pressable wrapper with subtle physical scale-down and ripple.
/// Respects system "Remove animations" accessibility preference.
class CreasePressable extends StatefulWidget {
  const CreasePressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(CreaseRadius.card),
    ),
    this.scale = 0.985,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final double scale;

  @override
  State<CreasePressable> createState() => _CreasePressableState();
}

class _CreasePressableState extends State<CreasePressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final child = Material(
      color: Colors.transparent,
      borderRadius: widget.borderRadius,
      child: InkWell(
        borderRadius: widget.borderRadius,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onHighlightChanged: (v) {
          if (widget.onTap != null || widget.onLongPress != null) {
            _setPressed(v);
          }
        },
        child: widget.child,
      ),
    );

    if (disableAnim) return child;
    return AnimatedScale(
      scale: _pressed ? widget.scale : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

/// Subtle pulsing live indicator dot (respects reduced-motion settings).
class CreaseLiveDot extends StatefulWidget {
  const CreaseLiveDot({super.key, this.size = 7, this.color});

  final double size;
  final Color? color;

  @override
  State<CreaseLiveDot> createState() => _CreaseLiveDotState();
}

class _CreaseLiveDotState extends State<CreaseLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.crease.pitchGreen;
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final opacity = 0.45 + (_ctrl.value * 0.55);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

/// Consistent squircle team monogram with deterministic, muted sports-team tones
/// so different teams are instantly distinguishable across cards and tables.
class CreaseTeamBadge extends StatelessWidget {
  const CreaseTeamBadge({
    super.key,
    required this.name,
    this.teamId,
    this.size = 36,
    this.highlighted = false,
    this.avatarUrl,
  });

  final String name;
  final String? teamId;
  final double size;
  final bool highlighted;
  final String? avatarUrl;

  static const _lightPalettes = [
    (bg: Color(0xFFE8EEF5), fg: Color(0xFF2B4C73)), // Steel Navy
    (bg: Color(0xFFE6F2EC), fg: Color(0xFF0E6B44)), // Pitch Forest
    (bg: Color(0xFFF5EAEB), fg: Color(0xFF9E333E)), // Heritage Crimson
    (bg: Color(0xFFF3EFE4), fg: Color(0xFF8C6218)), // Warm Ochre
    (bg: Color(0xFFECEAF5), fg: Color(0xFF4B3F82)), // Deep Indigo
    (bg: Color(0xFFE9EEEF), fg: Color(0xFF3A4952)), // Architectural Slate
  ];

  static const _darkPalettes = [
    (bg: Color(0xFF1A2633), fg: Color(0xFF8AB4E1)),
    (bg: Color(0xFF142D22), fg: Color(0xFF56C993)),
    (bg: Color(0xFF331B1E), fg: Color(0xFFE6838D)),
    (bg: Color(0xFF2E2616), fg: Color(0xFFE0B45C)),
    (bg: Color(0xFF231F36), fg: Color(0xFFA89CE6)),
    (bg: Color(0xFF1E2429), fg: Color(0xFF9EB0BC)),
  ];

  int get _hashIndex {
    final normalized = name.trim().toLowerCase();
    var hash = 0;
    for (var i = 0; i < normalized.length; i++) {
      hash = (hash * 31 + normalized.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash % _lightPalettes.length;
  }

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return word.length >= 2
          ? word.substring(0, 2).toUpperCase()
          : word.toUpperCase();
    }
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark
        ? _darkPalettes[_hashIndex]
        : _lightPalettes[_hashIndex];

    final radius = BorderRadius.circular(size * 0.28);
    final fallback = Text(
      _initials,
      style: creaseNumeralStyle(
        fontSize: size * 0.36,
        fontWeight: FontWeight.w700,
        color: palette.fg,
        letterSpacing: 0.2,
      ),
    );
    final explicitUrl = avatarUrl?.trim();
    final url = (explicitUrl != null && explicitUrl.isNotEmpty)
        ? explicitUrl
        : (teamId != null && teamId!.isNotEmpty)
            ? LocalEventStore.instance.directory.teamLogosById[teamId!]
            : null;
    final hasPhoto = url != null && url.isNotEmpty;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: radius,
        border: Border.all(
          color: palette.fg.withValues(alpha: isDark ? 0.24 : 0.16),
          width: 1,
        ),
      ),
      child: hasPhoto
          ? ClipRRect(
              borderRadius: BorderRadius.circular((size * 0.28) - 1),
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            )
          : fallback,
    );
  }
}

/// Circular avatar for human players — visually distinct from the squircle
/// [CreaseTeamBadge] used for clubs/teams and [CreaseTournamentBadge] for
/// competitions.
class CreasePlayerAvatar extends StatelessWidget {
  const CreasePlayerAvatar({
    super.key,
    required this.name,
    this.size = 36,
    this.highlighted = false,
    this.avatarUrl,
  });

  final String name;
  final double size;
  final bool highlighted;
  final String? avatarUrl;

  int get _hashIndex {
    final normalized = name.trim().toLowerCase();
    var hash = 0;
    for (var i = 0; i < normalized.length; i++) {
      hash = (hash * 31 + normalized.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash % CreaseTeamBadge._lightPalettes.length;
  }

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return word.length >= 2
          ? word.substring(0, 2).toUpperCase()
          : word.toUpperCase();
    }
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark
        ? CreaseTeamBadge._darkPalettes[_hashIndex]
        : CreaseTeamBadge._lightPalettes[_hashIndex];

    final fallback = Text(
      _initials,
      style: creaseNumeralStyle(
        fontSize: size * 0.36,
        fontWeight: FontWeight.w700,
        color: palette.fg,
        letterSpacing: 0.2,
      ),
    );
    final url = avatarUrl?.trim();
    final hasPhoto = url != null && url.isNotEmpty;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: palette.fg.withValues(
            alpha: highlighted ? (isDark ? 0.45 : 0.34) : (isDark ? 0.24 : 0.16),
          ),
          width: highlighted ? 1.4 : 1,
        ),
      ),
      child: hasPhoto
          ? ClipOval(
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            )
          : fallback,
    );
  }
}

/// Trophy badge for tournaments & leagues — visually distinct from team
/// monograms and circular player avatars.
class CreaseTournamentBadge extends StatelessWidget {
  const CreaseTournamentBadge({
    super.key,
    this.size = 40,
    this.hasChampion = false,
  });

  final double size;
  final bool hasChampion;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bg;
    final Color fg;
    if (hasChampion) {
      bg = isDark ? const Color(0xFF2E2616) : const Color(0xFFF6EFE0);
      fg = isDark ? const Color(0xFFE5BA5C) : const Color(0xFF9A6B16);
    } else {
      bg = c.pitchGreenSoft;
      fg = c.pitchGreen;
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: fg.withValues(alpha: isDark ? 0.28 : 0.2),
          width: 1,
        ),
      ),
      child: Icon(
        Icons.emoji_events_rounded,
        size: size * 0.5,
        color: fg,
      ),
    );
  }
}

/// Consistent segmented control used across Stats, Scorecard, and Profile.
class CreaseSegmentedControl<T> extends StatelessWidget {
  const CreaseSegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<({T value, String label, IconData? icon})> items;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.pillMutedBg,
        borderRadius: BorderRadius.circular(CreaseRadius.control),
        border: Border.all(color: c.hairlineSubtle, width: 1),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(item.value),
                child: AnimatedContainer(
                  duration: disableAnim
                      ? Duration.zero
                      : const Duration(milliseconds: 170),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    vertical: 9,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected == item.value
                        ? c.surfaceGlass
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(CreaseRadius.badge + 1),
                    boxShadow: selected == item.value
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (item.icon != null) ...[
                        Icon(
                          item.icon,
                          size: 15,
                          color: selected == item.value
                              ? c.inkPrimary
                              : c.inkSecondary,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontSize: 12.5,
                                color: selected == item.value
                                    ? c.inkPrimary
                                    : c.inkSecondary,
                                fontWeight: selected == item.value
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Standard modal sheet header with drag pill + title + close button + optional subtitle.
class CreaseSheetHeader extends StatelessWidget {
  const CreaseSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showCloseButton = true,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final bool showCloseButton;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (showCloseButton)
              IconButton(
                tooltip: 'Close',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: c.inkSecondary,
                ),
                onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }
}

/// Subtle pulse skeleton placeholder for loading states (no generic spinners).
class CreaseSkeletonBox extends StatefulWidget {
  const CreaseSkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(CreaseRadius.card),
    ),
  });

  final double height;
  final double? width;
  final BorderRadius borderRadius;

  @override
  State<CreaseSkeletonBox> createState() => _CreaseSkeletonBoxState();
}

class _CreaseSkeletonBoxState extends State<CreaseSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: c.pillMutedBg,
          borderRadius: widget.borderRadius,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final color = Color.lerp(
          c.pillMutedBg,
          c.hairlineSubtle,
          _ctrl.value,
        );
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: widget.borderRadius,
          ),
        );
      },
    );
  }
}

/// Authentic 4-color Google "G" mark painted cleanly for the Sign-In button.
class GoogleGMark extends StatelessWidget {
  const GoogleGMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Red top-left to top-right
    canvas.drawArc(rect, -2.55, 1.85, false, arc(const Color(0xFFEA4335)));
    // Yellow left
    canvas.drawArc(rect, 2.45, 1.30, false, arc(const Color(0xFFFBBC05)));
    // Green bottom
    canvas.drawArc(rect, 0.72, 1.75, false, arc(const Color(0xFF34A853)));
    // Blue right
    canvas.drawArc(rect, -0.05, 0.82, false, arc(const Color(0xFF4285F4)));

    // Horizontal blue bar
    canvas.drawLine(
      Offset(size.width * 0.52, size.height * 0.5),
      Offset(size.width * 0.94, size.height * 0.5),
      Paint()
        ..color = const Color(0xFF4285F4)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Option descriptor for [showCreaseActionSheet] and [CreaseMenuButton].
class CreaseMenuItem<T> {
  const CreaseMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.subtitle,
    this.isDestructive = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? subtitle;
  final bool isDestructive;
}

/// Unified, thumb-friendly Crease bottom action sheet replacing stock Material
/// popup menus across the app.
Future<T?> showCreaseActionSheet<T>(
  BuildContext context, {
  String? title,
  required List<CreaseMenuItem<T>> items,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.crease;
      return Container(
        decoration: BoxDecoration(
          color: c.surfaceSheet,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(CreaseRadius.sheet),
          ),
          border: Border(top: BorderSide(color: c.hairline)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null && title.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  title,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ],
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: c.surfaceKey,
                  borderRadius: BorderRadius.circular(CreaseRadius.card),
                  border: Border.all(color: c.hairlineSubtle),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: c.hairlineSubtle),
                      _CreaseActionRow<T>(item: items[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CreaseActionRow<T> extends StatelessWidget {
  const _CreaseActionRow({required this.item});

  final CreaseMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final fg = item.isDestructive ? c.wicketRed : c.inkPrimary;
    final iconBg = item.isDestructive ? c.wicketRedSoft : c.pillMutedBg;
    final iconColor = item.isDestructive ? c.wicketRed : c.inkPrimary;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).pop(item.value);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: fg,
                        ),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: item.isDestructive
                  ? c.wicketRed.withValues(alpha: 0.7)
                  : c.inkSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Drop-in replacement for [PopupMenuButton] that opens [showCreaseActionSheet].
class CreaseMenuButton<T> extends StatelessWidget {
  const CreaseMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.sheetTitle,
    this.tooltip = 'More options',
    this.icon = Icons.more_vert_rounded,
    this.iconSize = 20,
    this.compact = false,
  });

  final List<CreaseMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final String? sheetTitle;
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return IconButton(
      tooltip: tooltip,
      padding: compact ? EdgeInsets.zero : null,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(icon, size: iconSize, color: c.inkSecondary),
      onPressed: () async {
        HapticFeedback.selectionClick();
        final picked = await showCreaseActionSheet<T>(
          context,
          title: sheetTitle,
          items: items,
        );
        if (picked != null) onSelected(picked);
      },
    );
  }
}

/// Unified option picker bottom sheet replacing raw Material dropdowns.
Future<T?> showCreaseOptionPicker<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<({T value, String label, String? subtitle})> options,
  required T selectedValue,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.crease;
      final maxHeight = MediaQuery.sizeOf(ctx).height * 0.65;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: c.surfaceSheet,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CreaseRadius.sheet),
            ),
            border: Border(top: BorderSide(color: c.hairline)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CreaseSheetHeader(title: title, subtitle: subtitle),
                const SizedBox(height: 12),
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surfaceKey,
                      borderRadius: BorderRadius.circular(CreaseRadius.card),
                      border: Border.all(color: c.hairlineSubtle),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: c.hairlineSubtle),
                      itemBuilder: (_, index) {
                        final opt = options[index];
                        final isSelected = opt.value == selectedValue;
                        return ListTile(
                          dense: true,
                          title: Text(
                            opt.label,
                            style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? c.pitchGreen
                                      : c.inkPrimary,
                                ),
                          ),
                          subtitle: opt.subtitle != null
                              ? Text(opt.subtitle!)
                              : null,
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  size: 20,
                                  color: c.pitchGreen,
                                )
                              : null,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.of(ctx).pop(opt.value);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
