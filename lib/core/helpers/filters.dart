// lib/helpers/filters.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Convert RSSI to estimated distance (in meters)
double estimateDistanceFromRssi(int rssi, {int txPower = -59, double n = 2.0}) {
  final dist = math.pow(10, (txPower - rssi) / (10 * n)).toDouble();
  debugPrint("🔹 RSSI→Distance | RSSI:$rssi  tx:$txPower  → RawDist:${dist.toStringAsFixed(3)} m");
  return dist;
}

/// Exponential Weighted Moving Average smoothing
double ewma(double prev, double raw, double alpha) {
  final val = alpha * raw + (1 - alpha) * prev;
  debugPrint("🔸 EWMA | prev:${prev.toStringAsFixed(3)}  raw:${raw.toStringAsFixed(3)}  → ewma:${val.toStringAsFixed(3)}");
  return val;
}
/// Clamp sudden unrealistic jumps
double clampJump(double prev, double next, double maxDeltaMeters) {
  final diff = next - prev;
  if (diff.abs() > maxDeltaMeters) {
    final clamped = prev + diff.sign * maxDeltaMeters;
    debugPrint("⚠️ Clamp | prev:${prev.toStringAsFixed(3)}  next:${next.toStringAsFixed(3)}  MAX:$maxDeltaMeters  → CLAMPED:${clamped.toStringAsFixed(3)}");
    return clamped;
  }
  return next;
}