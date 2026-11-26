import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local_event_store.dart';
import '../../domain/guest_sync_guards.dart';
import '../../domain/models.dart';
import '../../domain/stats_engine.dart';
import '../../domain/team_profile.dart';
import '../../domain/user_profile.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';
import '../auth/auth_sheet.dart';
import 'player_career_poster.dart';

/// Daylight Glass Profile & Account screen:
/// 1. Cricketer identity + linked player career stats
/// 2. Cloud backup & optional Email account linking
/// 3. Appearance (System / Light / Dark)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile _profile = const UserProfile();
  TeamProfile? _myTeam;
  PlayerCareerStats? _myStats;
  List<String> _knownPlayers = const [];
  Map<String, List<String>> _playerTeamsByLower = const {};
  Map<String, String> _playerIdByLower = const {};
  int _matchCount = 0;
  bool _loading = true;
  bool _syncing = false;
  bool _uploadingAvatar = false;
  String? _syncNote;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _load();
    try {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn ||
            data.event == AuthChangeEvent.userUpdated) {
          await LocalEventStore.instance.syncAllPendingToSupabase();
          await LocalEventStore.instance.restoreAccountDataFromCloud();
          if (mounted) {
            await _load();
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  User? get _currentUser {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  bool get _isLinkedEmail {
    final email = _currentUser?.email;
    return email != null && email.trim().isNotEmpty;
  }

  Future<void> _load() async {
    final store = LocalEventStore.instance;
    await store.refreshDirectory();
    final profile = await store.getUserProfile();
    final teams = await store.listTeams();
    final myTeam = teams.where((t) => t.isMyTeam).firstOrNull;
    final configs = await store.listMatches();
    final derived = <DerivedMatchState>[];
    for (final cfg in configs) {
      final events = await store.getBallEvents(cfg.id);
      derived.add(store.deriveMatch(cfg, events));
    }

    final realMatches = derived.where((m) => !m.config.isDemo).toList();
    final statsPool = realMatches.isNotEmpty ? realMatches : derived;
    final allStats = store.deriveStats(
      statsPool,
      excludeDemo: realMatches.isNotEmpty,
    );

    final currentUid = _currentUser?.id;
    final myTeams = teams.where((t) => t.isMyTeam).toList();
    final canonicalByLower = <String, String>{};
    final teamsByPlayerLower = <String, List<String>>{};
    final playerIdByLower = <String, String>{};
    String? claimedPlayerId;
    for (final t in myTeams) {
      for (final p in t.squad) {
        if (p.archived) continue;
        final name = p.displayName.trim();
        if (name.isEmpty || LocalEventStore.isPlaceholderPlayerName(name)) {
          continue;
        }
        final claimedByOther = p.userId != null &&
            p.userId!.isNotEmpty &&
            p.userId != currentUid;
        if (claimedByOther) continue;
        if (currentUid != null && p.userId == currentUid) {
          claimedPlayerId ??= p.id;
        }
        final key = name.toLowerCase();
        canonicalByLower.putIfAbsent(key, () => name);
        playerIdByLower.putIfAbsent(key, () => p.id);
        final list = teamsByPlayerLower.putIfAbsent(key, () => <String>[]);
        if (!list.contains(t.name)) list.add(t.name);
      }
    }
    final knownPlayers = canonicalByLower.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    PlayerCareerStats? myStats;
    if (claimedPlayerId != null) {
      myStats = allStats.where((p) => p.playerId == claimedPlayerId).firstOrNull;
    }
    final linked = profile.linkedPlayerName;
    if (myStats == null && linked != null && linked.isNotEmpty) {
      myStats = allStats
          .where((p) => p.name.toLowerCase() == linked.toLowerCase())
          .firstOrNull;
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _myTeam = myTeam;
      _myStats = myStats;
      _knownPlayers = knownPlayers;
      _playerTeamsByLower = teamsByPlayerLower;
      _playerIdByLower = playerIdByLower;
      _matchCount = realMatches.length;
      _loading = false;
    });
  }

  Future<void> _updateThemeMode(ThemeMode mode) async {
    final updated = _profile.copyWith(themeMode: mode);
    CreaseThemeController.instance.value = mode;
    setState(() => _profile = updated);
    await LocalEventStore.instance.saveUserProfile(updated);
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _syncNote = null;
    });
    try {
      final count = await LocalEventStore.instance.syncAllPendingToSupabase();
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncNote = count > 0
            ? 'Backed up $count new ball events.'
            : 'Everything is backed up.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncNote = 'Offline. Saved locally and will back up when online.';
      });
    }
  }

  Future<void> _editProfile() async {
    final nameCtrl = TextEditingController(text: _profile.displayName);
    var selectedRole = _profile.role;
    var selectedPlayer = _profile.linkedPlayerName;
    var isSaving = false;
    String? saveError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return PopScope(
              canPop: !isSaving,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: GlassSurface(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  fillColor: c.surfaceSheet,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const CreaseSheetHeader(title: 'Edit profile'),
                        const SizedBox(height: 14),
                        TextField(
                          controller: nameCtrl,
                          enabled: !isSaving,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setModalState(() {
                            saveError = null;
                          }),
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            hintText: 'e.g. Abdur Rehman',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Playing role',
                          style: Theme.of(ctx).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final role in UserProfile.roles)
                              ChoiceChip(
                                label: Text(role),
                                selected: selectedRole == role,
                                selectedColor: c.pitchGreen,
                                checkmarkColor: c.onPitchGreen,
                                labelStyle: TextStyle(
                                  color: selectedRole == role
                                      ? c.onPitchGreen
                                      : c.inkPrimary,
                                  fontWeight: selectedRole == role
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                                side: BorderSide(
                                  color: selectedRole == role
                                      ? c.pitchGreen
                                      : c.hairline,
                                ),
                                onSelected: isSaving
                                    ? null
                                    : (_) => setModalState(() {
                                          selectedRole = role;
                                          saveError = null;
                                        }),
                              ),
                          ],
                        ),
                        if (_knownPlayers.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Link my scorecard name',
                            style: Theme.of(ctx).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 8),
                          CreasePressable(
                            onTap: isSaving
                                ? null
                                : () async {
                                    final currentKey =
                                        _knownPlayers.contains(selectedPlayer)
                                            ? (selectedPlayer ?? '')
                                            : '';
                                    final picked =
                                        await showCreaseOptionPicker<String>(
                                      ctx,
                                      title: 'Link scorecard name',
                                      subtitle:
                                          'Connect your profile to your career stats.',
                                      selectedValue: currentKey,
                                      options: [
                                        (
                                          value: '',
                                          label: 'Not linked',
                                          subtitle: null,
                                        ),
                                        for (final p in _knownPlayers)
                                          (
                                            value: p,
                                            label: p,
                                            subtitle: _playerTeamsByLower[
                                                    p.toLowerCase()]
                                                ?.join(', '),
                                          ),
                                      ],
                                    );
                                    if (picked == null) return;
                                    setModalState(() {
                                      selectedPlayer =
                                          picked.isEmpty ? null : picked;
                                      saveError = null;
                                    });
                                  },
                          child: Opacity(
                            opacity: isSaving ? 0.55 : 1,
                            child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: c.surfaceKey,
                              borderRadius:
                                  BorderRadius.circular(CreaseRadius.control),
                              border: Border.all(color: c.hairline),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _knownPlayers.contains(selectedPlayer)
                                        ? selectedPlayer!
                                        : 'Not linked',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(ctx)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: _knownPlayers
                                                  .contains(selectedPlayer)
                                              ? c.inkPrimary
                                              : c.inkSecondary,
                                        ),
                                  ),
                                ),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: c.inkSecondary,
                                ),
                              ],
                            ),
                          ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (saveError != null) ...[
                        Text(
                          saveError!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.wicketRed,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Builder(
                        builder: (_) {
                          final hasChanges =
                              nameCtrl.text.trim() !=
                                      _profile.displayName.trim() ||
                                  selectedRole != _profile.role ||
                                  selectedPlayer != _profile.linkedPlayerName;
                          return FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.pitchGreen,
                              foregroundColor: c.onPitchGreen,
                              disabledBackgroundColor:
                                  isSaving ? c.pitchGreen : c.surfaceKey,
                              disabledForegroundColor:
                                  isSaving ? c.onPitchGreen : c.inkSecondary,
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: (hasChanges && !isSaving)
                                ? () async {
                                    final linkChanged =
                                        selectedPlayer !=
                                            _profile.linkedPlayerName;
                                    final trimmedName = nameCtrl.text.trim();
                                    final updated = _profile.copyWith(
                                      displayName: trimmedName,
                                      role: selectedRole,
                                      linkedPlayerName: selectedPlayer,
                                      clearLinkedPlayer: selectedPlayer == null,
                                    );
                                    setModalState(() {
                                      isSaving = true;
                                      saveError = null;
                                    });
                                    try {
                                      if (linkChanged) {
                                        final targetId = selectedPlayer != null
                                            ? _playerIdByLower[selectedPlayer!
                                                .trim()
                                                .toLowerCase()]
                                            : null;
                                        await LocalEventStore.instance
                                            .syncSelfPlayerLink(
                                          targetId,
                                          avatarUrl: updated.avatarUrl,
                                        );
                                      }
                                      await LocalEventStore.instance
                                          .saveUserProfile(updated);
                                      await _load();
                                      if (ctx.mounted) Navigator.of(ctx).pop();
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        setModalState(() {
                                          isSaving = false;
                                          saveError = e
                                                  .toString()
                                                  .contains('already claimed')
                                              ? 'That player spot is already claimed by another account.'
                                              : 'Could not update link. Check connection and try again.';
                                        });
                                      }
                                    }
                                  }
                                : null,
                            child: isSaving
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: c.onPitchGreen,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text('Saving…'),
                                    ],
                                  )
                                : const Text('Save profile'),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAuthSheet({bool initialSignIn = false}) async {
    final done = await showCreaseAuthSheet(
      context,
      initialSignIn: initialSignIn,
    );
    if (done != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _load();
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    final ok = await requireSignedInAccount(
      context,
      title: 'Sign in to upload a profile photo',
      subtitle: 'Your photo syncs across scorecards and team rosters.',
    );
    if (!ok || !mounted) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 82,
      );
      if (picked == null) return;
      setState(() => _uploadingAvatar = true);
      final bytes = await picked.readAsBytes();
      final url = await LocalEventStore.instance.uploadProfileAvatar(bytes);
      final updated = _profile.copyWith(avatarUrl: url);
      await LocalEventStore.instance.saveUserProfile(updated);
      if (updated.linkedPlayerName != null) {
        final targetId =
            _playerIdByLower[updated.linkedPlayerName!.trim().toLowerCase()];
        if (targetId != null) {
          await LocalEventStore.instance.syncSelfPlayerLink(
            targetId,
            avatarUrl: url,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _uploadingAvatar = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not upload photo. Check your internet connection.'),
        ),
      );
    }
  }

  Future<void> _openAvatarSheet() async {
    final hasPhoto =
        _profile.avatarUrl != null && _profile.avatarUrl!.isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return GlassSurface(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          fillColor: c.surfaceSheet,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Profile photo',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.photo_library_outlined, color: c.pitchGreen),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadAvatar(ImageSource.gallery);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.photo_camera_outlined, color: c.pitchGreen),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadAvatar(ImageSource.camera);
                },
              ),
              if (hasPhoto)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded, color: c.wicketRed),
                  title: Text(
                    'Remove photo',
                    style: TextStyle(color: c.wicketRed),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final updated = _profile.copyWith(clearAvatar: true);
                    await LocalEventStore.instance.saveUserProfile(updated);
                    if (updated.linkedPlayerName != null) {
                      final targetId = _playerIdByLower[
                          updated.linkedPlayerName!.trim().toLowerCase()];
                      if (targetId != null) {
                        await LocalEventStore.instance.syncSelfPlayerLink(
                          targetId,
                          avatarUrl: null,
                        );
                      }
                    }
                    if (!mounted) return;
                    setState(() => _profile = updated);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _signOut() async {
    final email = _currentUser?.email ?? 'your account';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          'Your teams and matches are backed up under $email and will return when you sign back in. Local data on this device will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.crease.wicketRed,
              foregroundColor: context.crease.onWicketRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final auth = Supabase.instance.client.auth;
      await SafeSignOutCoordinator.execute(
        backupPending: LocalEventStore.instance.syncAllPendingBeforeSignOut,
        signOutGoogle: () => GoogleSignIn().signOut(),
        signOutCloud: () => auth.signOut(),
        clearLocalData: LocalEventStore.instance.clearLocalUserDataOnSignOut,
        ensureFreshAnonymousSession: () async {},
      );

      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signed out. Sign back in anytime to restore your data.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Couldn\'t sign out while offline. Connect to back up your matches first.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final confirmCtrl = TextEditingController();
    var isDeleting = false;
    String? errorText;

    final deleted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final ready = confirmCtrl.text.trim().toUpperCase() == 'DELETE';
            return PopScope(
              canPop: !isDeleting,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: GlassSurface(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  fillColor: c.surfaceSheet,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const CreaseSheetHeader(
                          title: 'Delete your account?',
                          subtitle:
                              'This action is permanent and cannot be undone.',
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: c.surfaceKey,
                            borderRadius:
                                BorderRadius.circular(CreaseRadius.control),
                            border: Border.all(color: c.hairlineSubtle),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in const [
                                'Permanently deletes your login, profile, and uploaded photos.',
                                'Releases your link from any claimed team player spots.',
                                'Shared match scorecards stay intact for teammates.',
                                'Clears all local data on this device.',
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '•  ',
                                        style: TextStyle(
                                          color: c.wicketRed,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          line,
                                          style: Theme.of(ctx)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: c.inkPrimary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: confirmCtrl,
                          enabled: !isDeleting,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: (_) => setModalState(() {
                            errorText = null;
                          }),
                          decoration: const InputDecoration(
                            labelText: 'Type DELETE to confirm',
                            hintText: 'DELETE',
                          ),
                        ),
                        if (errorText != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            errorText!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: c.wicketRed,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: c.wicketRed,
                            foregroundColor: c.onWicketRed,
                            disabledBackgroundColor:
                                isDeleting ? c.wicketRed : c.surfaceKey,
                            disabledForegroundColor:
                                isDeleting ? c.onWicketRed : c.inkSecondary,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: (ready && !isDeleting)
                              ? () async {
                                  setModalState(() {
                                    isDeleting = true;
                                    errorText = null;
                                  });
                                  try {
                                    await LocalEventStore.instance
                                        .deleteAccount();
                                    try {
                                      await GoogleSignIn().signOut();
                                    } catch (_) {}
                                    if (ctx.mounted) {
                                      Navigator.of(ctx).pop(true);
                                    }
                                  } catch (_) {
                                    if (ctx.mounted) {
                                      setModalState(() {
                                        isDeleting = false;
                                        errorText =
                                            'Could not delete account right now. Check your connection and try again.';
                                      });
                                    }
                                  }
                                }
                              : null,
                          child: isDeleting
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.onWicketRed,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('Deleting…'),
                                  ],
                                )
                              : const Text('Delete account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    Future<void>.delayed(const Duration(milliseconds: 500), confirmCtrl.dispose);
    if (deleted != true || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account deleted.')),
    );
  }

  Future<void> _shareMyCard(PlayerCareerStats stats) async {
    await PlayerCareerPoster.sharePlayerCard(
      playerName: _profile.effectiveName,
      stats: stats,
      role: _profile.role,
      teamName: _myTeam?.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    CreaseSkeletonBox(height: 98),
                    SizedBox(height: 16),
                    CreaseSkeletonBox(height: 164),
                    SizedBox(height: 16),
                    CreaseSkeletonBox(height: 56),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                children: [
                  // 1. Cricketer Identity Hero (tappable to edit)
                  CreasePressable(
                    onTap: _editProfile,
                    child: GlassSurface(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: _uploadingAvatar ? null : _openAvatarSheet,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    color: c.pitchGreenSoft,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: c.pitchGreen.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: _uploadingAvatar
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : (_profile.avatarUrl != null &&
                                              _profile.avatarUrl!.isNotEmpty)
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              child: Image.network(
                                                _profile.avatarUrl!,
                                                width: double.infinity,
                                                height: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) =>
                                                    _profile
                                                            .initials.isNotEmpty
                                                        ? Center(
                                                            child: Text(
                                                              _profile.initials,
                                                              style: creaseNumeralStyle(
                                                                fontSize: 22,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color:
                                                                    c.pitchGreen,
                                                              ),
                                                            ),
                                                          )
                                                        : Icon(
                                                            Icons
                                                                .person_outline_rounded,
                                                            color: c.pitchGreen,
                                                            size: 26,
                                                          ),
                                              ),
                                            )
                                          : _profile.initials.isNotEmpty
                                              ? Text(
                                                  _profile.initials,
                                                  style: creaseNumeralStyle(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.w700,
                                                    color: c.pitchGreen,
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.person_outline_rounded,
                                                  color: c.pitchGreen,
                                                  size: 26,
                                                ),
                                ),
                                Positioned(
                                  right: -3,
                                  bottom: -3,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: c.pitchGreen,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: c.surfaceGlass,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt_rounded,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _profile.effectiveName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 5),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: c.pillMutedBg,
                                        borderRadius: BorderRadius.circular(
                                          CreaseRadius.badge,
                                        ),
                                      ),
                                      child: Text(
                                        _profile.role,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(color: c.inkPrimary),
                                      ),
                                    ),
                                    if (_myTeam != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: c.pitchGreenSoft,
                                          borderRadius: BorderRadius.circular(
                                            CreaseRadius.badge,
                                          ),
                                        ),
                                        child: Text(
                                          _myTeam!.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: c.pitchGreen,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (_profile.displayName.trim().isEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Tap to set your name and playing role',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: c.inkSecondary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // 2. Career stats
                  Row(
                    children: [
                      Text(
                        'Career stats',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      if (_myStats != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _shareMyCard(_myStats!),
                          icon: const Icon(Icons.share_rounded, size: 16),
                          label: const Text('Share card'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_myStats != null)
                    Column(
                      children: [
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _StatTile(
                                  label: 'Runs',
                                  value: '${_myStats!.runs}',
                                  sub:
                                      'SR ${_myStats!.strikeRate.toStringAsFixed(1)} · HS ${_myStats!.highestScoreText}',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatTile(
                                  label: 'Wickets',
                                  value: '${_myStats!.wickets}',
                                  sub:
                                      'Econ ${_myStats!.economy.toStringAsFixed(1)}',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _StatTile(
                                  label: 'Matches',
                                  value: '${_myStats!.matchesPlayed}',
                                  sub:
                                      '${_myStats!.fours} fours · ${_myStats!.sixes} sixes',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatTile(
                                  label: 'MVP points',
                                  value: '${_myStats!.mvpPoints}',
                                  sub:
                                      '${_myStats!.fieldingDismissals} fielding',
                                  highlight: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else if (_profile.linkedPlayerName != null &&
                      _profile.linkedPlayerName!.trim().isNotEmpty)
                    GlassSurface(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No match stats yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Linked as ${_profile.linkedPlayerName} — score a match to see your runs, wickets, and MVP points here.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    )
                  else
                    GlassSurface(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Link your player name',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _knownPlayers.isEmpty
                                      ? 'Create or join a team to link your player name and see personal career stats here.'
                                      : 'Pick your name from your squad to connect runs, wickets, and MVP points.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          if (_knownPlayers.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: _editProfile,
                              child: const Text('Link'),
                            ),
                          ],
                        ],
                      ),
                    ),

                  const SizedBox(height: 22),

                  // 3. Appearance
                  Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 10),
                  CreaseSegmentedControl<ThemeMode>(
                    selected: _profile.themeMode,
                    onChanged: _updateThemeMode,
                    items: const [
                      (
                        value: ThemeMode.system,
                        label: 'System',
                        icon: Icons.brightness_auto_rounded,
                      ),
                      (
                        value: ThemeMode.light,
                        label: 'Light',
                        icon: Icons.light_mode_outlined,
                      ),
                      (
                        value: ThemeMode.dark,
                        label: 'Dark',
                        icon: Icons.dark_mode_outlined,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 4. Account & backup
                  Text(
                    'Account & backup',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  GlassSurface(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isLinkedEmail
                                  ? Icons.verified_user_outlined
                                  : Icons.cloud_done_outlined,
                              size: 20,
                              color: _isLinkedEmail
                                  ? c.pitchGreen
                                  : c.inkSecondary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _isLinkedEmail
                                    ? _profile.effectiveName
                                    : 'Local guest session',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (!_isLinkedEmail)
                              IconButton(
                                tooltip: 'Sync now',
                                visualDensity: VisualDensity.compact,
                                onPressed: _syncing ? null : _syncNow,
                                icon: _syncing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        Icons.sync_rounded,
                                        size: 20,
                                        color: c.inkSecondary,
                                      ),
                              ),
                          ],
                        ),
                        if (_isLinkedEmail) ...[
                          const SizedBox(height: 2),
                          Text(
                            _currentUser!.email!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_matchCount match${_matchCount == 1 ? '' : 'es'} and teams backed up.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ] else ...[
                          const SizedBox(height: 4),
                          Text(
                            'Sign in to restore an existing account, or create one to back up your teams and matches.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        if (_syncNote != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _syncNote!,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: c.pitchGreen),
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (_isLinkedEmail) ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _syncing ? null : _syncNow,
                                  icon: const Icon(Icons.sync_rounded, size: 18),
                                  label: const Text('Sync now'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: c.wicketRed,
                                    side: BorderSide(
                                      color: c.wicketRed.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  onPressed: _signOut,
                                  child: const Text('Sign out'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Divider(height: 1, color: c.hairlineSubtle),
                          const SizedBox(height: 4),
                          Center(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: c.wicketRed,
                              ),
                              onPressed: _deleteAccount,
                              child: const Text(
                                'Delete account',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ] else
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      _openAuthSheet(initialSignIn: true),
                                  child: const Text(
                                    'Sign in',
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () =>
                                      _openAuthSheet(initialSignIn: false),
                                  child: const Text(
                                    'Create account',
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.sub,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String sub;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: highlight ? c.pitchGreen : c.inkPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: c.inkSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
