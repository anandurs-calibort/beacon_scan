import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Beacon observation model
// class Observation {
//   final String id;
//   final String type;
//   final String info;
//   final int rssi;
//   final ScanMode scanMode;
//
//   Observation({
//     required this.id,
//     required this.type,
//     required this.info,
//     required this.rssi,
//     required this.scanMode,
//   });
// }

class Observation {
  final String id;
  final String type; // iBeacon / Eddystone
  final String info;
  final int rssi;
  final DateTime seenAt;

  Observation({
    required this.id,
    required this.type,
    required this.info,
    required this.rssi,
    required this.seenAt,
  });

  Observation copyUpdated({int? rssi, DateTime? seenAt}) => Observation(
    id: id,
    type: type,
    info: info,
    rssi: rssi ?? this.rssi,
    seenAt: seenAt ?? this.seenAt,
  );
}
