import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/coach/data/coach_repository.dart';

/// Answers the chat stream with a fixed status, headers and body.
class _Server implements HttpClientAdapter {
  _Server(this.status, this.body, {this.headers = const {}});

  final int status;
  final String body;
  final Map<String, List<String>> headers;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    return ResponseBody.fromString(body, status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

CoachRepository _repo(_Server server) => CoachRepository(Dio(BaseOptions(baseUrl: 'https://api.test', validateStatus: (s) => s != null && s < 400))
  ..httpClientAdapter = server);

void main() {
  test('a refusal because the AI is busy tells the chat how long to wait', () async {
    final repo = _repo(_Server(429, jsonEncode({'code': 'ai_rate_limited'}), headers: {
      'retry-after': ['42'],
    }));

    expect(
      repo.sendStream('Hi').toList(),
      throwsA(isA<CoachBusyException>().having((e) => e.retryAfter, 'retryAfter', 42)),
    );
  });

  test('without a wait time the chat waits a minute', () async {
    final repo = _repo(_Server(429, '{}'));

    expect(repo.sendStream('Hi').toList(), throwsA(isA<CoachBusyException>().having((e) => e.retryAfter, 'retryAfter', 60)));
  });

  test('a rate limit in the middle of a reply arrives as an event with the wait', () async {
    final body = 'data: ${jsonEncode({'type': 'delta', 'content': 'Your spending'})}\n\n'
        'data: ${jsonEncode({'type': 'rate_limited', 'retry_after': 30, 'message': 'busy'})}\n\n'
        'data: ${jsonEncode({'type': 'done', 'conversation_id': 'c1'})}\n\n';
    final repo = _repo(_Server(200, body));

    final chunks = await repo.sendStream('Hi').toList();

    expect(chunks.first.text, 'Your spending');
    expect(chunks.any((c) => c.busyRetryAfter == 30), true);
  });

  test('a long wait from the server is kept, not cut short', () async {
    final repo = _repo(_Server(429, '{}', headers: {
      'retry-after': ['3600'],
    }));

    expect(repo.sendStream('Hi').toList(), throwsA(isA<CoachBusyException>().having((e) => e.retryAfter, 'retryAfter', 3600)));
  });

  test('a normal reply is unaffected', () async {
    final body = 'data: ${jsonEncode({'type': 'delta', 'content': 'Hello'})}\n\n'
        'data: ${jsonEncode({'type': 'done', 'conversation_id': 'c1'})}\n\n';
    final chunks = await _repo(_Server(200, body)).sendStream('Hi').toList();

    expect(chunks.map((c) => c.busyRetryAfter), everyElement(isNull));
    expect(chunks.last.isDone, true);
  });
}
