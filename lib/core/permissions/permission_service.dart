import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Thin wrapper over permission_handler. Permissions are requested in-context
/// (camera when scanning a receipt, notifications during first-run setup).
class PermissionService {
  Future<bool> requestCamera() async => (await Permission.camera.request()).isGranted;

  Future<bool> requestPhotos() async => (await Permission.photos.request()).isGranted;

  Future<bool> requestSms() async => (await Permission.sms.request()).isGranted;

  /// Best-effort: returns whether notifications are allowed; never throws.
  Future<bool> requestNotifications() async {
    try {
      return (await Permission.notification.request()).isGranted;
    } catch (_) {
      return false;
    }
  }
}

final permissionServiceProvider = Provider<PermissionService>((ref) => PermissionService());
