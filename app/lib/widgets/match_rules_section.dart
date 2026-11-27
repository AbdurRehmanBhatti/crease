import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/crease_theme.dart';

/// Collapsible gully / tape-ball rules panel shared by Quick Match and
/// Create Tournament: Players per side, Last Man Stands, and Max overs/bowler.
/// Stays collapsed by default so standard 11-a-side matches add zero extra taps.
class MatchRulesSection extends StatefulWidget {
  const MatchRulesSection({
    super.key,
    required this.playersPerSide,
    required this.lastManStands,
    required this.maxOversPerBowler,
    required this.oversLimit,
    required this.isTestMatch,
    required this.onPlayersPerSideChanged,
    required this.onLastManStandsChanged,
    required this.onMaxOversPerBowlerChanged,
    this.title = 'Match rules',
  });

  final int playersPerSide;
  final bool lastManStands;
  final int? maxOversPerBowler;
  final int oversLimit;
  final bool isTestMatch;
  final ValueChanged<int> onPlayersPerSideChanged;
  final ValueChanged<bool> onLastManStandsChanged;
  final ValueChanged<int?> onMaxOversPerBowlerChanged;
  final String title;

  @override
  State<MatchRulesSection> createState() => _MatchRulesSectionState();
}

class _MatchRulesSectionState extends State<MatchRulesSection> {
  bool _expanded = false;

  bool get _isCustomized =>
      widget.playersPerSide != 11 ||
      widget.lastManStands ||
      (!widget.isTestMatch && widget.maxOversPerBowler != null);

  String get _summary {
    final parts = <String>[
      '${widget.playersPerSide} players',
      if (widget.lastManStands) 'Last man stands',
      if (!widget.isTestMatch && widget.maxOversPerBowler != null)
        'Max ${widget.maxOversPerBowler} ov/bowler',
    ];
    if (!_isCustomized) return '11 players · Standard rules';
    return parts.join(' · ');
  }

  List<int> get _bowlerCapOptions {
    const all = [1, 2, 3, 4, 5, 10];
    if (widget.oversLimit <= 0) return all;
    final filtered = [
      for (final cap in all)
        if (cap < widget.oversLimit) cap,
    ];
    if (filtered.isEmpty && widget.oversLimit >= 1) {
      return [1];
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final customized = _isCustomized;

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceKey,
        borderRadius: BorderRadius.circular(CreaseRadius.control),
        border: Border.all(
          color: customized
              ? c.pitchGreen.withValues(alpha: 0.45)
              : c.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(CreaseRadius.control),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (!customized) ...[
                              const SizedBox(width: 6),
                              Text(
                                'Optional',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: c.inkSecondary),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: customized
                                        ? c.pitchGreen
                                        : c.inkSecondary,
                                    fontWeight: customized
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: c.inkSecondary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(height: 1, color: c.hairlineSubtle),
                        const SizedBox(height: 12),
                        Text(
                          'Players per side',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final count in const [6, 7, 8, 9, 10, 11])
                              ChoiceChip(
                                label: Text('$count'),
                                selected: widget.playersPerSide == count,
                                selectedColor: c.pitchGreen,
                                showCheckmark: false,
                                labelStyle: TextStyle(
                                  color: widget.playersPerSide == count
                                      ? c.onPitchGreen
                                      : c.inkPrimary,
                                  fontWeight: widget.playersPerSide == count
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                side: BorderSide(
                                  color: widget.playersPerSide == count
                                      ? c.pitchGreen
                                      : c.hairline,
                                ),
                                onSelected: (_) {
                                  HapticFeedback.selectionClick();
                                  widget.onPlayersPerSideChanged(count);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          borderRadius:
                              BorderRadius.circular(CreaseRadius.control - 2),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            widget.onLastManStandsChanged(
                              !widget.lastManStands,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Last man stands',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        'Last remaining batter can continue batting solo',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: c.inkSecondary,
                                              fontSize: 11.5,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Switch.adaptive(
                                  value: widget.lastManStands,
                                  activeThumbColor: c.pitchGreen,
                                  activeTrackColor:
                                      c.pitchGreen.withValues(alpha: 0.35),
                                  onChanged: (v) {
                                    HapticFeedback.selectionClick();
                                    widget.onLastManStandsChanged(v);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!widget.isTestMatch) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Max overs per bowler',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              ChoiceChip(
                                label: const Text('No limit'),
                                selected: widget.maxOversPerBowler == null,
                                selectedColor: c.pitchGreen,
                                showCheckmark: false,
                                labelStyle: TextStyle(
                                  color: widget.maxOversPerBowler == null
                                      ? c.onPitchGreen
                                      : c.inkPrimary,
                                  fontWeight: widget.maxOversPerBowler == null
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                side: BorderSide(
                                  color: widget.maxOversPerBowler == null
                                      ? c.pitchGreen
                                      : c.hairline,
                                ),
                                onSelected: (_) {
                                  HapticFeedback.selectionClick();
                                  widget.onMaxOversPerBowlerChanged(null);
                                },
                              ),
                              for (final cap in _bowlerCapOptions)
                                ChoiceChip(
                                  label: Text('$cap ov'),
                                  selected: widget.maxOversPerBowler == cap,
                                  selectedColor: c.pitchGreen,
                                  showCheckmark: false,
                                  labelStyle: TextStyle(
                                    color: widget.maxOversPerBowler == cap
                                        ? c.onPitchGreen
                                        : c.inkPrimary,
                                    fontWeight: widget.maxOversPerBowler == cap
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                  side: BorderSide(
                                    color: widget.maxOversPerBowler == cap
                                        ? c.pitchGreen
                                        : c.hairline,
                                  ),
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    widget.onMaxOversPerBowlerChanged(cap);
                                  },
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
