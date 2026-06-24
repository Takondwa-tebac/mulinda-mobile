/// Build-time configuration. Override the API base URL with:
///   flutter run --dart-define=API_BASE_URL=https://api.example.com/api
abstract class AppEnv {
  /// Defaults to the Android emulator's host-machine loopback (`10.0.2.2`),
  /// which maps to `localhost` on the developer's machine.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // defaultValue: 'http://10.0.2.2:8000/api',
    defaultValue: 'http://192.168.1.197:8000/api',
  );
}
