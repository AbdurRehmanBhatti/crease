import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/local_event_store.dart';
import '../../domain/cricket_engine.dart';
import '../../domain/models.dart';
import '../../domain/tournament_engine.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(CreaseRadius.sheet),
              ),
              fillColor: c.surfaceSheet,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CreaseSheetHeader(title: 'Start tournament match'),
                  const SizedBox(height: 16),
                  Text(
                    'Batting first',
                    style: Theme.of(ctx).textTheme.labelMedium,
                  ),
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
                          labelStyle: TextStyle(
                            color: teamA == team ? Colors.white : c.inkPrimary,
                            fontWeight: teamA == team
                                ? FontWeight.w600
                                : FontWeight.w500,
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
                  Text(
                    'Bowling first',
                    style: Theme.of(ctx).textTheme.labelMedium,
                  ),
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
                          labelStyle: TextStyle(
                            color: teamB == team ? Colors.white : c.inkPrimary,
                            fontWeight: teamB == team
                                ? FontWeight.w600
                                : FontWeight.w500,
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
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              CreaseSkeletonBox(height: 220),
              SizedBox(height: 12),
              CreaseSkeletonBox(height: 96),
            ],
          ),
        ),
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
            labelColor: c.inkPrimary,
            indicatorColor: c.pitchGreen,
            indicatorWeight: 2.5,
            unselectedLabelColor: c.inkSecondary,
            dividerColor: c.hairlineSubtle,
            labelStyle: Theme.of(context).textTheme.titleSmall,
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
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CreaseRadius.control + 2),
          ),
          onPressed: _startTournamentMatch,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Start match'),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Points Table & NRR
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              children: [
                GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 11),
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
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Net Run Rate follows ICC tournament calculation after each completed match.',
                    style: Theme.of(context).textTheme.bodySmall,
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
                        'No fixtures played yet.\nStart a match to record the first result.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
                    itemCount: _matches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final m = _matches[index];
                      final inn = m.activeInnings;
                      return CreasePressable(
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ScoringScreen(matchId: m.config.id),
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
                                    const CreaseLiveDot(size: 7),
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
                                    style: creaseNumeralStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: c.inkPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              if (m.resultSummary != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  m.resultSummary!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: c.pitchGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              itemCount: t.teams.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final team = t.teams[index];
                final roster = t.teamRosters[team] ?? const [];
                return GlassSurface(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CreaseTeamBadge(name: team, size: 32),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              team,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _addPlayerToRoster(team),
                            icon: const Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 16,
                            ),
                            label: const Text('Add player'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (roster.isEmpty)
                        Text(
                          'No players added yet. Players entered during a match will appear here.',
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
          Container(
            width: 3,
            height: 20,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: isTopTwo ? c.pitchGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '$rank',
                    style: creaseNumeralStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
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
            child: Text(
              '${row.played}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: c.inkPrimary,
                  ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${row.won}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: c.inkPrimary,
                  ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${row.lost}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: c.inkSecondary,
                  ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${row.points}',
              textAlign: TextAlign.right,
              style: creaseNumeralStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.inkPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row.nrrText,
              textAlign: TextAlign.right,
              style: creaseNumeralStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: nrrColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
