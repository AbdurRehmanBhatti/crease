import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_links.dart';
import '../../domain/stats_engine.dart';

/// Generates an editorial sports Player Career Card PNG (WhatsApp-ready)
/// and shares it together with the Crease link.
class PlayerCareerPoster {
  PlayerCareerPoster._();

  static Future<void> sharePlayerCard({
    required String playerName,
    required PlayerCareerStats stats,
    String? role,
    String? teamName,
  }) async {
    final metaParts = <String>[
      if (role != null && role.trim().isNotEmpty) role.trim(),
      if (teamName != null && teamName.trim().isNotEmpty) teamName.trim(),
    ];
    final header = metaParts.isEmpty
        ? playerName
        : '$playerName (${metaParts.join(' · ')})';
    final caption = '$header\n'
        'Matches: ${stats.matchesPlayed} · Runs: ${stats.runs} '
        '(SR ${stats.strikeRate.toStringAsFixed(1)}) · '
        'Wickets: ${stats.wickets} (Econ ${stats.economy.toStringAsFixed(1)}) · '
        'MVP: ${stats.mvpPoints.toStringAsFixed(0)} pts\n'
        'Tracked with Crease · ${CreaseLinks.liveScorecardBaseUrl}';

    try {
      final file = await _renderPosterPng(
        playerName: playerName,
        stats: stats,
        role: role,
        teamName: teamName,
      );
      await Share.shareXFiles([XFile(file.path)], text: caption);
    } catch (_) {
      await Share.share(caption);
    }
  }

  static Future<File> _renderPosterPng({
    required String playerName,
    required PlayerCareerStats stats,
    String? role,
    String? teamName,
  }) async {
    const double width = 1080;
    const double height = 1040;
    const double headerHeight = 148;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    // Architectural cool-stone ground
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
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
      const Offset(122, 50),
      fontSize: 36,
      weight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: -0.8,
    );

    // Career Card pill top-right
    final badgeRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(width - 244, 52, 192, 44),
      const Radius.circular(10),
    );
    canvas.drawRRect(badgeRect, Paint()..color = const Color(0xFF1E2327));
    _drawText(
      canvas,
      'CAREER CARD',
      const Offset(width - 148, 63),
      fontSize: 18,
      weight: FontWeight.w700,
      color: const Color(0xFF19A96B),
      align: TextAlign.center,
      letterSpacing: 1.0,
    );

    // Player identity card
    final idCardRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(52, headerHeight + 36, width - 104, 176),
      const Radius.circular(24),
    );
    canvas.drawRRect(idCardRect, Paint()..color = Colors.white);
    canvas.drawRRect(
      idCardRect,
      Paint()
        ..color = const Color(0xFFE3E7EA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Player monogram avatar
    final initials = _initialsFor(playerName);
    final avatarRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(88, headerHeight + 70, 108, 108),
      const Radius.circular(24),
    );
    canvas.drawRRect(avatarRect, Paint()..color = const Color(0xFFE5F4EC));
    _drawText(
      canvas,
      initials,
      const Offset(142, headerHeight + 100),
      fontSize: 40,
      weight: FontWeight.w700,
      color: const Color(0xFF0B7A4B),
      align: TextAlign.center,
    );

    // Name + role/team subtitle
    _drawText(
      canvas,
      playerName,
      const Offset(224, headerHeight + 74),
      fontSize: 44,
      weight: FontWeight.w700,
      color: const Color(0xFF101315),
      letterSpacing: -0.8,
      maxWidth: 560,
    );

    final subParts = <String>[
      if (role != null && role.trim().isNotEmpty) role.trim(),
      if (teamName != null && teamName.trim().isNotEmpty) teamName.trim(),
    ];
    _drawText(
      canvas,
      subParts.isEmpty ? 'Crease Player' : subParts.join(' · '),
      const Offset(224, headerHeight + 132),
      fontSize: 24,
      weight: FontWeight.w500,
      color: const Color(0xFF5D6770),
      maxWidth: 560,
    );

    // Matches pill on right side of identity card
    final matchesPill = RRect.fromRectAndRadius(
      const Rect.fromLTWH(width - 252, headerHeight + 96, 168, 56),
      const Radius.circular(14),
    );
    canvas.drawRRect(matchesPill, Paint()..color = const Color(0xFFF4F6F7));
    _drawText(
      canvas,
      '${stats.matchesPlayed} ${stats.matchesPlayed == 1 ? 'MATCH' : 'MATCHES'}',
      const Offset(width - 168, headerHeight + 112),
      fontSize: 19,
      weight: FontWeight.w700,
      color: const Color(0xFF101315),
      align: TextAlign.center,
      letterSpacing: 0.6,
    );

    // 2x2 Stat Grid
    const double gridTop = headerHeight + 36 + 176 + 26;
    const double gap = 22;
    const double tileW = (width - 104 - gap) / 2;
    const double tileH = 250;

    _drawStatTile(
      canvas,
      rect: const Rect.fromLTWH(52, gridTop, tileW, tileH),
      label: 'RUNS',
      value: '${stats.runs}',
      sub: 'SR ${stats.strikeRate.toStringAsFixed(1)}  ·  HS ${stats.highestScoreText}',
    );
    _drawStatTile(
      canvas,
      rect: Rect.fromLTWH(52 + tileW + gap, gridTop, tileW, tileH),
      label: 'WICKETS',
      value: '${stats.wickets}',
      sub: 'Econ ${stats.economy.toStringAsFixed(1)}  ·  Best ${stats.bestBowlingText}',
    );
    _drawStatTile(
      canvas,
      rect: const Rect.fromLTWH(52, gridTop + tileH + gap, tileW, tileH),
      label: 'BOUNDARIES',
      value: '${stats.fours}×4  ${stats.sixes}×6',
      sub: 'Balls faced ${stats.ballsFaced}  ·  Overs ${stats.oversBowledText}',
      valueFontSize: 52,
    );
    _drawStatTile(
      canvas,
      rect: Rect.fromLTWH(52 + tileW + gap, gridTop + tileH + gap, tileW, tileH),
      label: 'MVP SCORE',
      value: stats.mvpPoints.toStringAsFixed(0),
      sub: 'All-round impact points',
      highlight: true,
    );

    // Footer bar
    const footerY = height - 66.0;
    _drawText(
      canvas,
      'Tracked with Crease',
      const Offset(52, footerY),
      fontSize: 22,
      weight: FontWeight.w600,
      color: const Color(0xFF101315),
    );
    _drawText(
      canvas,
      'abdurrehmanbhatti.github.io/crease',
      const Offset(width - 52, footerY + 2),
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
        playerName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final file = File('${dir.path}/crease_player_$safeName.png');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static void _drawStatTile(
    Canvas canvas, {
    required Rect rect,
    required String label,
    required String value,
    required String sub,
    double valueFontSize = 68,
    bool highlight = false,
  }) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(24));
    canvas.drawRRect(
      rrect,
      Paint()..color = highlight ? const Color(0xFF0B7A4B) : Colors.white,
    );
    if (!highlight) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = const Color(0xFFE3E7EA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    _drawText(
      canvas,
      label,
      Offset(rect.left + 32, rect.top + 30),
      fontSize: 19,
      weight: FontWeight.w700,
      color: highlight
          ? Colors.white.withValues(alpha: 0.78)
          : const Color(0xFF5D6770),
      letterSpacing: 1.1,
    );

    _drawText(
      canvas,
      value,
      Offset(rect.left + 32, rect.top + 78),
      fontSize: valueFontSize,
      weight: FontWeight.w700,
      color: highlight ? Colors.white : const Color(0xFF101315),
      letterSpacing: -1.2,
      maxWidth: rect.width - 64,
    );

    _drawText(
      canvas,
      sub,
      Offset(rect.left + 32, rect.bottom - 56),
      fontSize: 21,
      weight: FontWeight.w500,
      color: highlight
          ? Colors.white.withValues(alpha: 0.88)
          : const Color(0xFF5D6770),
      maxWidth: rect.width - 64,
    );
  }

  static String _initialsFor(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'CR';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
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
