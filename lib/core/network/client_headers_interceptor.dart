import 'dart:io' show Platform;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// A random RFC 4122 version 4 UUID (no package needed).
String uuidV4([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
  String hex(int from, int to) => b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// Tells the API which app sent each request (see the round-2 contract):
/// `X-App-Version`, `X-Platform` (android|ios), `X-OS-Version` (≤ 100 chars) and
/// a fresh `X-Request-Id` per request. The server stores them with audits and
/// product events. No device model is sent.
class ClientHeadersInterceptor extends Interceptor {
  ClientHeadersInterceptor({
    Future<String> Function()? appVersion,
    String? platform,
    String? osVersion,
    String Function()? requestId,
  }) : _appVersion = appVersion ?? _packageVersion,
       _platform = platform ?? _currentPlatform(),
       _osVersion = _truncate(osVersion ?? _currentOsVersion()),
       _requestId = requestId ?? uuidV4;

  final Future<String> Function() _appVersion;
  final String _platform;
  final String _osVersion;
  final String Function() _requestId;
  Future<String>? _version;

  static Future<String> _packageVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  static String _currentPlatform() {
    try {
      return Platform.isIOS ? 'ios' : 'android';
    } catch (_) {
      return 'android';
    }
  }

  static String _currentOsVersion() {
    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return 'unknown';
    }
  }

  static String _truncate(String v) => v.length <= 100 ? v : v.substring(0, 100);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    String version;
    try {
      version = await (_version ??= _appVersion());
    } catch (_) {
      version = 'unknown';
    }
    options.headers
      ..['X-App-Version'] = version
      ..['X-Platform'] = _platform
      ..['X-OS-Version'] = _osVersion
      ..['X-Request-Id'] = _requestId();
    handler.next(options);
  }
}
