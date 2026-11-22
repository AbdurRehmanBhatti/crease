import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/local_event_store.dart';
import 'data/sample_match.dart';
import 'features/home/home_screen.dart';
import 'features/scoring/scoring_screen.dart';
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

  runApp(const CreaseApp());
}

Future<void> _ensureAnonymousSessionAndSync() async {
  try {
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession == null) {
      await auth.signInAnonymously();
    }
    final synced = await LocalEventStore.instance.syncAllPendingToSupabase();
    debugPrint('[Crease Sync] Auth ready (${auth.currentUser?.id}), synced $synced events.');
  } catch (e) {
    debugPrint('[Crease Sync] Startup auth/sync skipped: $e');
  }
}

class CreaseApp extends StatelessWidget {
  const CreaseApp({super.key, this.initialMatchId});

  /// Optional match ID to open directly (handy for tests & verification).
  final String? initialMatchId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crease',
      debugShowCheckedModeBanner: false,
      theme: CreaseTheme.light(),
      darkTheme: CreaseTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: initialMatchId != null
          ? ScoringScreen(matchId: initialMatchId!)
          : const HomeScreen(),
    );
  }
}
