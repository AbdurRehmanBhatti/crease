import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/cricket_engine.dart';
import '../../domain/models.dart';
import '../../domain/tournament_engine.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/glass_surface.dart';
import '../scoring/scoring_screen.dart';

class TournamentDetailScreen extends StatefulWidget {
  const TournamentDetailScreen({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  static const _uuid = Uuid();

  Tournament? _tournament;
  List<DerivedMatchState> _matches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = LocalEventStore.instance;
    final tournament = await store.getTournament(widget.tournamentId);
    final matchConfigs =
        await store.listMatchesForTournament(widget.tournamentId);
    final derived = <DerivedMatchState>[];
    for (final cfg in matchConfigs) {
      final events = await store.getBallEvents(cfg.id);
      derived.add(CricketEngine.derive(cfg, events));
    }
    if (!mounted) return;
    setState(() {
      _tournament = tournament;
      _matches = derived;
      _loading = false;
    });
  }

  Future<void> _startTournamentMatch() async {
    final t = _tournament;
    if (t == null || t.teams.length < 2) return;

    String teamA = t.teams[0];
    String teamB = t.teams[1];

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return GlassSurface(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              fillColor: c.surfaceSheet,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
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
                    'Start Tournament Match',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  Text('Batting first',
                      style: Theme.of(ctx).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final team in t.teams)
                        ChoiceChip(
                          label: Text(team),
                          selected: teamA == team,
                          selectedColor: c.pitchGreen,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: teamA == team ? Colors.white : c.inkPrimary,
                          ),
                          side: BorderSide(
                            color: teamA == team ? c.pitchGreen : c.hairline,
                          ),
                          onSelected: (_) => setModalState(() {
                            teamA = team;
                            if (teamB == team) {
                              teamB = t.teams.firstWhere((x) => x != team);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Bowling first',
                      style: Theme.of(ctx).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final team in t.teams.where((x) => x != teamA))
                        ChoiceChip(
                          label: Text(team),
                          selected: teamB == team,
                          selectedColor: c.pitchGreen,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: teamB == team ? Colors.white : c.inkPrimary,
                          ),
                          side: BorderSide(
                            color: teamB == team ? c.pitchGreen : c.hairline,
                          ),
                          onSelected: (_) => setModalState(() => teamB = team),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.pitchGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Start ${t.formatLabel} · $teamA v $teamB'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) return;
    final rosterA = List<String>.from(t.teamRosters[teamA] ?? const []);
    final rosterB = List<String>.from(t.teamRosters[teamB] ?? const []);
    final striker1 = rosterA.isNotEmpty ? rosterA[0] : 'Batter 1';
    final nonStriker1 = rosterA.length > 1 ? rosterA[1] : 'Batter 2';
    final bowler1 = rosterB.isNotEmpty ? rosterB[0] : 'Bowler 1';
    final striker2 = rosterB.isNotEmpty ? rosterB[0] : 'Opener 1';
    final nonStriker2 = rosterB.length > 1 ? rosterB[1] : 'Opener 2';
    final bowler2 = rosterA.isNotEmpty ? rosterA[0] : 'Bowler 1';

    final matchConfig = MatchConfig(
      id: _uuid.v4(),
      teamA: teamA,
      teamB: teamB,
      oversLimit: t.oversLimit,
      playersPerSide: t.playersPerSide,
      formatLabel: t.formatLabel,
      battingFirstTeam: teamA,
      openingStrikerInnings1: striker1,
      openingNonStrikerInnings1: nonStriker1,
      openingBowlerInnings1: bowler1,
      openingStrikerInnings2: striker2,
      openingNonStrikerInnings2: nonStriker2,
      openingBowlerInnings2: bowler2,
      teamAPlayers: rosterA.isEmpty ? [striker1, nonStriker1] : rosterA,
      teamBPlayers: rosterB.isEmpty ? [bowler1] : rosterB,
      tournamentId: t.id,
      createdAt: DateTime.now(),
    );

    await LocalEventStore.instance.saveMatch(matchConfig);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScoringScreen(matchId: matchConfig.id)),
    );
    _load();
  }

  Future<void> _addPlayerToRoster(String teamName) async {
    final t = _tournament;
    if (t == null) return;
    final ctrl = TextEditingController();
    final player = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add player to $teamName'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Player name'),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx, ctrl.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (player == null || player.isEmpty) return;
    final updatedRosters = {
      for (final e in t.teamRosters.entries) e.key: List<String>.from(e.value),
    };
    final list = updatedRosters.putIfAbsent(teamName, () => []);
    if (!list.any((p) => p.toLowerCase() == player.toLowerCase())) {
      list.add(player);
      final updated = t.copyWith(teamRosters: updatedRosters);
      await LocalEventStore.instance.saveTournament(updated);
      LocalEventStore.instance.syncTournamentToSupabase(updated.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;

    if (_loading) {
      return Scaffold(
        backgroundColor: c.ground,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final t = _tournament;
    if (t == null) {
      return Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(title: const Text('Tournament')),
        body: const Center(child: Text('Tournament not found.')),
      );
    }

    final standings = TournamentEngine.deriveStandings(t, _matches);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(
          title: Text(t.name),
          bottom: TabBar(
            labelColor: c.pitchGreen,
            indicatorColor: c.pitchGreen,
            unselectedLabelColor: c.inkSecondary,
            dividerColor: c.hairlineSubtle,
            tabs: const [
              Tab(text: 'Standings'),
              Tab(text: 'Matches'),
              Tab(text: 'Teams'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: c.pitchGreen,
          foregroundColor: Colors.white,
          onPressed: _startTournamentMatch,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Start Match'),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Auto-derived Points Table & NRR
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                GlassSurface(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              'Team',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          for (final h in const ['P', 'W', 'L', 'Pts', 'NRR'])
                            Expanded(
                              flex: h == 'NRR' ? 2 : 1,
                              child: Text(
                                h,
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                        ],
                      ),
                      const Divider(height: 16),
                      for (var i = 0; i < standings.length; i++) ...[
                        _StandingsRowWidget(
                          rank: i + 1,
                          row: standings[i],
                          isTopTwo: i < 2 && standings[i].played > 0,
                        ),
                        if (i != standings.length - 1)
                          const Divider(height: 14),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'Standings & ICC Net Run Rate are auto-derived from the ball-by-ball log after every completed match.',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),

            // Tab 2: Matches
            _matches.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No matches played yet.\nTap "Start Match" to begin.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _matches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final m = _matches[index];
                      final inn = m.activeInnings;
                      return GestureDetector(
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ScoringScreen(matchId: m.config.id),
                            ),
                          );
                          _load();
                        },
                        child: GlassSurface(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (m.status == MatchStatus.live) ...[
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: c.pitchGreen,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      m.config.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  Text(
                                    '${inn.scoreText} (${inn.oversText})',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                ],
                              ),
                              if (m.resultSummary != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  m.resultSummary!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: c.pitchGreen),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),

            // Tab 3: Teams & Rosters
            ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: t.teams.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final team = t.teams[index];
                final roster = t.teamRosters[team] ?? const [];
                return GlassSurface(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            team,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          TextButton.icon(
                            onPressed: () => _addPlayerToRoster(team),
                            icon: const Icon(Icons.person_add_alt_1_rounded,
                                size: 17),
                            label: const Text('Add player'),
                          ),
                        ],
                      ),
                      if (roster.isEmpty)
                        Text(
                          'No players added yet — players you add while scoring will also appear here.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final p in roster)
                              Chip(
                                label: Text(p),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StandingsRowWidget extends StatelessWidget {
  const _StandingsRowWidget({
    required this.rank,
    required this.row,
    required this.isTopTwo,
  });

  final int rank;
  final PointsTableRow row;
  final bool isTopTwo;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final nrrColor = row.nrr > 0.0005
        ? c.pitchGreen
        : row.nrr < -0.0005
            ? c.wicketRed
            : c.inkSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '$rank',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: isTopTwo ? c.pitchGreen : c.inkSecondary,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    row.teamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight:
                              isTopTwo ? FontWeight.w600 : FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text('${row.played}', textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 1,
            child: Text('${row.won}', textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 1,
            child: Text('${row.lost}', textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${row.points}',
              textAlign: TextAlign.right,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row.nrrText,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: nrrColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
