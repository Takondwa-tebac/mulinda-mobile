import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/core/network/client_headers_interceptor.dart';

class _Recorder implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    return ResponseBody.fromString(
      jsonEncode({'data': []}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('every request carries the client headers and its own request id', () async {
    final recorder = _Recorder();
    final dio = Dio()
      ..httpClientAdapter = recorder
      ..interceptors.add(
        ClientHeadersInterceptor(appVersion: () async => '1.1.2+6', platform: 'android', osVersion: 'A' * 150),
      );

    await dio.get('https://example.test/a');
    await dio.get('https://example.test/b');

    final first = recorder.requests[0].headers;
    expect(first['X-App-Version'], '1.1.2+6');
    expect(first['X-Platform'], 'android');
    expect((first['X-OS-Version'] as String).length, 100);
    expect(first['X-Request-Id'], isNot(recorder.requests[1].headers['X-Request-Id']));
  });

  test('request ids are version 4 UUIDs', () {
    final id = uuidV4(Random(1));
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
  });

  test('a failing version lookup still sends the request', () async {
    final recorder = _Recorder();
    final dio = Dio()
      ..httpClientAdapter = recorder
      ..interceptors.add(ClientHeadersInterceptor(appVersion: () async => throw StateError('no plugin')));
    await dio.get('https://example.test/a');
    expect(recorder.requests.single.headers['X-App-Version'], 'unknown');
  });
}
