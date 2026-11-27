import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/crease_theme.dart';
import '../../../widgets/crease_ui.dart';

/// Shared, consistent "Show on Live tab" broadcast toggle used in Quick Match,
/// Create Tournament, and Scoring Match Options.
class LiveBroadcastToggleTile extends StatelessWidget {
  const LiveBroadcastToggleTile({
    super.key,
    required this.isPublic,
    required this.onChanged,
    this.isTournament = false,
  });

  final bool isPublic;
  final ValueChanged<bool> onChanged;
  final bool isTournament;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final subtitle = isPublic
        ? (isTournament
            ? 'Public · Tournament and live matches appear on Crease Live'
            : 'Public · Appears on Crease Live after the first ball')
        : 'Unlisted · Only people with your link can view';

    return Semantics(
      toggled: isPublic,
      label: 'Show on Live tab. $subtitle',
      child: InkWell(
        borderRadius: BorderRadius.circular(CreaseRadius.control),
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!isPublic);
        },
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: isPublic ? c.pitchGreenSoft.withValues(alpha: 0.55) : c.surfaceKey,
            borderRadius: BorderRadius.circular(CreaseRadius.control),
            border: Border.all(
              color: isPublic
                  ? c.pitchGreen.withValues(alpha: 0.45)
                  : c.hairline,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isPublic ? c.pitchGreenSoft : c.pillMutedBg,
                  borderRadius: BorderRadius.circular(CreaseRadius.badge + 2),
                ),
                child: isPublic
                    ? const CreaseLiveDot(size: 8)
                    : Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: c.inkSecondary,
                      ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Show on Live tab',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: c.inkPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isPublic ? c.pitchGreen : c.inkSecondary,
                            fontSize: 11.5,
                            fontWeight:
                                isPublic ? FontWeight.w500 : FontWeight.w400,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Switch.adaptive(
                value: isPublic,
                activeThumbColor: c.pitchGreen,
                activeTrackColor: c.pitchGreen.withValues(alpha: 0.35),
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
