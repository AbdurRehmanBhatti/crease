import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/local_event_store.dart';
import '../../domain/cricket_engine.dart';
import '../../domain/models.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/glass_surface.dart';

class ScorecardScreen extends StatefulWidget {
  const ScorecardScreen({super.key, required this.matchId});

  final String matchId;

  @override
  State<ScorecardScreen> createState() => _ScorecardScreenState();
}

class _ScorecardScreenState extends State<ScorecardScreen> {
  DerivedMatchState? _state;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = LocalEventStore.instance;
    final config = await store.getMatch(widget.matchId);
    final events = await store.getBallEvents(widget.matchId);
    if (!mounted) return;
    setState(() {
      _state = config == null ? null : CricketEngine.derive(config, events);
      _loading = false;
    });
  }

  void _shareFullScorecard(DerivedMatchState state) {
    final inn = state.activeInnings;
    final buf = StringBuffer()
      ..writeln('${state.config.title} · ${state.config.formatLabel}')
      ..writeln('${inn.battingTeam}: ${inn.scoreText} (${inn.oversText} ov)')
      ..writeln('');
    for (final b in inn.batters) {
      final star = b.isOut ? '' : '*';
      buf.writeln(
        '${b.name}$star  ${b.runs} (${b.balls})  4s:${b.fours} 6s:${b.sixes}',
      );
    }
    buf.writeln('');
    for (final bw in inn.bowlers) {
      buf.writeln('${bw.name}  ${bw.figuresText} (Econ ${bw.economy.toStringAsFixed(1)})');
    }
    buf.writeln('\nScored with Crease');
    Share.share(buf.toString());
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

    final state = _state;
    if (state == null) {
      return Scaffold(
        backgroundColor: c.ground,
        appBar: AppBar(title: const Text('Scorecard')),
        body: const Center(child: Text('Match not found.')),
      );
    }

    final inn = state.activeInnings;

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: const Text('Scorecard'),
        actions: [
          IconButton(
            tooltip: 'Share scorecard',
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _shareFullScorecard(state),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Summary header
          GlassSurface(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${state.config.title} · ${state.config.formatLabel}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inn.battingTeam,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${inn.scoreText}  (${inn.oversText} ov)',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'CRR ${inn.currentRunRate.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Extras ${inn.extrasTotal} (wd ${inn.wides}, nb ${inn.noBalls}, b ${inn.byes}, lb ${inn.legByes})',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Batting table
          _SectionTitle('Batting'),
          GlassSurface(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              children: [
                _ScorecardHeaderRow(
                  col0: 'Batter',
                  cols: const ['R', 'B', '4s', '6s', 'SR'],
                ),
                const Divider(height: 14),
                for (final b in inn.batters) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ScorecardDataRow(
                          label: b.isOut ? b.name : '${b.name} *',
                          isHighlight: !b.isOut,
                          values: [
                            '${b.runs}',
                            '${b.balls}',
                            '${b.fours}',
                            '${b.sixes}',
                            b.strikeRate.toStringAsFixed(0),
                          ],
                        ),
                        if (b.dismissalText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              b.dismissalText!,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (b != inn.batters.last) const Divider(height: 10),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Bowling table
          _SectionTitle('Bowling'),
          GlassSurface(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              children: [
                _ScorecardHeaderRow(
                  col0: 'Bowler',
                  cols: const ['O', 'M', 'R', 'W', 'Econ'],
                ),
                const Divider(height: 14),
                for (final bw in inn.bowlers) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _ScorecardDataRow(
                      label: bw.name,
                      values: [
                        bw.oversText,
                        '${bw.maidens}',
                        '${bw.runsConceded}',
                        '${bw.wickets}',
                        bw.economy.toStringAsFixed(1),
                      ],
                    ),
                  ),
                  if (bw != inn.bowlers.last) const Divider(height: 10),
                ],
              ],
            ),
          ),

          if (inn.overs.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionTitle('Runs per over'),
            GlassSurface(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 120,
                child: CustomPaint(
                  painter: _ManhattanPainter(
                    overs: inn.overs,
                    barColor: c.pitchGreen,
                    wicketColor: c.wicketRed,
                    labelColor: c.inkSecondary,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ],

          if (inn.fallOfWickets.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionTitle('Fall of wickets'),
            GlassSurface(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final fow in inn.fallOfWickets)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.pillMutedBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${fow.runsAtFall}-${fow.wicketNumber} (${fow.batterName}, ${fow.oversAtFall})',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: c.inkPrimary,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

class _ScorecardHeaderRow extends StatelessWidget {
  const _ScorecardHeaderRow({required this.col0, required this.cols});
  final String col0;
  final List<String> cols;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(col0, style: Theme.of(context).textTheme.labelMedium),
        ),
        for (final col in cols)
          Expanded(
            flex: 1,
            child: Text(
              col,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
      ],
    );
  }
}

class _ScorecardDataRow extends StatelessWidget {
  const _ScorecardDataRow({
    required this.label,
    required this.values,
    this.isHighlight = false,
  });

  final String label;
  final List<String> values;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w400,
                  color: isHighlight ? c.pitchGreen : c.inkPrimary,
                ),
          ),
        ),
        for (var i = 0; i < values.length; i++)
          Expanded(
            flex: 1,
            child: Text(
              values[i],
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13.5,
                  ),
            ),
          ),
      ],
    );
  }
}

/// Ultra-lightweight CustomPainter Manhattan chart — runs smoothly on budget Android.
class _ManhattanPainter extends CustomPainter {
  const _ManhattanPainter({
    required this.overs,
    required this.barColor,
    required this.wicketColor,
    required this.labelColor,
  });

  final List<OverSummary> overs;
  final Color barColor;
  final Color wicketColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (overs.isEmpty) return;
    final maxRuns = overs.fold<int>(
      6,
      (prev, o) => o.runsInOver > prev ? o.runsInOver : prev,
    );

    final barPaint = Paint()..color = barColor;
    final wktPaint = Paint()..color = wicketColor;
    final slotWidth = size.width / overs.length;
    final barWidth = (slotWidth * 0.56).clamp(4.0, 18.0);
    final chartHeight = size.height - 16;

    for (var i = 0; i < overs.length; i++) {
      final ov = overs[i];
      final h = (ov.runsInOver / maxRuns) * (chartHeight - 10);
      final left = i * slotWidth + (slotWidth - barWidth) / 2;
      final top = chartHeight - h;

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, h.clamp(2.0, chartHeight)),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(rect, barPaint);

      for (var w = 0; w < ov.wicketsInOver; w++) {
        canvas.drawCircle(
          Offset(left + barWidth / 2, (top - 6 - w * 8).clamp(4.0, chartHeight)),
          3.2,
          wktPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ManhattanPainter oldDelegate) =>
      oldDelegate.overs != overs;
}

