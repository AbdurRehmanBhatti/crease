import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_links.dart';
import '../../data/local_event_store.dart';
import '../../domain/models.dart';

/// Generates a crisp Daylight Glass Match Summary Poster PNG (WhatsApp-ready)
/// and shares it together with the 1-line caption + live web scorecard URL.
class MatchSummaryPoster {
  MatchSummaryPoster._();

  static Future<void> shareMatch(DerivedMatchState state) async {
    // Flush any pending balls so the live link is up to date.
    await LocalEventStore.instance.syncPendingToSupabase(state.config.id);

    final caption =
        '${state.config.teamA} vs ${state.config.teamB} — Cricket Match Live Score & Stats on #Crease\n'
        '${CreaseLinks.liveMatchUrl(state.config.id)}';

    try {
      final file = await _renderPosterPng(state);
      await Share.shareXFiles([XFile(file.path)], text: caption);
    } catch (_) {
      // Fallback to link-only share if image export fails on any device.
      await Share.share(caption);
    }
  }

  static Future<File> _renderPosterPng(DerivedMatchState state) async {
    const double width = 1080;
    final inningsToShow = state.allInnings
        .where((i) => i.legalBalls > 0 || i.isDeclared || i.inningsNumber == state.activeInningsNumber)
        .toList();
    final shown = inningsToShow.length > 2
        ? inningsToShow.sublist(inningsToShow.length - 2)
        : inningsToShow;

    final double cardHeight = 290;
    final double height = 180 + (shown.length * (cardHeight + 24)) + 150;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    // Background gradient (Daylight Glass)
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE3F0EA), Color(0xFFEEF3F3), Color(0xFFEEF3F3)],
        stops: [0.0, 0.32, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    // Header: Crease brand + Format pill
    _drawText(
      canvas,
      'Crease',
      const Offset(56, 48),
      fontSize: 42,
      weight: FontWeight.w700,
      color: const Color(0xFF0A0C0C),
      letterSpacing: -1.0,
    );
    _drawText(
      canvas,
      'MATCH SUMMARY',
      const Offset(56, 100),
      fontSize: 18,
      weight: FontWeight.w600,
      color: const Color(0xFF5B6560),
      letterSpacing: 1.4,
    );

    // Format badge top-right
    final badgeRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(width - 176, 54, 120, 44),
      const Radius.circular(12),
    );
    canvas.drawRRect(badgeRect, Paint()..color = const Color(0xFFDDF1E8));
    _drawText(
      canvas,
      state.config.formatLabel,
      const Offset(width - 116, 64),
      fontSize: 20,
      weight: FontWeight.w700,
      color: const Color(0xFF098558),
      align: TextAlign.center,
    );

    // Render each innings card
    double y = 160;
    for (final inn in shown) {
      _drawInningsCard(canvas, inn, Rect.fromLTWH(48, y, width - 96, cardHeight));
      y += cardHeight + 24;
    }

    // Bottom Result / Live Status Banner (Pitch Green)
    final bannerText = state.resultSummary ??
        state.leadTrailText ??
        (state.activeInnings.runsNeeded != null
            ? '${state.activeInnings.battingTeam} need ${state.activeInnings.runsNeeded} from ${state.activeInnings.ballsRemaining} balls'
            : '${state.activeInnings.battingTeam} ${state.activeInnings.scoreText} (${state.activeInnings.oversText} ov)');

    final bannerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(48, y + 4, width - 96, 76),
      const Radius.circular(20),
    );
    canvas.drawRRect(bannerRect, Paint()..color = const Color(0xFF098558));
    _drawText(
      canvas,
      bannerText,
      Offset(width / 2, y + 26),
      fontSize: 26,
      weight: FontWeight.w600,
      color: Colors.white,
      align: TextAlign.center,
      maxWidth: width - 140,
    );

    // Subtle footer
    _drawText(
      canvas,
      'Live ball-by-ball scorecard · abdurrehmanbhatti.github.io/crease',
      Offset(width / 2, height - 46),
      fontSize: 18,
      weight: FontWeight.w500,
      color: const Color(0xFF5B6560),
      align: TextAlign.center,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final safeId = state.config.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File('${dir.path}/crease_summary_$safeId.png');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static void _drawInningsCard(
    Canvas canvas,
    DerivedInningsState inn,
    Rect rect,
  ) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(24));

    // Soft shadow
    canvas.drawRRect(
      rrect.shift(const Offset(0, 6)),
      Paint()
        ..color = const Color(0x120A0C0C)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    // Frosted white fill + 1px hairline
    canvas.drawRRect(rrect, Paint()..color = const Color(0xF5FFFFFF));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFFD5DFDD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Top row: Team Name | Overs | Score
    _drawText(
      canvas,
      inn.battingTeam.toUpperCase(),
      Offset(rect.left + 28, rect.top + 24),
      fontSize: 26,
      weight: FontWeight.w700,
      color: const Color(0xFF098558),
      maxWidth: 460,
    );
    _drawText(
      canvas,
      'Overs ${inn.oversText}',
      Offset(rect.left + 520, rect.top + 28),
      fontSize: 21,
      weight: FontWeight.w500,
      color: const Color(0xFF5B6560),
    );
    _drawText(
      canvas,
      inn.scoreText,
      Offset(rect.right - 28, rect.top + 20),
      fontSize: 34,
      weight: FontWeight.w700,
      color: const Color(0xFF0A0C0C),
      align: TextAlign.right,
    );

    // Divider
    final divY = rect.top + 74;
    canvas.drawLine(
      Offset(rect.left + 28, divY),
      Offset(rect.right - 28, divY),
      Paint()
        ..color = const Color(0xFFE3EAE8)
        ..strokeWidth = 1.5,
    );

    // Top 3 Batters (left column) & Top 3 Bowlers (right column)
    final topBat = List<BatterLine>.from(inn.batters)
      ..sort((a, b) => b.runs.compareTo(a.runs));
    final topBowl = List<BowlerLine>.from(inn.bowlers)
      ..sort((a, b) {
        final w = b.wickets.compareTo(a.wickets);
        return w != 0 ? w : a.runsConceded.compareTo(b.runsConceded);
      });

    final midX = rect.left + rect.width / 2;
    canvas.drawLine(
      Offset(midX, divY + 14),
      Offset(midX, rect.bottom - 22),
      Paint()
        ..color = const Color(0xFFE3EAE8)
        ..strokeWidth = 1.5,
    );

    for (var i = 0; i < 3; i++) {
      final rowY = divY + 26 + (i * 58);
      if (i < topBat.length) {
        final b = topBat[i];
        _drawText(
          canvas,
          b.isOut ? b.name : '${b.name}*',
          Offset(rect.left + 28, rowY),
          fontSize: 22,
          weight: FontWeight.w500,
          color: const Color(0xFF0A0C0C),
          maxWidth: 270,
        );
        _drawText(
          canvas,
          '${b.runs} (${b.balls})',
          Offset(midX - 24, rowY),
          fontSize: 22,
          weight: FontWeight.w600,
          color: const Color(0xFF0A0C0C),
          align: TextAlign.right,
        );
      }

      if (i < topBowl.length) {
        final bw = topBowl[i];
        _drawText(
          canvas,
          bw.name,
          Offset(midX + 24, rowY),
          fontSize: 22,
          weight: FontWeight.w500,
          color: const Color(0xFF0A0C0C),
          maxWidth: 270,
        );
        _drawText(
          canvas,
          '${bw.wickets}-${bw.runsConceded} (${bw.oversText})',
          Offset(rect.right - 28, rowY),
          fontSize: 22,
          weight: FontWeight.w600,
          color: const Color(0xFF0A0C0C),
          align: TextAlign.right,
        );
      }
    }
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required double fontSize,
    required FontWeight weight,
    required Color color,
    TextAlign align = TextAlign.left,
    double? letterSpacing,
    double maxWidth = 800,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    final dx = switch (align) {
      TextAlign.right => offset.dx - tp.width,
      TextAlign.center => offset.dx - tp.width / 2,
      _ => offset.dx,
    };
    tp.paint(canvas, Offset(dx, offset.dy));
  }
}
