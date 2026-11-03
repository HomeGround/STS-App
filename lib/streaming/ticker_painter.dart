import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'ticker_snapshot.dart';

/// Draws the score bug that is burned into the stream: a transparent PNG the size of the video,
/// with the score in the bottom-left corner. Laid out on a 1280×720 grid and scaled up,
/// so it looks the same at every resolution.
Future<Uint8List> renderTicker(TickerSnapshot match, {required int width, required int height}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(width / _gridWidth);
  _paint(canvas, match);
  final image = await recorder.endRecording().toImage(width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

const _gridWidth = 1280.0;
const _gridHeight = 720.0;
const _orange = Color(0xFFED9440);
const _panel = Color(0xE6121418);
const _cell = Color(0xFF2A2F36);

void _paint(Canvas canvas, TickerSnapshot match) {
  const margin = 40.0;
  const rowHeight = 44.0;
  const headerHeight = 28.0;
  const nameWidth = 300.0;
  const gamesWidth = 44.0;
  const pointsWidth = 60.0;
  const width = 24 + nameWidth + gamesWidth + pointsWidth;
  final top = _gridHeight - margin - headerHeight - rowHeight * 2;

  // Header: which game, and the call, or the result once the match is won.
  final header = match.winner != null
      ? 'FINAL'
      : match.servingSide == null
      ? 'GAME ${match.game}'
      : 'GAME ${match.game}   ·   ${match.call}';
  canvas.drawRRect(
    RRect.fromRectAndCorners(
      const Rect.fromLTWH(margin, 0, width, headerHeight).shift(Offset(0, top)),
      topLeft: const Radius.circular(8),
      topRight: const Radius.circular(8),
    ),
    Paint()..color = _orange,
  );
  _text(canvas, header, const Offset(margin + 12, 0).translate(0, top), headerHeight,
      size: 15, color: const Color(0xFF121418), weight: FontWeight.w800);

  for (final side in [1, 2]) {
    final y = top + headerHeight + rowHeight * (side - 1);
    final isLast = side == 2;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(margin, y, width, rowHeight),
        bottomLeft: isLast ? const Radius.circular(8) : Radius.zero,
        bottomRight: isLast ? const Radius.circular(8) : Radius.zero,
      ),
      Paint()..color = _panel,
    );
    // The serving side is marked with a ball.
    if (match.servingSide == side && match.winner == null) {
      canvas.drawCircle(Offset(margin + 12, y + rowHeight / 2), 5, Paint()..color = _orange);
    }
    _text(canvas, match.sideNames[side - 1].toUpperCase(), Offset(margin + 24, y), rowHeight,
        size: 20, weight: match.winner == side ? FontWeight.w900 : FontWeight.w700, maxWidth: nameWidth - 8);

    final gamesX = margin + 24 + nameWidth;
    canvas.drawRect(Rect.fromLTWH(gamesX, y + 4, gamesWidth - 4, rowHeight - 8), Paint()..color = _cell);
    _text(canvas, '${match.gamesWon[side - 1]}', Offset(gamesX, y), rowHeight,
        size: 20, maxWidth: gamesWidth - 4, align: TextAlign.center);

    final pointsX = gamesX + gamesWidth;
    canvas.drawRect(Rect.fromLTWH(pointsX, y + 4, pointsWidth - 8, rowHeight - 8), Paint()..color = _orange);
    _text(canvas, '${match.score[side - 1]}', Offset(pointsX, y), rowHeight,
        size: 24, color: const Color(0xFF121418), weight: FontWeight.w900, maxWidth: pointsWidth - 8, align: TextAlign.center);
  }
}

/// Draws one line of text, vertically centred in a box [boxHeight] tall starting at [topLeft].
void _text(
  Canvas canvas,
  String text,
  Offset topLeft,
  double boxHeight, {
  required double size,
  Color color = const Color(0xFFFFFFFF),
  FontWeight weight = FontWeight.w700,
  double? maxWidth,
  TextAlign align = TextAlign.left,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color, fontWeight: weight)),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
  )..layout(minWidth: maxWidth ?? 0, maxWidth: maxWidth ?? double.infinity);
  painter.paint(canvas, topLeft.translate(0, (boxHeight - painter.height) / 2));
  painter.dispose();
}
