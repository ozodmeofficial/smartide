// Renders the SmartIDE logo to PNG files used for the Windows .ico and docs.
// Run with: flutter test tool/render_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartide/ui/logo.dart';

void main() {
  test('render logo pngs', () async {
    for (final int size in [16, 20, 24, 32, 40, 48, 64, 128, 256, 512]) {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      // Leave a small transparent margin at small sizes so the tile does not
      // touch the edges of the taskbar slot.
      final double pad = size >= 48 ? size * 0.04 : 0;
      canvas.translate(pad, pad);
      const LogoPainter().paint(canvas, Size.square(size - pad * 2));
      final ui.Image img = await recorder.endRecording().toImage(size, size);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('assets/icon/smartide_$size.png').writeAsBytesSync(data!.buffer.asUint8List());
    }
  });
}
