import 'package:flutter/material.dart';
import '../core/models/beacon_observation_model.dart';
import '../core/models/beacon_state.dart';
class BeaconTile extends StatelessWidget {
  final Observation observation;
  final BeaconState? state;
  final Offset? position;


  const BeaconTile({
    super.key,
    required this.observation,
    this.state, this.position,
  });

  @override
  Widget build(BuildContext context) {
    final dist = state?.filteredDistance ?? observation.distance;

    final typeIcon = observation.type == 'iBeacon'
        ? Icons.bluetooth_searching
        : (observation.type == 'Eddystone'
        ? Icons.wifi
        : Icons.bluetooth);

    return ListTile(
      leading: Icon(
        typeIcon,
        color: observation.type == 'iBeacon'
            ? Colors.blueAccent
            : Colors.orangeAccent,
      ),

      // --------------------------
      // TITLE
      // --------------------------
      title: Text(
        '${observation.type} ${observation.info}',
        style: const TextStyle(color: Colors.white),
      ),

      // --------------------------
      // SUBTITLE (MULTI-LINE → no overflow)
      // --------------------------
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device: ${observation.id}',
            style: const TextStyle(color: Colors.white54),
          ),
          Text(
            'AoA: ${state?.bearing?.toStringAsFixed(1) ?? "—"}°',
            style: const TextStyle(color: Colors.white54),
          ),

          if (state != null) ...[
            Text(
              'Raw: ${state!.rawDistance.toStringAsFixed(2)} m',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
            Text(
              'EWMA: ${state!.ewmaDistance.toStringAsFixed(2)} m',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
            ),
            Text(
              'Kalman: ${state!.kalmanDistance.toStringAsFixed(2)} m',
              style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11),
            ),
          ],

          if (position != null)
            Text(
              'Position: (${position!.dx.toStringAsFixed(1)}, ${position!.dy.toStringAsFixed(1)})',
              style: const TextStyle(color: Colors.white54),
            ),
        ],
      ),

      trailing: Text(
        '${observation.rssi} dBm',
        style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
      ),
    );
  }
}
