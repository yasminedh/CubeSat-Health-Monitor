class Telemetry {
  final double temp;
  final double pressure;
  final double altitude;
  final int battery;
  final String mode;

  Telemetry({
    required this.temp,
    required this.pressure,
    required this.altitude,
    required this.battery,
    required this.mode,
  });

  factory Telemetry.fromJson(Map<String, dynamic> json) {
    return Telemetry(
      temp: (json["temp"] ?? 0).toDouble(),
      pressure: (json["pressure"] ?? 0).toDouble(),
      altitude: (json["altitude"] ?? 0).toDouble(),
      battery: json["battery"] ?? 0,
      mode: json["mode"] ?? "UNKNOWN",
    );
  }
}