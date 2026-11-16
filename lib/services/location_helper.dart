import 'package:geolocator/geolocator.dart';

/// GPS settings for the whole app.
/// forceLocationManager: use Android's built-in GPS service instead of the
/// Google Play Services "fused" provider, which crashed on the Android 17
/// emulator. Plain GPS is also more predictable on budget phones.
LocationSettings gpsSettings({LocationAccuracy accuracy = LocationAccuracy.high, int seconds = 20}) =>
    AndroidSettings(
      accuracy: accuracy,
      timeLimit: Duration(seconds: seconds),
      forceLocationManager: true,
    );

Future<Position?> lastKnownPosition() =>
    Geolocator.getLastKnownPosition(forceAndroidLocationManager: true);
