import 'kalman_filter.dart';
class BeaconState {
  final String id;
  double rawDistance;
  double filteredDistance; // the one currently used by logic
  double? bearing;
  int rssi;
  DateTime lastSeen;

  // NEW:
  double ewmaDistance;
  double kalmanDistance;
  KalmanFilter1D? kalman;

  BeaconState({
    required this.id,
    required this.rawDistance,
    required this.filteredDistance,
    required this.rssi,
    required this.lastSeen,
    this.bearing,
    this.kalman,
    double? ewmaDistance,
    double? kalmanDistance,
  })  : ewmaDistance = ewmaDistance ?? rawDistance,
        kalmanDistance = kalmanDistance ?? rawDistance;


  void update(int newRssi, double newDistance) {
    rssi = newRssi;
    rawDistance = newDistance;
    lastSeen = DateTime.now();
  }
}