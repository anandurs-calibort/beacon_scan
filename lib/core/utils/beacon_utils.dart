import 'dart:math';
import 'package:flutter/material.dart';

double estimateDistance(int rssi, {int txPower = -75, double n = 2.0}) {
  final distance = pow(10, (txPower - rssi) / (10 * n)).toDouble();
  debugPrint('📏 [DistanceCalc] RSSI: $rssi | TxPower: $txPower | n: $n → Estimated: ${distance.toStringAsFixed(2)} m');
  return distance;
}

