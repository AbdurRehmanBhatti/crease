import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local_event_store.dart';
import '../../domain/cricket_engine.dart';
import '../../domain/models.dart';
import '../../domain/stats_engine.dart';
import '../../domain/team_profile.dart';
import '../../domain/user_profile.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/glass_surface.dart';

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
  int _matchCount = 0;
  bool _loading = true;
  bool _syncing = false;
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
    final profile = await store.getUserProfile();
    final teams = await store.listTeams();
    final myTeam = teams.where((t) => t.isMyTeam).firstOrNull;
    final configs = await store.listMatches();
    final derived = <DerivedMatchState>[];
    for (final cfg in configs) {
      final events = await store.getBallEvents(cfg.id);
      derived.add(CricketEngine.derive(cfg, events));
    }

    final realMatches = derived.where((m) => !m.config.isDemo).toList();
    final statsPool = realMatches.isNotEmpty ? realMatches : derived;
    final allStats = StatsEngine.derive(
      statsPool,
      teamName: myTeam?.name,
      excludeDemo: realMatches.isNotEmpty,
    );

    final knownSet = <String>{
      ...?myTeam?.players,
      ...allStats.map((p) => p.name),
    };
    final knownPlayers = knownSet.toList()..sort();

    PlayerCareerStats? myStats;
    final linked = profile.linkedPlayerName;
    if (linked != null && linked.isNotEmpty) {
      myStats = allStats
          .where((p) => p.name.toLowerCase() == linked.toLowerCase())
          .firstOrNull;
      if (myStats == null && myTeam != null) {
        // Fallback across all matches if they played for another team name
        final broad = StatsEngine.derive(statsPool, excludeDemo: realMatches.isNotEmpty);
        myStats = broad
            .where((p) => p.name.toLowerCase() == linked.toLowerCase())
            .firstOrNull;
      }
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _myTeam = myTeam;
      _myStats = myStats;
      _knownPlayers = knownPlayers;
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
        _syncNote = 'Offline — saved locally and will back up when online.';
      });
    }
  }

  Future<void> _editProfile() async {
    final nameCtrl = TextEditingController(text: _profile.displayName);
    var selectedRole = _profile.role;
    var selectedPlayer = _profile.linkedPlayerName;

    final saved = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
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
                        'Edit profile',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: nameCtrl,
                        textCapitalization: TextCapitalization.words,
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
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(
                                color: selectedRole == role
                                    ? Colors.white
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
                              onSelected: (_) =>
                                  setModalState(() => selectedRole = role),
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
                        DropdownButtonFormField<String?>(
                          initialValue: _knownPlayers.contains(selectedPlayer)
                              ? selectedPlayer
                              : null,
                          decoration: const InputDecoration(
                            hintText: 'Select your name from squad',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Not linked'),
                            ),
                            for (final p in _knownPlayers)
                              DropdownMenuItem<String?>(
                                value: p,
                                child: Text(p),
                              ),
                          ],
                          onChanged: (v) =>
                              setModalState(() => selectedPlayer = v),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.pitchGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () {
                          final trimmedName = nameCtrl.text.trim();
                          Navigator.of(ctx).pop(
                            _profile.copyWith(
                              displayName: trimmedName,
                              role: selectedRole,
                              linkedPlayerName: selectedPlayer,
                              clearLinkedPlayer: selectedPlayer == null,
                            ),
                          );
                        },
                        child: const Text('Save profile'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == null) return;
    await LocalEventStore.instance.saveUserProfile(saved);
    await _load();
  }

  Future<void> _openAuthSheet({bool initialSignIn = false}) async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    var isSignInMode = initialSignIn;
    var obscurePassword = true;
    var submitting = false;
    String? errorText;

    final done = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> continueWithGoogle() async {
              setModalState(() {
                submitting = true;
                errorText = null;
              });
              try {
                final auth = Supabase.instance.client.auth;
                const redirect = 'crease://login-callback';
                final isGuest =
                    auth.currentUser != null && (auth.currentUser!.isAnonymous);
                if (!isSignInMode && isGuest) {
                  await auth.linkIdentity(
                    OAuthProvider.google,
                    redirectTo: redirect,
                  );
                } else {
                  await auth.signInWithOAuth(
                    OAuthProvider.google,
                    redirectTo: redirect,
                  );
                }
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop('Continuing with Google…');
              } on AuthException catch (e) {
                setModalState(() {
                  errorText = e.message;
                  submitting = false;
                });
              } catch (_) {
                setModalState(() {
                  errorText =
                      'Google sign-in is not enabled yet or you are offline.';
                  submitting = false;
                });
              }
            }

            Future<void> submitEmail() async {
              final email = emailCtrl.text.trim();
              final pass = passCtrl.text;
              if (!email.contains('@') || pass.length < 6) {
                setModalState(() {
                  errorText = 'Enter a valid email and at least 6 characters.';
                });
                return;
              }
              setModalState(() {
                submitting = true;
                errorText = null;
              });
              try {
                final auth = Supabase.instance.client.auth;
                if (isSignInMode) {
                  await auth.signInWithPassword(email: email, password: pass);
                  final restored = await LocalEventStore.instance
                      .restoreAccountDataFromCloud();
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop(
                    restored > 0
                        ? 'Signed in & restored $restored matches.'
                        : 'Signed in as $email',
                  );
                } else {
                  const redirect = 'crease://login-callback';
                  if (auth.currentSession == null) {
                    await auth.signUp(
                      email: email,
                      password: pass,
                      emailRedirectTo: redirect,
                    );
                  } else {
                    await auth.updateUser(
                      UserAttributes(email: email, password: pass),
                      emailRedirectTo: redirect,
                    );
                  }
                  await LocalEventStore.instance.syncAllPendingToSupabase();
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop(
                    'Account created & backed up! Check $email if confirmation is enabled.',
                  );
                }
              } on AuthException catch (e) {
                setModalState(() {
                  errorText = e.message;
                  submitting = false;
                });
              } catch (_) {
                setModalState(() {
                  errorText = 'Check your internet connection and try again.';
                  submitting = false;
                });
              }
            }

            return Padding(
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
                        isSignInMode ? 'Sign in to Crease' : 'Create account',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isSignInMode
                            ? 'Restore your backed-up teams, matches, and career stats.'
                            : 'Save your teams, matches, and stats to an account so you never lose them.',
                        style: Theme.of(ctx).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: c.hairline),
                          backgroundColor: c.surfaceGlass,
                          foregroundColor: c.inkPrimary,
                        ),
                        onPressed: submitting ? null : continueWithGoogle,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'G',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text('Continue with Google'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: Divider(color: c.hairlineSubtle)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or use email',
                              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                    color: c.inkSecondary,
                                  ),
                            ),
                          ),
                          Expanded(child: Divider(color: c.hairlineSubtle)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'you@example.com',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText:
                              isSignInMode ? 'Password' : 'Create a password',
                          hintText: 'At least 6 characters',
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                            ),
                            onPressed: () => setModalState(
                              () => obscurePassword = !obscurePassword,
                            ),
                          ),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          errorText!,
                          style: Theme.of(ctx)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: c.wicketRed),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.pitchGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: submitting ? null : submitEmail,
                        child: submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isSignInMode ? 'Sign in' : 'Create account',
                              ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: submitting
                            ? null
                            : () => setModalState(() {
                                  isSignInMode = !isSignInMode;
                                  errorText = null;
                                }),
                        child: Text(
                          isSignInMode
                              ? 'New to Crease? Create account'
                              : 'Already have an account? Sign in',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (done != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _load();
    }
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
              foregroundColor: Colors.white,
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
      await LocalEventStore.instance.syncAllPendingToSupabase();
      await LocalEventStore.instance.clearLocalUserDataOnSignOut();
      final auth = Supabase.instance.client.auth;
      await auth.signOut();
      await auth.signInAnonymously();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signed out. Sign back in anytime to restore your data.'),
        ),
      );
    } catch (_) {
      if (mounted) await _load();
    }
  }

  void _shareMyCard(PlayerCareerStats stats) {
    final teamLine = _myTeam != null ? ' · ${_myTeam!.name}' : '';
    final text = '${_profile.effectiveName} (${_profile.role}$teamLine)\n'
        'Matches: ${stats.matchesPlayed} · Runs: ${stats.runs} (SR ${stats.strikeRate.toStringAsFixed(1)}) · '
        'Wickets: ${stats.wickets} (Econ ${stats.economy.toStringAsFixed(1)}) · '
        'MVP: ${stats.mvpPoints.toStringAsFixed(0)} pts\n'
        'Tracked with Crease';
    Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Scaffold(
      backgroundColor: c.ground,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Profile'),
        actions: [
          TextButton(
            onPressed: _editProfile,
            child: Text(
              'Edit',
              style: TextStyle(
                color: c.pitchGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, -0.35),
            colors: [c.sageWashTop, c.ground],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                  children: [
                    // 1. Cricketer Identity Hero (tappable to edit)
                    GestureDetector(
                      onTap: _editProfile,
                      child: GlassSurface(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: c.pitchGreenSoft,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: c.pitchGreen.withValues(alpha: 0.25),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: _profile.initials.isNotEmpty
                                  ? Text(
                                      _profile.initials,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            color: c.pitchGreen,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    )
                                  : Icon(
                                      Icons.person_outline_rounded,
                                      color: c.pitchGreen,
                                      size: 28,
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
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: c.pillMutedBg,
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                                        Text(
                                          '★ ${_myTeam!.name}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: c.pitchGreen,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                    ],
                                  ),
                                  if (_profile.displayName.trim().isEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Tap to set your name & role',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: c.inkSecondary),
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

                    // 2. My Career Stats
                    Row(
                      children: [
                        Text(
                          'MY CAREER STATS',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    letterSpacing: 0.8,
                                  ),
                        ),
                        const Spacer(),
                        if (_myStats != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: c.pitchGreen,
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
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.85,
                        children: [
                          _StatTile(
                            label: 'Runs',
                            value: '${_myStats!.runs}',
                            sub:
                                'SR ${_myStats!.strikeRate.toStringAsFixed(1)} · HS ${_myStats!.highestScoreText}',
                          ),
                          _StatTile(
                            label: 'Wickets',
                            value: '${_myStats!.wickets}',
                            sub: 'Econ ${_myStats!.economy.toStringAsFixed(1)}',
                          ),
                          _StatTile(
                            label: 'Matches',
                            value: '${_myStats!.matchesPlayed}',
                            sub:
                                '${_myStats!.fours} fours · ${_myStats!.sixes} sixes',
                          ),
                          _StatTile(
                            label: 'MVP Points',
                            value: '${_myStats!.mvpPoints}',
                            sub: '${_myStats!.fieldingDismissals} fielding',
                            highlight: true,
                          ),
                        ],
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
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _knownPlayers.isEmpty
                                        ? 'Score your first match to see your personal career stats here.'
                                        : 'Pick your name from your squad so your runs, wickets, and MVP appear here.',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
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

                    // 3. Appearance (single-layer pill directly on ground, symmetrical icons)
                    Text(
                      'APPEARANCE',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            letterSpacing: 0.8,
                          ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        backgroundColor:
                            WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return c.pitchGreen;
                          }
                          return c.surfaceGlass;
                        }),
                        foregroundColor:
                            WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.white;
                          }
                          return c.inkPrimary;
                        }),
                        side: WidgetStateProperty.all(
                          BorderSide(color: c.hairline, width: 1),
                        ),
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_rounded, size: 17),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_rounded, size: 17),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_rounded, size: 17),
                        ),
                      ],
                      selected: {_profile.themeMode},
                      onSelectionChanged: (set) => _updateThemeMode(set.first),
                    ),

                    const SizedBox(height: 24),

                    // 4. Account & Cloud Backup
                    Text(
                      'ACCOUNT & BACKUP',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            letterSpacing: 0.8,
                          ),
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
                                      ? _currentUser!.email!
                                      : 'Guest cloud backup',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
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
                          const SizedBox(height: 4),
                          Text(
                            _isLinkedEmail
                                ? 'Your $_matchCount matches and teams are linked to this account.'
                                : 'Sign in to restore an existing account, or create one to keep your teams and stats backed up.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
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
                          if (_isLinkedEmail)
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
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        _openAuthSheet(initialSignIn: true),
                                    child: const Text('Sign in'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: c.pitchGreen,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () =>
                                        _openAuthSheet(initialSignIn: false),
                                    child: const Text('Create account'),
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
