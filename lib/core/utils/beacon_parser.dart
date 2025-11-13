
// -------------------------
// Advertisement parsing
// - handles Uint8List manufacturerData and Map<Uuid,Uint8List> serviceData
// - returns an Observation if iBeacon or Eddystone found, otherwise null
// - also extracts AoA angle when embedded
// -------------------------
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../models/beacon_observation_model.dart';

Observation? _parseAdvertisement({
  required String id,
  required int rssi,
  required Uint8List? manufacturerData,
  required Map<Uuid, Uint8List>? serviceData,
}) {
  // convert to List<int> defensively
  final manu = manufacturerData != null ? List<int>.from(manufacturerData) : <int>[];
  // debug hex
  if (manu.isNotEmpty) {
    final hex = manu.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    debugPrint('📡 Manu($id): $hex');
  }
  if (serviceData != null && serviceData.isNotEmpty) {
    for (final e in serviceData.entries) {
      final hex = List<int>.from(e.value).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
      debugPrint('📡 Service ${e.key} ($id): $hex');
    }
  }

  // Try iBeacon pattern in manufacturer data
  // Apple iBeacon packet is: companyID 0x004C (0x4C 0x00) followed by 0x02 0x15, then 16 byte UUID, 2 byte major, 2 byte minor, 1 byte tx
  if (manu.length >= 25) {
    // search for sequence 0x4C 0x00 0x02 0x15 (Apple) or the short 0x02 0x15 sequence at some offset
    for (int i = 0; i <= manu.length - 22; i++) {
      final applePrefix = i + 3 < manu.length &&
          manu[i] == 0x4C &&
          manu[i + 1] == 0x00 &&
          manu[i + 2] == 0x02 &&
          manu[i + 3] == 0x15;
      final barePrefix = i + 1 < manu.length && manu[i] == 0x02 && manu[i + 1] == 0x15;

      if (applePrefix || barePrefix) {
        final offset = applePrefix ? i + 4 : i + 2;
        if (offset + 20 <= manu.length) {
          final uuidBytes = manu.sublist(offset, offset + 16);
          final major = (manu[offset + 16] << 8) | manu[offset + 17];
          final minor = (manu[offset + 18] << 8) | manu[offset + 19];
          final uuid = _bytesToUuid(uuidBytes);

          // Try read AoA from manufacturer trailing bytes (if any)
          final aoa = _tryExtractAoAFromBytes(manu);

          debugPrint('✅ [iBeacon Detected] $id  UUID:$uuid major:$major minor:$minor rssi:$rssi AoA:${aoa?.toStringAsFixed(1) ?? "—"}');
          final obs = Observation(id: id, type: 'iBeacon', info: '($uuid / $major / $minor)', rssi: rssi, seenAt: DateTime.now());
          // attach AoA to observation if your Observation supports it — else we will set it in BeaconState later
          return obs;
        }
      }
    }
  }

  // Try Eddystone UID in serviceData where service UUID FEAA is present and frame type 0x00 UID
  if (serviceData != null && serviceData.isNotEmpty) {
    for (final entry in serviceData.entries) {
      final svcUuid = entry.key;
      final bytes = List<int>.from(entry.value);
      // FEAA service indicates Eddystone
      if (svcUuid.toString().toUpperCase().contains('FEAA') && bytes.isNotEmpty) {
        final frameType = bytes[0];
        if (frameType == 0x00 && bytes.length >= 18) {
          // UID frame
          final namespace = bytes.sublist(2, 12).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
          final instance = bytes.sublist(12, 18).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
          final aoa = _tryExtractAoAFromBytes(bytes);

          debugPrint('✅ [Eddystone UID] $id  namespace:$namespace instance:$instance rssi:$rssi AoA:${aoa?.toStringAsFixed(1) ?? "—"}');
          return Observation(id: id, type: 'Eddystone', info: '($namespace / $instance)', rssi: rssi, seenAt: DateTime.now());
        }
        // other Eddystone frames (URL, TLM) are possible, ignore here
      }
    }
  }

  // No known pattern
  return null;
}



// Extract AoA from raw byte array (some beacons append angle in last two bytes as little-endian tenths of degree)
double? _tryExtractAoAFromBytes(List<int> bytes) {
  // check last 2 bytes
  if (bytes.length >= 2) {
    final v = (bytes[bytes.length - 2] & 0xFF) | ((bytes[bytes.length - 1] & 0xFF) << 8);
    if (v > 0 && v <= 3600) return v / 10.0;
  }
  // fallback none
  return null;
}

String _bytesToUuid(List<int> bytes) {
  final hex = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
