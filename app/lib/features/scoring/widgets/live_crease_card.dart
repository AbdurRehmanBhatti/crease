import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../../theme/crease_theme.dart';
import '../../../widgets/glass_surface.dart';

/// Broadcast-grade live crease table showing active batters (R, B, 4s, 6s, SR)
/// and current bowler figures (O, M, R, W, Eco) with crisp tabular alignment.
class LiveCreaseCard extends StatelessWidget {
  const LiveCreaseCard({
    super.key,
    required this.strikerEmpty,
    required this.nonStrikerEmpty,
    required this.striker,
    required this.nonStriker,
    required this.bowler,
    required this.needsNewBowler,
    required this.onSwapStrike,
    required this.onSelectNextBatter,
    required this.onSelectNextBowler,
  });

  final bool strikerEmpty;
  final bool nonStrikerEmpty;
  final BatterLine striker;
  final BatterLine nonStriker;
  final BowlerLine bowler;
  final bool needsNewBowler;
  final VoidCallback onSwapStrike;
  final VoidCallback onSelectNextBatter;
  final VoidCallback onSelectNextBowler;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final headerStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 11,
          color: c.inkSecondary,
          fontWeight: FontWeight.w600,
        );

    return GlassSurface(
      borderRadius: BorderRadius.circular(CreaseRadius.card),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Batters header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text('Batter', style: headerStyle)),
                _ColHeader('R', width: 32, style: headerStyle),
                _ColHeader('B', width: 30, style: headerStyle),
                _ColHeader('4s', width: 26, style: headerStyle),
                _ColHeader('6s', width: 26, style: headerStyle),
                _ColHeader('SR', width: 44, style: headerStyle),
              ],
            ),
          ),
          const SizedBox(height: 5),
          if (strikerEmpty)
            _ActionCreaseRow(
              icon: Icons.person_add_alt_1_rounded,
              label: 'Select next batter',
              onTap: onSelectNextBatter,
            )
          else
            _BatterTableRow(
              batter: striker,
              isStriker: true,
              onTap: onSwapStrike,
            ),
          const SizedBox(height: 2),
          if (nonStrikerEmpty)
            _ActionCreaseRow(
              icon: Icons.person_add_alt_1_rounded,
              label: 'Select next batter',
              onTap: onSelectNextBatter,
            )
          else
            _BatterTableRow(
              batter: nonStriker,
              isStriker: false,
              onTap: onSwapStrike,
            ),
          Divider(height: 16, color: c.hairlineSubtle),
          // Bowler header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text('Bowler', style: headerStyle)),
                _ColHeader('O', width: 32, style: headerStyle),
                _ColHeader('M', width: 26, style: headerStyle),
                _ColHeader('R', width: 30, style: headerStyle),
                _ColHeader('W', width: 26, style: headerStyle),
                _ColHeader('Eco', width: 44, style: headerStyle),
              ],
            ),
          ),
          const SizedBox(height: 5),
          if (needsNewBowler)
            _ActionCreaseRow(
              icon: Icons.sports_baseball_outlined,
              label: 'Select next bowler',
              onTap: onSelectNextBowler,
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onSelectNextBowler,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        bowler.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: c.inkPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    _NumCell(bowler.oversText, width: 32),
                    _NumCell('${bowler.maidens}', width: 26, muted: true),
                    _NumCell('${bowler.runsConceded}', width: 30),
                    _NumCell('${bowler.wickets}', width: 26, bold: true),
                    _NumCell(
                      bowler.economy.toStringAsFixed(1),
                      width: 44,
                      muted: true,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BatterTableRow extends StatelessWidget {
  const _BatterTableRow({
    required this.batter,
    required this.isStriker,
    required this.onTap,
  });

  final BatterLine batter;
  final bool isStriker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Material(
      color: isStriker ? c.surfaceKey : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 7, 6, 7),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 16,
                margin: const EdgeInsets.only(right: 7),
                decoration: BoxDecoration(
                  color: isStriker ? c.pitchGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        batter.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: c.inkPrimary,
                              fontWeight:
                                  isStriker ? FontWeight.w700 : FontWeight.w500,
                            ),
                      ),
                    ),
                    if (isStriker) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.sports_cricket_rounded,
                        size: 13,
                        color: c.pitchGreen,
                      ),
                    ],
                  ],
                ),
              ),
              _NumCell('${batter.runs}', width: 32, bold: true),
              _NumCell('${batter.balls}', width: 30, muted: true),
              _NumCell('${batter.fours}', width: 26, muted: true),
              _NumCell('${batter.sixes}', width: 26, muted: true),
              _NumCell(
                batter.strikeRate.toStringAsFixed(1),
                width: 44,
                muted: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCreaseRow extends StatelessWidget {
  const _ActionCreaseRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Material(
      color: c.pitchGreenSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.pitchGreen.withValues(alpha: 0.3), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: c.pitchGreen),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: c.pitchGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.text, {required this.width, required this.style});
  final String text;
  final double width;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.right, style: style),
    );
  }
}

class _NumCell extends StatelessWidget {
  const _NumCell(
    this.text, {
    required this.width,
    this.bold = false,
    this.muted = false,
  });

  final String text;
  final double width;
  final bool bold;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: creaseNumeralStyle(
          fontSize: 14,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: muted ? c.inkSecondary : c.inkPrimary,
        ),
      ),
    );
  }
}
