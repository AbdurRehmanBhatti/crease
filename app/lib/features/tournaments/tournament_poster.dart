import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_links.dart';
import '../../data/local_event_store.dart';
import '../../domain/stats_engine.dart';
import '../../domain/tournament_engine.dart';

/// Generates an editorial sports Tournament Standings Poster PNG (WhatsApp-ready)
/// and shares it together with the live tournament link.
class TournamentPoster {
  TournamentPoster._();

  static Future<void> shareTournament({
    required Tournament tournament,
    required TournamentOverview overview,
    PlayerCareerStats? mvp,
  }) async {
    LocalEventStore.instance.syncTournamentToSupabase(tournament.id);

    final metaParts = <String>[
      '${tournament.structure.shortLabel} · ${tournament.formatLabel} · ${tournament.teams.length} teams',
      if (tournament.location != null && tournament.location!.isNotEmpty)
        tournament.location!,
      if (tournament.dateRangeLabel != null) tournament.dateRangeLabel!,
    ];
    final buf = StringBuffer()
      ..writeln(tournament.name)
      ..writeln(metaParts.join(' · '));
    if (overview.champion != null) {
      buf.writeln('Champion: ${overview.champion}');
    }
    buf.write(
      'Live table & fixtures: ${CreaseLinks.tournamentUrl(tournament.id)}',
    );
    final caption = buf.toString();

    try {
      final file = await _renderPosterPng(
        tournament: tournament,
        overview: overview,
        mvp: mvp,
      );
      await Share.shareXFiles([XFile(file.path)], text: caption);
    } catch (_) {
      await Share.share(caption);
    }
  }

  static Future<File> _renderPosterPng({
    required Tournament tournament,
    required TournamentOverview overview,
    PlayerCareerStats? mvp,
  }) async {
    const double width = 1080;
    const double headerHeight = 184;
    const double rowHeight = 76;
    const int maxRows = 8;

    final rows = overview.standings.take(maxRows).toList();
    final extraCount = overview.standings.length - rows.length;
    final hasChampion = overview.champion != null;
    final championBlockH = hasChampion ? 132.0 + 24.0 : 0.0;
    final tableCardH = rows.isEmpty
        ? 160.0
        : 76.0 + (rows.length * rowHeight) + (extraCount > 0 ? 54.0 : 18.0);
    final double height =
        headerHeight + 36 + championBlockH + tableCardH + 116;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    // Cool-stone ground
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFF4F6F7),
    );

    // Obsidian header band
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, headerHeight),
      Paint()..color = const Color(0xFF101315),
    );

    // Crease emblem top-left
    const emblemRect = Rect.fromLTWH(52, 46, 54, 54);
    canvas.drawRRect(
      RRect.fromRectAndRadius(emblemRect, const Radius.circular(14)),
      Paint()..color = const Color(0xFF0B7A4B),
    );
    final emblemStroke = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(63, 83), const Offset(95, 83), emblemStroke);
    for (final x in const [71.0, 79.0, 87.0]) {
      canvas.drawLine(Offset(x, 59), Offset(x, 75), emblemStroke);
    }

    _drawText(
      canvas,
      tournament.name,
      const Offset(124, 42),
      fontSize: 38,
      weight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: -0.8,
      maxWidth: 740,
    );

    final metaParts = <String>[
      tournament.structure.shortLabel,
      '${tournament.teams.length} teams',
      if (tournament.location != null && tournament.location!.isNotEmpty)
        tournament.location!,
      if (tournament.dateRangeLabel != null) tournament.dateRangeLabel!,
    ];
    _drawText(
      canvas,
      metaParts.join(' · '),
      const Offset(124, 96),
      fontSize: 22,
      weight: FontWeight.w500,
      color: const Color(0xFF9AA4AD),
      maxWidth: 740,
    );

    // Format tag top-right
    final badgeRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(width - 172, 52, 120, 44),
      const Radius.circular(10),
    );
    canvas.drawRRect(badgeRect, Paint()..color = const Color(0xFF1E2327));
    _drawText(
      canvas,
      tournament.formatLabel,
      const Offset(width - 112, 62),
      fontSize: 20,
      weight: FontWeight.w700,
      color: const Color(0xFF19A96B),
      align: TextAlign.center,
    );

    var cursorY = headerHeight + 36.0;

    // Champion banner
    if (hasChampion) {
      final champRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(52, cursorY, width - 104, 132),
        const Radius.circular(22),
      );
      canvas.drawRRect(champRect, Paint()..color = const Color(0xFF0B7A4B));
      _drawText(
        canvas,
        'TOURNAMENT CHAMPION',
        Offset(84, cursorY + 24),
        fontSize: 17,
        weight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.8),
        letterSpacing: 1.1,
      );
      _drawText(
        canvas,
        overview.champion!,
        Offset(84, cursorY + 56),
        fontSize: 40,
        weight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: -0.6,
        maxWidth: 640,
      );
      if (mvp != null) {
        _drawText(
          canvas,
          'MVP · ${mvp.name}',
          Offset(width - 84, cursorY + 68),
          fontSize: 22,
          weight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.92),
          align: TextAlign.right,
          maxWidth: 320,
        );
      }
      cursorY += 132 + 24;
    }

    // Points table card
    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(52, cursorY, width - 104, tableCardH),
      const Radius.circular(24),
    );
    canvas.drawRRect(cardRect, Paint()..color = Colors.white);
    canvas.drawRRect(
      cardRect,
      Paint()
        ..color = const Color(0xFFE3E7EA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (rows.isEmpty) {
      _drawText(
        canvas,
        'Standings & fixtures will appear once teams are added.',
        Offset(width / 2, cursorY + 68),
        fontSize: 24,
        weight: FontWeight.w500,
        color: const Color(0xFF5D6770),
        align: TextAlign.center,
        maxWidth: width - 160,
      );
    } else {
      const colTeam = 92.0;
      const colP = 610.0;
      const colW = 685.0;
      const colL = 760.0;
      const colPts = 848.0;
      const colNrr = width - 84.0;

      // Table header
      final headerY = cursorY + 26;
      const headerColor = Color(0xFF5D6770);
      _drawText(canvas, 'TEAM', Offset(colTeam, headerY), fontSize: 18, weight: FontWeight.w700, color: headerColor, letterSpacing: 0.8);
      _drawText(canvas, 'P', Offset(colP, headerY), fontSize: 18, weight: FontWeight.w700, color: headerColor, align: TextAlign.right);
      _drawText(canvas, 'W', Offset(colW, headerY), fontSize: 18, weight: FontWeight.w700, color: headerColor, align: TextAlign.right);
      _drawText(canvas, 'L', Offset(colL, headerY), fontSize: 18, weight: FontWeight.w700, color: headerColor, align: TextAlign.right);
      _drawText(canvas, 'PTS', Offset(colPts, headerY), fontSize: 18, weight: FontWeight.w700, color: headerColor, align: TextAlign.right);
      _drawText(canvas, 'NRR', Offset(colNrr, headerY), fontSize: 18, weight: FontWeight.w700, color: headerColor, align: TextAlign.right);

      final dividerPaint = Paint()
        ..color = const Color(0xFFEAECEF)
        ..strokeWidth = 1.6;
      canvas.drawLine(
        Offset(76, cursorY + 68),
        Offset(width - 76, cursorY + 68),
        dividerPaint,
      );

      final qualifiers = overview.qualifiersCount;
      for (var i = 0; i < rows.length; i++) {
        final s = rows[i];
        final rowTop = cursorY + 76 + (i * rowHeight);
        final textY = rowTop + 22;
        final isQualifier = qualifiers > 0 && i < qualifiers;

        if (i > 0) {
          canvas.drawLine(
            Offset(76, rowTop),
            Offset(width - 76, rowTop),
            dividerPaint,
          );
        }

        if (isQualifier) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(68, rowTop + 18, 6, 40),
              const Radius.circular(3),
            ),
            Paint()..color = const Color(0xFF0B7A4B),
          );
        }

        _drawText(
          canvas,
          '${i + 1}',
          Offset(colTeam, textY),
          fontSize: 22,
          weight: FontWeight.w700,
          color: isQualifier
              ? const Color(0xFF0B7A4B)
              : const Color(0xFF5D6770),
        );
        _drawText(
          canvas,
          s.teamName,
          Offset(colTeam + 40, textY - 2),
          fontSize: 25,
          weight: FontWeight.w600,
          color: const Color(0xFF101315),
          maxWidth: 420,
        );
        _drawText(canvas, '${s.played}', Offset(colP, textY), fontSize: 22, weight: FontWeight.w500, color: const Color(0xFF101315), align: TextAlign.right);
        _drawText(canvas, '${s.won}', Offset(colW, textY), fontSize: 22, weight: FontWeight.w500, color: const Color(0xFF101315), align: TextAlign.right);
        _drawText(canvas, '${s.lost}', Offset(colL, textY), fontSize: 22, weight: FontWeight.w500, color: const Color(0xFF5D6770), align: TextAlign.right);
        _drawText(canvas, '${s.points}', Offset(colPts, textY - 1), fontSize: 24, weight: FontWeight.w700, color: const Color(0xFF101315), align: TextAlign.right);
        final nrrText =
            '${s.nrr >= 0 ? '+' : ''}${s.nrr.toStringAsFixed(3)}';
        _drawText(
          canvas,
          nrrText,
          Offset(colNrr, textY),
          fontSize: 21,
          weight: FontWeight.w600,
          color: s.nrr > 0
              ? const Color(0xFF0B7A4B)
              : const Color(0xFF5D6770),
          align: TextAlign.right,
        );
      }

      if (extraCount > 0) {
        _drawText(
          canvas,
          '+ $extraCount more ${extraCount == 1 ? 'team' : 'teams'} on live table',
          Offset(width / 2, cursorY + tableCardH - 42),
          fontSize: 19,
          weight: FontWeight.w500,
          color: const Color(0xFF5D6770),
          align: TextAlign.center,
        );
      }
    }

    // Footer
    final footerY = height - 66.0;
    _drawText(
      canvas,
      'Live table & fixtures on Crease',
      Offset(52, footerY),
      fontSize: 22,
      weight: FontWeight.w600,
      color: const Color(0xFF101315),
    );
    _drawText(
      canvas,
      'abdurrehmanbhatti.github.io/crease',
      Offset(width - 52, footerY + 2),
      fontSize: 20,
      weight: FontWeight.w500,
      color: const Color(0xFF0B7A4B),
      align: TextAlign.right,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final safeName =
        tournament.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final file = File('${dir.path}/crease_tournament_$safeName.png');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required double fontSize,
    required FontWeight weight,
    required Color color,
    double? letterSpacing,
    TextAlign align = TextAlign.left,
    double maxWidth = 960,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
          height: 1.12,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    final dx = switch (align) {
      TextAlign.center => offset.dx - painter.width / 2,
      TextAlign.right => offset.dx - painter.width,
      _ => offset.dx,
    };
    painter.paint(canvas, Offset(dx, offset.dy));
  }
}
