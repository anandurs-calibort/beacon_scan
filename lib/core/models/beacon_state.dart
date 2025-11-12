import 'kalman_filter.dart';

class BeaconState {
  final String id;
  double rawDistance;
  double filteredDistance;
  int rssi;
  DateTime lastSeen;
  double? bearing; // Angle of Arrival in degrees (optional)
  KalmanFilter1D? kalman; // One Kalman instance per beacon


  BeaconState({
    required this.id,
    required this.rawDistance,
    required this.filteredDistance,
    required this.rssi,
    required this.lastSeen,

  });

  void update(int newRssi, double newDistance) {
    rssi = newRssi;
    rawDistance = newDistance;
    lastSeen = DateTime.now();
  }
}