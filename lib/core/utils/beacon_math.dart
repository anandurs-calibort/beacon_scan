import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/beacon_fix.dart';

// 📍 Rough estimate using 2 beacons
Offset estimateFromTwo(BeaconFix a, BeaconFix b) {
  final dx = b.pos.dx - a.pos.dx;
  final dy = b.pos.dy - a.pos.dy;
  final d = math.sqrt(dx * dx + dy * dy).clamp(1e-6, double.infinity);
  final ux = dx / d;
  final uy = dy / d;
  return Offset(a.pos.dx + ux * a.dist, a.pos.dy + uy * a.dist);
}

// 🧭 Convert bearing + distance to a point
Offset bearingToPoint(Offset origin, double bearingDeg, double dist) {
  final rad = bearingDeg * math.pi / 180.0;
  return Offset(origin.dx + dist * math.cos(rad), origin.dy + dist * math.sin(rad));
}

// 🧮 Combine multiple beacons using distance + bearing
Offset? combineDistanceAndBearing(Map<String, BeaconFix> fixes, Map<String, double> bearings) {
  final points = <Offset>[];
  for (final entry in fixes.entries) {
    final id = entry.key;
    final fix = entry.value;
    final bearing = bearings[id];
    if (bearing != null) {
      points.add(bearingToPoint(fix.pos, bearing, fix.dist));
    }
  }
  if (points.isEmpty) return null;
  final avgX = points.map((p) => p.dx).reduce((a, b) => a + b) / points.length;
  final avgY = points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
  return Offset(avgX, avgY);
}

