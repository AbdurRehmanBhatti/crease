import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_links.dart';
import 'data/local_event_store.dart';
import 'data/sample_match.dart';
import 'domain/user_profile.dart';
import 'features/home/home_screen.dart';
import 'features/scorecard/scorecard_screen.dart';
import 'features/scoring/scoring_screen.dart';
import 'features/teams/team_invite_sheets.dart';
import 'theme/crease_theme.dart';

/// Supabase project configuration (overridable via --dart-define).
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://ajwqkcblakfojsbyqjqt.supabase.co',
);
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_6MtwRj2UjMJJSeRWqDDnOw_oUW_NR0z',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge Android system UI
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  if (_supabaseUrl.isNotEmpty && _supabasePublishableKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
    );
    unawaited(_ensureAnonymousSessionAndSync());
  }

  // Seed synthetic demo match on first launch so the live scoring experience
  // is immediately testable.
  final store = LocalEventStore.instance;
  final existing = await store.getMatch(SampleMatchSeed.demoMatchId);
  if (existing == null) {
    await store.saveMatch(SampleMatchSeed.config());
    await store.appendBallEventsBatch(SampleMatchSeed.events());
  } else {
    if (existing.teamAPlayers.isEmpty) {
      final seed = SampleMatchSeed.config();
      await store.saveMatch(
        existing.copyWith(
          teamAPlayers: seed.teamAPlayers,
          teamBPlayers: seed.teamBPlayers,
        ),
      );
    }
    final existingEvents =
        await store.getBallEvents(SampleMatchSeed.demoMatchId);
    final hasInn1 = existingEvents.any((e) => e.inningsNumber == 1);
    if (!hasInn1) {
      await store.appendBallEventsBatch(SampleMatchSeed.innings1Events());
    }
  }

  // Load persisted theme preference before first frame
  final savedProfile = await store.getUserProfile();
  CreaseThemeController.instance.value = savedProfile.themeMode;

  runApp(const CreaseApp());
}

Future<void> _ensureAnonymousSessionAndSync() async {
  try {
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession == null) {
      await auth.signInAnonymously();
    }
    final synced = await LocalEventStore.instance.syncAllPendingToSupabase();
    final pulled = await LocalEventStore.instance.pullLatestForMyTeams();
    debugPrint('[Crease Sync] Auth ready (${auth.currentUser?.id}), synced $synced events, pulled $pulled team matches.');
  } catch (e) {
    debugPrint('[Crease Sync] Startup auth/sync skipped: $e');
  }
}

class CreaseApp extends StatefulWidget {
  const CreaseApp({super.key, this.initialMatchId});

  /// Optional match ID to open directly (handy for tests & verification).
  final String? initialMatchId;

  @override
  State<CreaseApp> createState() => _CreaseAppState();
}

class _CreaseAppState extends State<CreaseApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  String? _lastOpenedMatchId;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleIncomingUri(initialUri);
      }
      _linkSub = _appLinks.uriLinkStream.listen(
        _handleIncomingUri,
        onError: (_) {},
      );
    } catch (_) {
      // Ignore on platforms/tests where app_links plugin isn't registered.
    }
  }

  void _handleIncomingUri(Uri uri) {
    final teamCode = CreaseLinks.parseTeamInviteCode(uri);
    if (teamCode != null && teamCode.length == 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _navigatorKey.currentContext;
        if (ctx != null) {
          showJoinTeamSheet(ctx, initialCode: teamCode);
        }
      });
      return;
    }

    final matchId = CreaseLinks.parseMatchId(uri);
    if (matchId == null || matchId == _lastOpenedMatchId) return;
    _lastOpenedMatchId = matchId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ScorecardScreen(matchId: matchId),
        ),
      ).whenComplete(() {
        if (_lastOpenedMatchId == matchId) {
          _lastOpenedMatchId = null;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: CreaseThemeController.instance,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Crease',
          debugShowCheckedModeBanner: false,
          theme: CreaseTheme.light(),
          darkTheme: CreaseTheme.dark(),
          themeMode: themeMode,
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
                statusBarBrightness:
                    isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: widget.initialMatchId != null
              ? ScoringScreen(matchId: widget.initialMatchId!)
              : const HomeScreen(),
        );
      },
    );
  }
}
