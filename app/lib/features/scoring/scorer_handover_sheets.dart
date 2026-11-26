import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_links.dart';
import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';
import '../auth/auth_sheet.dart';

/// Displays a sheet with a 6-digit handover code so the other team's scorer
/// can take over scoring on their own phone.
Future<void> showHandOverScoringSheet(
  BuildContext context,
  DerivedMatchState state,
) async {
  final ok = await requireSignedInAccount(
    context,
    title: 'Sign in to hand over scoring',
    subtitle: 'Pass the Baton syncs live balls across devices under your account.',
  );
  if (!ok || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _HandOverSheet(state: state),
  );
}

class _HandOverSheet extends StatefulWidget {
  const _HandOverSheet({required this.state});

  final DerivedMatchState state;

  @override
  State<_HandOverSheet> createState() => _HandOverSheetState();
}

class _HandOverSheetState extends State<_HandOverSheet> {
  String? _code;
  String? _error;
  bool _loading = true;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _generateCode();
  }

  Future<void> _generateCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await LocalEventStore.instance
          .createScorerHandoverCode(widget.state.config.id);
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final msg = raw.contains('Not authorized')
          ? 'This match belongs to an earlier guest session. Start a new match under your current account to hand over scoring.'
          : 'Connect to the internet to generate a scorer handover code.';
      setState(() {
        _error = msg;
        _loading = false;
      });
    }
  }

  String _formatCode(String raw) {
    if (raw.length == 6) {
      return '${raw.substring(0, 3)} ${raw.substring(3)}';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return GlassSurface(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CreaseRadius.sheet),
      ),
      fillColor: c.surfaceSheet,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CreaseSheetHeader(
            title: 'Hand over scoring',
            subtitle:
                'Share this 6-digit code with the next scorer so scoring transfers to their device without duplicate balls.',
          ),
          const SizedBox(height: 18),
          if (_loading)
            const CreaseSkeletonBox(height: 98)
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.wicketRedSoft,
                borderRadius: BorderRadius.circular(CreaseRadius.card),
              ),
              child: Column(
                children: [
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: c.wicketRed),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _generateCode,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: c.pitchGreenSoft,
                borderRadius: BorderRadius.circular(CreaseRadius.card),
                border: Border.all(color: c.pitchGreen.withValues(alpha: 0.28)),
              ),
              child: Column(
                children: [
                  Text(
                    'Scorer code',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: c.pitchGreen,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatCode(_code!),
                    style: creaseNumeralStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: c.pitchGreen,
                      letterSpacing: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _code!));
                      setState(() => _copied = true);
                    },
                    icon: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 18,
                    ),
                    label: Text(_copied ? 'Copied' : 'Copy code'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final codeFormatted = _formatCode(_code!);
                      final text =
                          'Take over scoring for ${widget.state.config.title} on Crease.\n'
                          'Open Crease -> Matches -> Join scorer and enter code: $codeFormatted\n'
                          'Live scorecard: ${CreaseLinks.liveMatchUrl(widget.state.config.id)}';
                      Share.share(text);
                    },
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share code'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Prompts for a 6-digit scorer handover code, claims the scoring baton,
/// downloads the match into local SQLite, and returns the joined `matchId`.
Future<String?> showJoinAsScorerSheet(BuildContext context) async {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _JoinScorerSheet(),
  );
}

class _JoinScorerSheet extends StatefulWidget {
  const _JoinScorerSheet();

  @override
  State<_JoinScorerSheet> createState() => _JoinScorerSheetState();
}

class _JoinScorerSheetState extends State<_JoinScorerSheet> {
  final _ctrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final digits = _ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 6) {
      setState(() => _error = 'Enter the 6-digit scorer code.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final matchId = await LocalEventStore.instance.claimScorerBaton(digits);
      if (!mounted) return;
      Navigator.of(context).pop(matchId);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('Invalid scorer code')
          ? 'Code not found. Check the 6 digits with the current scorer.'
          : 'Could not join right now. Check your connection and try again.';
      setState(() {
        _error = msg;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CreaseRadius.sheet),
        ),
        fillColor: c.surfaceSheet,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CreaseSheetHeader(
              title: 'Join as scorer',
              subtitle:
                  'Enter the 6-digit handover code from the current scorer.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 7,
              textAlign: TextAlign.center,
              style: creaseNumeralStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: c.inkPrimary,
                letterSpacing: 6,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '000 000',
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Take over scoring'),
            ),
          ],
        ),
      ),
    );
  }
}
