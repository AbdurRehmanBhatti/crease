import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_links.dart';
import '../../data/local_event_store.dart';
import '../../domain/team_profile.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';
import '../auth/auth_sheet.dart';

/// Displays a sheet with a 6-digit Team Code and invite link so teammates
/// can join the team and claim their player spot.
Future<void> showInviteTeammatesSheet(
  BuildContext context,
  TeamProfile team,
) async {
  final ok = await requireSignedInAccount(
    context,
    title: 'Sign in to invite teammates',
    subtitle: 'Team invite codes link teammates to ${team.name} across devices.',
  );
  if (!ok || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _InviteTeammatesSheet(team: team),
  );
}

class _InviteTeammatesSheet extends StatefulWidget {
  const _InviteTeammatesSheet({required this.team});

  final TeamProfile team;

  @override
  State<_InviteTeammatesSheet> createState() => _InviteTeammatesSheetState();
}

class _InviteTeammatesSheetState extends State<_InviteTeammatesSheet> {
  String? _code;
  String? _error;
  bool _loading = true;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _loadCode();
  }

  Future<void> _loadCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code =
          await LocalEventStore.instance.createTeamInviteCode(widget.team.id);
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Connect to the internet to generate a team invite code.';
        _loading = false;
      });
    }
  }

  Future<void> _resetCode() async {
    setState(() {
      _loading = true;
      _error = null;
      _copied = false;
    });
    try {
      final code =
          await LocalEventStore.instance.resetTeamInviteCode(widget.team.id);
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reset code right now. Check connection.';
        _loading = false;
      });
    }
  }

  String _formatCode(String raw) =>
      raw.length == 6 ? '${raw.substring(0, 3)} ${raw.substring(3)}' : raw;

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
          CreaseSheetHeader(
            title: 'Invite to ${widget.team.name}',
            subtitle:
                'Share this link or code with teammates so they can claim their squad name and link career stats.',
          ),
          const SizedBox(height: 18),
          if (_loading)
            const CreaseSkeletonBox(height: 98)
          else if (_error != null)
            Column(
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
                OutlinedButton(onPressed: _loadCode, child: const Text('Retry')),
              ],
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
                    'Team code',
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
                      final formatted = _formatCode(_code!);
                      final link = CreaseLinks.teamInviteUrl(_code!);
                      Share.share(
                        'Join ${widget.team.name} on Crease to link your player stats.\n'
                        '$link\n'
                        'Or open Crease -> Teams -> Join and enter code: $formatted',
                      );
                    },
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share invite'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: c.inkSecondary,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _resetCode,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reset code (invalidates old link)'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 2-step sheet: enter 6-digit Team Code -> pick your name from the squad.
Future<bool> showJoinTeamSheet(
  BuildContext context, {
  String? initialCode,
}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _JoinTeamSheet(initialCode: initialCode),
  );
  return res == true;
}

class _JoinTeamSheet extends StatefulWidget {
  const _JoinTeamSheet({this.initialCode});

  final String? initialCode;

  @override
  State<_JoinTeamSheet> createState() => _JoinTeamSheetState();
}

class _JoinTeamSheetState extends State<_JoinTeamSheet> {
  final _codeCtrl = TextEditingController();
  final _newNameCtrl = TextEditingController();

  TeamInvitePreview? _preview;
  String? _selectedPlayer;
  bool _addingNew = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final init = widget.initialCode?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    if (init.length == 6) {
      _codeCtrl.text = init;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lookupCode(init);
      });
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _newNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupCode([String? overrideCode]) async {
    final digits =
        (overrideCode ?? _codeCtrl.text).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 6) {
      setState(() => _error = 'Enter the 6-digit team code.');
      return;
    }
    final signedIn = await requireSignedInAccount(
      context,
      title: 'Sign in to join a team',
      subtitle: 'Sign in to look up the team code and claim your player spot.',
    );
    if (!signedIn || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await LocalEventStore.instance.previewTeamByCode(digits);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _selectedPlayer = preview.myClaimedPlayerId;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _error = msg.contains('Invalid team code')
            ? 'Team code not found. Double-check with your captain.'
            : (msg.contains('Authentication') || e is StateError)
                ? 'Please sign in to look up this team code.'
                : 'Check your internet connection and try again.';
        _busy = false;
      });
    }
  }

  Future<void> _claim() async {
    final preview = _preview;
    if (preview == null) return;
    final selectedId = _addingNew ? null : _selectedPlayer;
    final newName = _addingNew ? _newNameCtrl.text.trim() : '';
    final chosenLabel = _addingNew
        ? newName
        : (preview.players
                .where((p) => p.id == selectedId)
                .map((p) => p.displayName)
                .firstOrNull ??
            '');
    if (chosenLabel.isEmpty) {
      setState(
        () => _error = 'Pick your name from the squad or enter a new name.',
      );
      return;
    }
    final ok = await requireSignedInAccount(
      context,
      title: 'Sign in to claim your player spot',
      subtitle:
          'Linking $chosenLabel to your account syncs your career stats across devices.',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = _codeCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
      await LocalEventStore.instance.claimTeamPlayer(
        code,
        playerId: selectedId,
        displayName: _addingNew ? newName : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().contains('already claimed')
            ? 'That player spot is already claimed by another account.'
            : 'Could not join right now. Check connection and retry.';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final preview = _preview;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CreaseRadius.sheet),
        ),
        fillColor: c.surfaceSheet,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (preview == null) ...[
                const CreaseSheetHeader(
                  title: 'Join a team',
                  subtitle:
                      'Enter the 6-digit invite code from your captain to claim your player spot.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeCtrl,
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
                  onSubmitted: (_) => _lookupCode(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : () => _lookupCode(),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Find team'),
                ),
              ] else ...[
                CreaseSheetHeader(
                  title: 'Who are you in ${preview.teamName}?',
                  subtitle:
                      'Pick your name from the squad to link your profile and pull ${preview.teamName}\'s matches.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in preview.players)
                      Builder(
                        builder: (context) {
                          final isMine = preview.myClaimedPlayerId == p.id;
                          final claimedByOther = !isMine && p.isLinked;
                          final selected = !_addingNew && _selectedPlayer == p.id;
                          return ChoiceChip(
                            label: Text(
                              claimedByOther
                                  ? '${p.displayName} (claimed)'
                                  : p.displayName,
                            ),
                            selected: selected,
                            selectedColor: c.pitchGreen,
                            labelStyle: TextStyle(
                              color: claimedByOther
                                  ? c.inkSecondary
                                  : selected
                                      ? Colors.white
                                      : c.inkPrimary,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            side: BorderSide(
                              color: selected ? c.pitchGreen : c.hairline,
                            ),
                            onSelected: claimedByOther
                                ? null
                                : (_) => setState(() {
                                      _addingNew = false;
                                      _selectedPlayer = p.id;
                                      _error = null;
                                    }),
                          );
                        },
                      ),
                    ChoiceChip(
                      label: const Text('+ New player'),
                      selected: _addingNew,
                      selectedColor: c.pitchGreen,
                      labelStyle: TextStyle(
                        color: _addingNew ? Colors.white : c.pitchGreen,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(color: c.pitchGreen),
                      onSelected: (_) => setState(() {
                        _addingNew = true;
                        _selectedPlayer = null;
                        _error = null;
                      }),
                    ),
                  ],
                ),
                if (_addingNew) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newNameCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      hintText: 'e.g. Bilal Ahmed',
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: c.wicketRed),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _claim,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Join & link stats'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
