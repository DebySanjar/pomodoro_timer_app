import 'dart:math';
import 'package:flutter/material.dart';

Path createMixedParticles(Size size) {
  final random = Random();
  final type = random.nextInt(4); // 0 = heart, 1 = star, 2 = flame, 3 = emoji
  final w = size.width;
  final h = size.height;

  switch (type) {

  // ❤️ HEART
    case 0:
      final path = Path();
      path.moveTo(w / 2, h / 1.2);
      path.cubicTo(w * 1.1, h * 0.6, w * 0.8, h * 0.05, w / 2, h * 0.3);
      path.cubicTo(w * 0.2, h * 0.05, w * -0.1, h * 0.6, w / 2, h / 1.2);
      return path;

  // ⭐ STAR
    case 1:
      final path = Path();
      const points = 5;
      final radius = w / 2;

      for (int i = 0; i < points * 2; i++) {
        final isOuter = i % 2 == 0;
        final r = isOuter ? radius : radius / 2;
        final angle = pi * i / points;

        final x = radius + r * cos(angle);
        final y = radius + r * sin(angle);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      return path;

  // 🔥 FLAME (OLOV)
    case 2:
      final path = Path();
      path.moveTo(w * 0.5, h * 0.1);
      path.quadraticBezierTo(w * 0.9, h * 0.4, w * 0.5, h * 0.9);
      path.quadraticBezierTo(w * 0.1, h * 0.4, w * 0.5, h * 0.1);
      return path;

  // 🙂 SIMPLE EMOJI CIRCLE
    case 3:
    default:
      final path = Path()..addOval(Rect.fromCircle(center: Offset(w/2, h/2), radius: w/2));
      return path;
  }
}
