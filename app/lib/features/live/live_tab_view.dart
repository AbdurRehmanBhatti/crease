import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local_event_store.dart';
import '../../domain/live_feed.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';
import '../scorecard/scorecard_screen.dart';
import '../tournaments/tournament_detail_screen.dart';

enum _LiveFilter {
  all('All'),
  matches('Matches'),
  tournaments('Tournaments'),
  recent('Recent');

  const _LiveFilter(this.label);
  final String label;
}

/// Public Live discovery tab: live tournaments strip, live match cards,
/// and completed-today/recent fallback during quiet hours.
/// Operates strictly in memory so spectators never pollute local SQLite.
class LiveTabView extends StatefulWidget {
  const LiveTabView({
    super.key,
    required this.headerSliver,
    required this.onLiveCountChanged,
    required this.onStartMatch,
  });

  final Widget headerSliver;
  final ValueChanged<int> onLiveCountChanged;
  final VoidCallback onStartMatch;

  @override
  State<LiveTabView> createState() => _LiveTabViewState();
}

class _LiveTabViewState extends State<LiveTabView> with WidgetsBindingObserver {
  static const _refreshInterval = Duration(seconds: 15);

  LiveFeedSnapshot? _snapshot;
  bool _loading = true;
  bool _offline = false;
  bool _refreshing = false;
  _LiveFilter _filter = _LiveFilter.all;
  Timer? _pollTimer;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetch(initial: true);
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _fetch();
      _startPolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_refreshInterval, (_) {
      if (_lifecycleState == AppLifecycleState.resumed && mounted) {
        _fetch();
      }
    });
  }

  Future<void> _fetch({bool initial = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final snap = await LocalEventStore.instance.fetchLiveFeed();
      if (!mounted) return;
      if (snap == null) {
        setState(() {
          _offline = true;
          if (initial) _loading = false;
        });
        return;
      }
      setState(() {
        _snapshot = snap;
        _offline = false;
        _loading = false;
      });
      widget.onLiveCountChanged(snap.liveMatches.length);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _openMatch(String matchId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScorecardScreen(matchId: matchId)),
    );
    if (mounted) _fetch();
  }

  Future<void> _openTournament(String tournamentId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TournamentDetailScreen(
          tournamentId: tournamentId,
          readOnlyPublic: true,
        ),
      ),
    );
    if (mounted) _fetch();
  }

  String _relativeAge(DateTime eventTime, DateTime referenceNow) {
    final diff = referenceNow.difference(eventTime);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final snap = _snapshot;
    final liveMatches = snap?.liveMatches ?? const <LiveFeedMatch>[];
    final recentMatches = snap?.recentMatches ?? const <LiveFeedMatch>[];
    final tournaments = snap?.tournaments ?? const <LiveFeedTournament>[];
    final serverNow = snap?.serverNow ?? DateTime.now();

    return RefreshIndicator(
      color: c.pitchGreen,
      backgroundColor: c.surfaceGlass,
      onRefresh: _fetch,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          widget.headerSliver,

          // Filter rail (single crisp horizontal row, edge-to-edge scroll)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final f in _LiveFilter.values) ...[
                      ChoiceChip(
                        label: Text(
                          f == _LiveFilter.matches && liveMatches.isNotEmpty
                              ? '${f.label} (${liveMatches.length})'
                              : f.label,
                        ),
                        selected: _filter == f,
                        selectedColor: c.pitchGreen,
                        backgroundColor: c.surfaceGlass,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          color: _filter == f ? c.onPitchGreen : c.inkPrimary,
                          fontWeight:
                              _filter == f ? FontWeight.w700 : FontWeight.w500,
                        ),
                        side: BorderSide(
                          color: _filter == f ? c.pitchGreen : c.hairline,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(CreaseRadius.control),
                        ),
                        onSelected: (_) {
                          if (_filter == f) return;
                          HapticFeedback.selectionClick();
                          setState(() => _filter = f);
                        },
                      ),
                      if (f != _LiveFilter.values.last)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Offline stale strip when a refresh fails with cached snapshot
          if (_offline && snap != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _OfflineBanner(
                  ageText: _relativeAge(snap.fetchedAt, DateTime.now()),
                  onRetry: _fetch,
                ),
              ),
            ),

          if (_loading)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              sliver: SliverList.separated(
                itemCount: 3,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, _) => const CreaseSkeletonBox(height: 132),
              ),
            )
          else if (_offline && snap == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: GlassSurface(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 32,
                          color: c.inkSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Couldn’t reach Crease Live',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Check your internet connection and pull down to try again.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            setState(() => _loading = true);
                            _fetch(initial: true);
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            ..._buildFeedSlivers(
              context,
              c,
              liveMatches: liveMatches,
              recentMatches: recentMatches,
              tournaments: tournaments,
              serverNow: serverNow,
            ),
        ],
      ),
    );
  }

  List<Widget> _buildFeedSlivers(
    BuildContext context,
    CreaseThemeExtension c, {
    required List<LiveFeedMatch> liveMatches,
    required List<LiveFeedMatch> recentMatches,
    required List<LiveFeedTournament> tournaments,
    required DateTime serverNow,
  }) {
    // Dedicated Tournaments filter
    if (_filter == _LiveFilter.tournaments) {
      if (tournaments.isEmpty) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _LiveEmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'No public tournaments yet',
              body:
                  'Open any tournament you manage and tap Go live to list its standings and fixtures here.',
            ),
          ),
        ];
      }
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 36),
          sliver: SliverList.separated(
            itemCount: tournaments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _LiveTournamentListCard(
              tournament: tournaments[i],
              onTap: () => _openTournament(tournaments[i].id),
            ),
          ),
        ),
      ];
    }

    // Dedicated Recent filter
    if (_filter == _LiveFilter.recent) {
      if (recentMatches.isEmpty) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _LiveEmptyState(
              icon: Icons.history_rounded,
              title: 'No recent public results',
              body:
                  'Completed matches broadcast on Crease Live will appear here.',
            ),
          ),
        ];
      }
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 36),
          sliver: SliverList.separated(
            itemCount: recentMatches.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _LiveFeedMatchCard(
              match: recentMatches[i],
              serverNow: serverNow,
              onTap: () => _openMatch(recentMatches[i].id),
            ),
          ),
        ),
      ];
    }

    // All or Matches filter
    final showTournamentsStrip =
        _filter == _LiveFilter.all && tournaments.isNotEmpty;
    final hasAnyContent =
        liveMatches.isNotEmpty || recentMatches.isNotEmpty || showTournamentsStrip;

    if (!hasAnyContent) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _LiveEmptyState(
            icon: Icons.sensors_rounded,
            title: 'No public matches live yet',
            body:
                'Start any match or tournament and turn on Show on Live tab to broadcast it here.',
            actionLabel: 'Start a match',
            onAction: widget.onStartMatch,
          ),
        ),
      ];
    }

    final slivers = <Widget>[];

    // 1. Live Tournaments horizontal strip (All filter only)
    if (showTournamentsStrip) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
            child: Row(
              children: [
                Text(
                  'Public tournaments',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (tournaments.length > 2)
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        setState(() => _filter = _LiveFilter.tournaments),
                    child: const Text('See all'),
                  ),
              ],
            ),
          ),
        ),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: SizedBox(
            height: 108,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              scrollDirection: Axis.horizontal,
              itemCount: tournaments.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _LiveTournamentStripCard(
                tournament: tournaments[i],
                onTap: () => _openTournament(tournaments[i].id),
              ),
            ),
          ),
        ),
      );
    }

    // 2. Live Matches section (or quiet-hours calm header)
    if (liveMatches.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                const CreaseLiveDot(size: 7),
                const SizedBox(width: 7),
                Text(
                  'Live now',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '${liveMatches.length} active',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            recentMatches.isNotEmpty ? 18 : 36,
          ),
          sliver: SliverList.separated(
            itemCount: liveMatches.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _LiveFeedMatchCard(
              match: liveMatches[i],
              serverNow: serverNow,
              onTap: () => _openMatch(liveMatches[i].id),
            ),
          ),
        ),
      );
    } else if (recentMatches.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: c.surfaceKey,
                borderRadius: BorderRadius.circular(CreaseRadius.control),
                border: Border.all(color: c.hairlineSubtle),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sensors_off_rounded,
                    size: 16,
                    color: c.inkSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No matches live right now · Showing recent public results',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: c.inkSecondary,
                            fontSize: 12.5,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 3. Completed Today / Recent Public Results
    if (recentMatches.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
            child: Text(
              'Recent results',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
          sliver: SliverList.separated(
            itemCount: recentMatches.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _LiveFeedMatchCard(
              match: recentMatches[i],
              serverNow: serverNow,
              onTap: () => _openMatch(recentMatches[i].id),
            ),
          ),
        ),
      );
    }

    return slivers;
  }
}

class _LiveFeedMatchCard extends StatelessWidget {
  const _LiveFeedMatchCard({
    required this.match,
    required this.serverNow,
    required this.onTap,
  });

  final LiveFeedMatch match;
  final DateTime serverNow;
  final VoidCallback onTap;

  String? _staleLabel() {
    if (!match.isLive && !match.isInningsBreak) return null;
    final mins = serverNow.difference(match.lastEventAt).inMinutes;
    if (mins < 2) return null;
    if (mins < 60) return '${mins}m ago';
    return '${(mins / 60).floor()}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final isLive = match.isLive;
    final isBreak = match.isInningsBreak;
    final isCompleted = match.isCompleted;
    final inn1Team = match.inn1TeamName;
    final inn2Team = match.inn2TeamName;
    final inn1Active = isLive && match.battingSide == match.inn1BattingSide;
    final inn2Active = isLive && match.battingSide == match.resolvedInn2Side;

    final footerText = match.statusLine;
    final footerColor = isCompleted
        ? c.pitchGreen
        : (isLive && footerText != null && footerText.contains('need '))
            ? c.inkPrimary
            : c.inkSecondary;

    final stale = _staleLabel();
    final rightFooter = stale ?? match.venue;

    return CreasePressable(
      onTap: onTap,
      child: GlassSurface(
        borderColor: c.hairline,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top broadcast strip
            Row(
              children: [
                if (isLive) ...[
                  const CreaseLiveDot(size: 7),
                  const SizedBox(width: 6),
                  Text(
                    'Live',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: c.pitchGreen,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ] else
                  Text(
                    isBreak
                        ? 'Innings break'
                        : (match.status == 'abandoned' ? 'Abandoned' : 'Final'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.pillMutedBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    match.formatLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontSize: 10.5,
                          color: c.inkPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (match.tournamentName != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      match.tournamentName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: c.inkSecondary,
                            fontSize: 11.5,
                          ),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (isLive && match.lastBallLabel != null) ...[
                  const SizedBox(width: 8),
                  _LastBallPill(
                    label: match.lastBallLabel!,
                    kind: match.lastBallKind,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // Team 1 scoreline
            _FeedTeamRow(
              teamName: inn1Team,
              teamId: match.inn1TeamId,
              logoUrl: match.inn1LogoUrl,
              score: match.inn1ScoreText,
              overs: '${match.inn1Overs} ov',
              isHighlighted: inn1Active,
              dimmed: isCompleted &&
                  footerText != null &&
                  !footerText.toLowerCase().startsWith(inn1Team.toLowerCase()),
            ),
            const SizedBox(height: 8),

            // Team 2 scoreline
            _FeedTeamRow(
              teamName: inn2Team,
              teamId: match.inn2TeamId,
              logoUrl: match.inn2LogoUrl,
              score: match.inn2Started ? match.inn2ScoreText : null,
              overs: match.inn2Started ? '${match.inn2Overs} ov' : 'Yet to bat',
              isHighlighted: inn2Active,
              dimmed: !match.inn2Started ||
                  (isCompleted &&
                      footerText != null &&
                      !footerText
                          .toLowerCase()
                          .startsWith(inn2Team.toLowerCase())),
            ),

            if (footerText != null || rightFooter != null) ...[
              const SizedBox(height: 11),
              Divider(height: 1, color: c.hairlineSubtle),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      footerText ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: footerColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                    ),
                  ),
                  if (rightFooter != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      rightFooter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: c.inkSecondary,
                            fontSize: 11.5,
                          ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedTeamRow extends StatelessWidget {
  const _FeedTeamRow({
    required this.teamName,
    this.teamId,
    this.logoUrl,
    required this.score,
    required this.overs,
    required this.isHighlighted,
    required this.dimmed,
  });

  final String teamName;
  final String? teamId;
  final String? logoUrl;
  final String? score;
  final String overs;
  final bool isHighlighted;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final nameColor = dimmed ? c.inkSecondary : c.inkPrimary;
    return Row(
      children: [
        CreaseTeamBadge(
          name: teamName,
          teamId: teamId,
          avatarUrl: logoUrl,
          size: 28,
          highlighted: isHighlighted,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            teamName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: nameColor,
                  fontWeight:
                      isHighlighted ? FontWeight.w700 : FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(width: 10),
        if (score != null) ...[
          Text(
            overs,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: c.inkSecondary,
                  fontSize: 12,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            score!,
            style: creaseNumeralStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: nameColor,
            ),
          ),
        ] else
          Text(
            overs,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: c.inkSecondary,
                  fontSize: 12.5,
                ),
          ),
      ],
    );
  }
}

class _LastBallPill extends StatelessWidget {
  const _LastBallPill({required this.label, required this.kind});

  final String label;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final Color bg;
    final Color fg;
    switch (kind) {
      case 'wicket':
        bg = c.wicketRedSoft;
        fg = c.wicketRed;
      case 'boundary':
        bg = c.pitchGreenSoft;
        fg = c.pitchGreen;
      default:
        bg = c.pillMutedBg;
        fg = c.inkPrimary;
    }
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CreaseRadius.badge),
      ),
      child: Text(
        label,
        style: creaseNumeralStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _LiveTournamentStripCard extends StatelessWidget {
  const _LiveTournamentStripCard({
    required this.tournament,
    required this.onTap,
  });

  final LiveFeedTournament tournament;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final meta = [
      if (tournament.location != null) tournament.location!,
      '${tournament.teamCount} teams',
      tournament.structure.shortLabel,
    ].join(' · ');

    return SizedBox(
      width: 248,
      child: CreasePressable(
        onTap: onTap,
        child: GlassSurface(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (tournament.hasLiveMatches) ...[
                    const CreaseLiveDot(size: 6),
                    const SizedBox(width: 6),
                    Text(
                      '${tournament.liveMatchCount} live',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: c.pitchGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                    ),
                  ] else
                    Text(
                      'Public',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: c.inkSecondary,
                            fontSize: 11.5,
                          ),
                    ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.pillMutedBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tournament.formatLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontSize: 10.5,
                            color: c.inkPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              Text(
                tournament.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: c.inkSecondary,
                      fontSize: 12,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveTournamentListCard extends StatelessWidget {
  const _LiveTournamentListCard({
    required this.tournament,
    required this.onTap,
  });

  final LiveFeedTournament tournament;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    final line1 = [
      tournament.structure.shortLabel,
      '${tournament.teamCount} teams',
      tournament.formatLabel,
    ].join(' · ');
    final line2 = [
      if (tournament.location != null) tournament.location!,
      if (tournament.dateRangeLabel != null) tournament.dateRangeLabel!,
      if (tournament.completedMatchCount > 0)
        '${tournament.completedMatchCount} played',
    ].join(' · ');

    return CreasePressable(
      onTap: onTap,
      child: GlassSurface(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CreaseTournamentBadge(
              size: 40,
              hasChampion: false,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tournament.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (tournament.hasLiveMatches) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.pitchGreenSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CreaseLiveDot(size: 5),
                              const SizedBox(width: 5),
                              Text(
                                '${tournament.liveMatchCount} live',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: c.pitchGreen,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    line1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: c.inkSecondary,
                        ),
                  ),
                  if (line2.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      line2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: c.inkSecondary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: c.inkSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.ageText, required this.onRetry});

  final String ageText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.pillMutedBg,
        borderRadius: BorderRadius.circular(CreaseRadius.control),
        border: Border.all(color: c.hairlineSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 15, color: c.inkSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline · Showing scores from $ageText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: c.inkSecondary,
                    fontSize: 12,
                  ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: c.pitchGreen,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 32),
            ),
            onPressed: onRetry,
            child: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveEmptyState extends StatelessWidget {
  const _LiveEmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: GlassSurface(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.pitchGreenSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: c.pitchGreen),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
