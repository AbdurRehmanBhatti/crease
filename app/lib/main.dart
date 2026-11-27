import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_links.dart';
import 'config/in_app_update_service.dart';
import 'data/local_event_store.dart';
import 'domain/user_profile.dart';
import 'features/home/home_screen.dart';
import 'features/scorecard/scorecard_screen.dart';
import 'features/scoring/scoring_screen.dart';
import 'features/teams/team_invite_sheets.dart';
import 'features/tournaments/tournament_detail_screen.dart';
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
  await _initCrashlytics();

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
    unawaited(_syncIfSignedIn());
  }

  final store = LocalEventStore.instance;
  await store.deleteDemoMatches();

  // Load persisted theme preference before first frame
  final savedProfile = await store.getUserProfile();
  CreaseThemeController.instance.value = savedProfile.themeMode;

  runApp(const CreaseApp());
}

Future<void> _initCrashlytics() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await Firebase.initializeApp();
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(crashlytics.recordError(error, stack, fatal: true));
      return true;
    };
  } catch (e) {
    if (kDebugMode) debugPrint('[Crease Crashlytics] Init skipped: $e');
  }
}

Future<void> _syncIfSignedIn() async {
  try {
    final uid = LocalEventStore.instance.signedInUserId;
    if (uid == null) return;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        Firebase.apps.isNotEmpty) {
      unawaited(FirebaseCrashlytics.instance.setUserIdentifier(uid));
    }
    final synced = await LocalEventStore.instance.syncAllPendingToSupabase();
    final pulled = await LocalEventStore.instance.pullLatestForMyTeams();
    if (kDebugMode) {
      debugPrint(
        '[Crease Sync] Auth ready ($uid), synced $synced events, pulled $pulled team matches.',
      );
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[Crease Sync] Startup sync skipped: $e');
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
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  String? _lastOpenedMatchId;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _initInAppUpdates();
  }

  void _initInAppUpdates() {
    InAppUpdateService.instance.init(
      onUpdateDownloaded: _showUpdateReadyBanner,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(InAppUpdateService.instance.checkForFlexibleUpdate());
    });
  }

  void _showUpdateReadyBanner() {
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(days: 1),
          behavior: SnackBarBehavior.floating,
          content: const Text('Update downloaded. Restart to install.'),
          action: SnackBarAction(
            label: 'Restart',
            onPressed: () {
              unawaited(InAppUpdateService.instance.completeUpdate());
            },
          ),
        ),
      );
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

    final tournamentId = CreaseLinks.parseTournamentId(uri);
    if (tournamentId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => TournamentDetailScreen(tournamentId: tournamentId),
          ),
        );
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
          scaffoldMessengerKey: _scaffoldMessengerKey,
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
