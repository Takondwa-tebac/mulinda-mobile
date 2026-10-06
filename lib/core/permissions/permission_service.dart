import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// What the OS currently says about a permission.
enum PermState {
  granted,

  /// Not granted yet — a request can still show the system prompt.
  denied,

  /// The user chose "don't ask again" (or policy blocks it) — only the system
  /// settings can change it.
  blocked,
}

/// Thin wrapper over permission_handler. Permissions are requested in-context
/// (camera when scanning a receipt, notifications during first-run setup).
///
/// The OS is the source of truth: always read the status here instead of
/// remembering it in widget state, so screens reflect what is really granted.
class PermissionService {
  PermState _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited || s.isProvisional) return PermState.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return PermState.blocked;
    return PermState.denied;
  }

  Future<PermState> _status(Permission p) async {
    try {
      return _map(await p.status);
    } catch (_) {
      return PermState.denied;
    }
  }

  Future<PermState> _request(Permission p) async {
    try {
      return _map(await p.request());
    } catch (_) {
      return PermState.denied;
    }
  }

  Future<PermState> cameraStatus() => _status(Permission.camera);
  Future<PermState> notificationsStatus() => _status(Permission.notification);
  Future<PermState> smsStatus() => _status(Permission.sms);

  Future<PermState> requestCameraState() => _request(Permission.camera);
  Future<PermState> requestNotificationsState() => _request(Permission.notification);

  /// Opens the app's page in system settings (for blocked permissions).
  Future<bool> openSettings() => openAppSettings();

  Future<bool> requestCamera() async => (await requestCameraState()) == PermState.granted;

  Future<bool> requestPhotos() async => (await Permission.photos.request()).isGranted;

  Future<bool> requestSms() async => (await Permission.sms.request()).isGranted;

  /// Best-effort: returns whether notifications are allowed; never throws.
  Future<bool> requestNotifications() async =>
      (await requestNotificationsState()) == PermState.granted;
}

final permissionServiceProvider = Provider<PermissionService>((ref) => PermissionService());
