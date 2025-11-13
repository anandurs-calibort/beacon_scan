import 'package:flutter/material.dart';
import '../core/helpers/filters.dart';
import '../core/models/beacon_observation_model.dart';
import '../core/models/beacon_state.dart';


class BeaconTile extends StatelessWidget {
  final Observation observation;
  final BeaconState? state;

  const BeaconTile({
    super.key,
    required this.observation,
    this.state,
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
      title: Text(
        '${observation.type} ${observation.info}',
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        'Device: ${observation.id}\nAoA: ${state?.bearing?.toStringAsFixed(1) ?? "—"}°',
        style: const TextStyle(color: Colors.white54),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${observation.rssi} dBm',
            style: const TextStyle(color: Colors.greenAccent),
          ),
          Text(
            '~${dist.toStringAsFixed(2)} m',
            style: const TextStyle(
              color: Colors.orangeAccent,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

