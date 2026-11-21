import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/local_event_store.dart';
import 'data/sample_match.dart';
import 'features/home/home_screen.dart';
import 'features/scoring/scoring_screen.dart';
import 'theme/crease_theme.dart';

/// Optional Supabase credentials passed at build time via --dart-define.
/// When omitted, Crease runs 100% offline-first on SQLite with zero friction.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

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

  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
    );
  }

  // Seed synthetic demo match on first launch so the live scoring experience
  // is immediately testable.
  final store = LocalEventStore.instance;
  final existing = await store.getMatch(SampleMatchSeed.demoMatchId);
  if (existing == null) {
    await store.saveMatch(SampleMatchSeed.config());
    await store.appendBallEventsBatch(SampleMatchSeed.events());
  } else if (existing.teamAPlayers.isEmpty) {
    final seed = SampleMatchSeed.config();
    await store.saveMatch(
      existing.copyWith(
        teamAPlayers: seed.teamAPlayers,
        teamBPlayers: seed.teamBPlayers,
      ),
    );
  }

  runApp(const CreaseApp());
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
