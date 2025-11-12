class KalmanFilter1D {
  double estimate;
  double error;
  final double processNoise;
  final double measurementNoise;

  KalmanFilter1D({
    required this.estimate,
    this.error = 1,
    this.processNoise = 0.008,
    this.measurementNoise = 0.1,
  });

  double update(double measurement) {
    // Prediction update
    error += processNoise;

    // Measurement update
    final gain = error / (error + measurementNoise);
    estimate = estimate + gain * (measurement - estimate);
    error = (1 - gain) * error;

    return estimate;
  }
}
