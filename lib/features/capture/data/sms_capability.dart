import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Whether this device can read or listen for SMS on its own.
///
/// Only Android lets an app do that. iOS sandboxes the Messages inbox, so
/// there the user pastes or shares a message into Mulinda instead (still
/// propose-then-approve). Every Android-only SMS path checks this first, so
/// nothing touches the telephony plugins on other platforms.
class SmsCapability {
  SmsCapability._();

  static bool get canReadSms => !kIsWeb && Platform.isAndroid;
}
