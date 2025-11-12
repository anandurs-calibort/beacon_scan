import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/beacon_fix.dart';

Offset? trilaterate(BeaconFix a, BeaconFix b, BeaconFix c) {
  final x1 = 0.0, y1 = 0.0, r1 = a.dist;
  final x2 = b.pos.dx - a.pos.dx;
  final y2 = b.pos.dy - a.pos.dy;
  final r2 = b.dist;
  final x3 = c.pos.dx - a.pos.dx;
  final y3 = c.pos.dy - a.pos.dy;
  final r3 = c.dist;

  final A11 = -2 * x2;
  final A12 = -2 * y2;
  final A21 = -2 * x3;
  final A22 = -2 * y3;

  final B1 = r1 * r1 - r2 * r2 + x2 * x2 + y2 * y2;
  final B2 = r1 * r1 - r3 * r3 + x3 * x3 + y3 * y3;

  final det = A11 * A22 - A12 * A21;
  if (det.abs() < 1e-6) return null;

  final px = (A22 * B1 - A12 * B2) / det;
  final py = (-A21 * B1 + A11 * B2) / det;

  return Offset(px + a.pos.dx, py + a.pos.dy);
}

Offset estimateFromTwo(BeaconFix a, BeaconFix b) {
  final dx = b.pos.dx - a.pos.dx;
  final dy = b.pos.dy - a.pos.dy;
  final d = math.sqrt(dx * dx + dy * dy).clamp(1e-6, double.infinity);
  final ux = dx / d;
  final uy = dy / d;
  return Offset(a.pos.dx + ux * a.dist, a.pos.dy + uy * a.dist);
}
