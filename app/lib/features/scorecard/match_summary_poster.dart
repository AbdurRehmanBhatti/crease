import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_links.dart';
import '../../data/local_event_store.dart';
import '../../domain/models.dart';

/// Generates an editorial sports Match Summary Poster PNG (WhatsApp-ready)
/// and shares it together with the live web scorecard URL.
class MatchSummaryPoster {
  MatchSummaryPoster._();

  static String buildShareCaption(
    DerivedMatchState state, {
    required bool includeLiveLink,
  }) {
    if (includeLiveLink) {
      return '${state.config.teamA} vs ${state.config.teamB} · Live Score & Stats on Crease\n'
          '${CreaseLinks.liveMatchUrl(state.config.id)}';
    }
    final summary = state.resultSummary?.trim() ?? '';
    return summary.isNotEmpty
        ? '${state.config.teamA} vs ${state.config.teamB} · $summary · Scored with Crease'
        : '${state.config.teamA} vs ${state.config.teamB} · Scored with Crease';
  }

  static Future<void> shareMatch(DerivedMatchState state) async {
    final signedIn = LocalEventStore.instance.isSignedInAccount;
    if (signedIn) {
      try {
        await LocalEventStore.instance
            .ensureMatchSyncedToSupabase(state.config.id);
      } catch (_) {}
    }

    final caption = buildShareCaption(state, includeLiveLink: signedIn);

    try {
      final file = await _renderPosterPng(state, includeLiveLink: signedIn);
      await Share.shareXFiles([XFile(file.path)], text: caption);
    } catch (_) {
      await Share.share(caption);
    }
  }

  static Future<File> _renderPosterPng(
    DerivedMatchState state, {
    required bool includeLiveLink,
  }) async {
    const double width = 1080;
    final inningsToShow = state.allInnings
        .where(
          (i) =>
              i.legalBalls > 0 ||
              i.isDeclared ||
              i.inningsNumber == state.activeInningsNumber,
        )
        .toList();
    final shown = inningsToShow.length > 2
        ? inningsToShow.sublist(inningsToShow.length - 2)
        : inningsToShow;

    const double headerHeight = 168;
    const double cardHeight = 286;
    final double height =
        headerHeight + 36 + (shown.length * (cardHeight + 22)) + 156;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    // Crisp architectural cool-stone ground
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFF4F6F7),
    );

    // Obsidian editorial top header band
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, headerHeight),
      Paint()..color = const Color(0xFF101315),
    );

    // Minimalist Crease emblem top-left
    const emblemRect = Rect.fromLTWH(52, 46, 54, 54);
    canvas.drawRRect(
      RRect.fromRectAndRadius(emblemRect, const Radius.circular(14)),
      Paint()..color = const Color(0xFF0B7A4B),
    );
    final emblemStroke = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(63, 83),
      const Offset(95, 83),
      emblemStroke,
    );
    for (final x in const [71.0, 79.0, 87.0]) {
      canvas.drawLine(Offset(x, 59), Offset(x, 75), emblemStroke);
    }

    _drawText(
      canvas,
      'Crease',
      const Offset(122, 42),
      fontSize: 36,
      weight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: -0.8,
    );
    _drawText(
      canvas,
      '${state.config.teamA} v ${state.config.teamB}',
      const Offset(122, 86),
      fontSize: 22,
      weight: FontWeight.w500,
      color: const Color(0xFF9AA4AD),
      maxWidth: 680,
    );

    // Format tag top-right
    final badgeRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(width - 172, 54, 120, 44),
      const Radius.circular(10),
    );
    canvas.drawRRect(badgeRect, Paint()..color = const Color(0xFF1E2327));
    _drawText(
      canvas,
      state.config.formatLabel,
      const Offset(width - 112, 64),
      fontSize: 20,
      weight: FontWeight.w700,
      color: const Color(0xFF19A96B),
      align: TextAlign.center,
    );

    // Innings cards
    double y = headerHeight + 34;
    for (final inn in shown) {
      _drawInningsCard(
        canvas,
        inn,
        Rect.fromLTWH(48, y, width - 96, cardHeight),
      );
      y += cardHeight + 22;
    }

    // Bottom Result / Status Banner
    final bannerText = state.resultSummary ??
        state.leadTrailText ??
        (state.activeInnings.runsNeeded != null
            ? '${state.activeInnings.battingTeam} need ${state.activeInnings.runsNeeded} from ${state.activeInnings.ballsRemaining} balls'
            : '${state.activeInnings.battingTeam} ${state.activeInnings.scoreText} (${state.activeInnings.oversText} ov)');

    final bannerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(48, y + 4, width - 96, 74),
      const Radius.circular(16),
    );
    canvas.drawRRect(bannerRect, Paint()..color = const Color(0xFF0B7A4B));
    _drawText(
      canvas,
      bannerText,
      Offset(width / 2, y + 25),
      fontSize: 25,
      weight: FontWeight.w700,
      color: Colors.white,
      align: TextAlign.center,
      maxWidth: width - 140,
    );

    // Clean footer
    _drawText(
      canvas,
      includeLiveLink
          ? 'Live scorecard · abdurrehmanbhatti.github.io/crease'
          : 'Scored with Crease',
      Offset(width / 2, height - 46),
      fontSize: 18,
      weight: FontWeight.w500,
      color: const Color(0xFF5D666E),
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
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));

    // Crisp white surface + hairline border
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFFE2E6E9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Top row: Team Name | Overs | Score
    _drawText(
      canvas,
      inn.battingTeam,
      Offset(rect.left + 28, rect.top + 22),
      fontSize: 27,
      weight: FontWeight.w700,
      color: const Color(0xFF101315),
      maxWidth: 460,
    );
    _drawText(
      canvas,
      '${inn.oversText} ov',
      Offset(rect.right - 196, rect.top + 28),
      fontSize: 21,
      weight: FontWeight.w500,
      color: const Color(0xFF5D666E),
      align: TextAlign.right,
    );
    _drawText(
      canvas,
      inn.scoreText,
      Offset(rect.right - 28, rect.top + 18),
      fontSize: 36,
      weight: FontWeight.w700,
      color: const Color(0xFF0B7A4B),
      align: TextAlign.right,
    );

    // Divider
    final divY = rect.top + 74;
    canvas.drawLine(
      Offset(rect.left + 28, divY),
      Offset(rect.right - 28, divY),
      Paint()
        ..color = const Color(0xFFECEFF2)
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
        ..color = const Color(0xFFECEFF2)
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
          weight: FontWeight.w600,
          color: const Color(0xFF101315),
          maxWidth: 270,
        );
        _drawText(
          canvas,
          '${b.runs} (${b.balls})',
          Offset(midX - 24, rowY),
          fontSize: 22,
          weight: FontWeight.w700,
          color: const Color(0xFF101315),
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
          weight: FontWeight.w600,
          color: const Color(0xFF101315),
          maxWidth: 270,
        );
        _drawText(
          canvas,
          '${bw.wickets}-${bw.runsConceded} (${bw.oversText})',
          Offset(rect.right - 28, rowY),
          fontSize: 22,
          weight: FontWeight.w700,
          color: const Color(0xFF101315),
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
