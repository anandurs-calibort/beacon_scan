// lib/helpers/filters.dart
import 'dart:math' as math;

/// Convert RSSI to estimated distance (in meters)
double estimateDistanceFromRssi(int rssi, {int txPower = -59, double n = 2.0}) {
  return math.pow(10, (txPower - rssi) / (10 * n)).toDouble();
}

/// Exponential Weighted Moving Average smoothing
double ewma(double prev, double raw, double alpha) {
  return alpha * raw + (1 - alpha) * prev;
}

/// Clamp sudden unrealistic jumps
double clampJump(double prev, double next, double maxDeltaMeters) {
  final diff = next - prev;
  if (diff.abs() > maxDeltaMeters) {
    return prev + diff.sign * maxDeltaMeters;
  }
  return next;
}
