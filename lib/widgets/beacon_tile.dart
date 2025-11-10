import 'package:flutter/material.dart';

import '../core/models/becon_data.dart';

class BeaconTile extends StatelessWidget {
  final   BeaconData beacon;

  const BeaconTile({super.key, required this.beacon});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: Icon(
          beacon.type == "iBeacon" ? Icons.bluetooth_searching : Icons.bluetooth,
          color: beacon.type == "iBeacon" ? Colors.purple : Colors.blueAccent,
        ),
        title: Text(
          '${beacon.type} (${beacon.details})',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(beacon.id),
        trailing: Text(
          '${beacon.rssi} dBm',
          style: const TextStyle(color: Colors.black54),
        ),
      ),
    );
  }
}
