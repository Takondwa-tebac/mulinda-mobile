import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

/// A stable id for this phone, sent once when the free trial starts so the
/// server can allow one trial per phone (it stores only a salted hash).
/// Android: the per-app ANDROID_ID. iOS: identifierForVendor. Null when it
/// cannot be read; the trial still starts, the server just cannot check.
class TrialDeviceId {
  TrialDeviceId._();

  static const _channel = MethodChannel('mulinda/device');

  static Future<String?> read() async {
    try {
      if (Platform.isAndroid) {
        final id = await _channel.invokeMethod<String>('androidId');
        return (id == null || id.isEmpty) ? null : id;
      }
      if (Platform.isIOS) {
        return (await DeviceInfoPlugin().iosInfo).identifierForVendor;
      }
    } catch (_) {
      // Not available (tests, desktop, an old plugin): no id.
    }
    return null;
  }
}
