import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class CoachReply {
  const CoachReply({required this.reply, this.conversationId});
  final String reply;
  final String? conversationId;
}

class CoachHistoryMessage {
  const CoachHistoryMessage({required this.role, required this.content});
  final String role; // 'user' | 'assistant'
  final String content;
}

class CoachHistory {
  const CoachHistory({required this.conversationId, required this.messages});
  final String conversationId;
  final List<CoachHistoryMessage> messages;
}

class ChartHint {
  const ChartHint({required this.kind, this.params = const {}});
  final String kind; // 'category_breakdown' | 'account_balances' | 'spending_summary' | 'savings_rule'
  final Map<String, dynamic> params;
}

class CoachChunk {
  const CoachChunk({this.text, this.isDone = false, this.conversationId, this.chartHint});
  final String? text;
  final bool isDone;
  final String? conversationId;
  final ChartHint? chartHint;
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class CoachRepository {
  CoachRepository(this._dio);

  final Dio _dio;

  /// Non-streaming fallback — kept for compatibility.
  Future<CoachReply> send(String message, {String? conversationId}) async {
    final body = <String, dynamic>{'message': message};
    if (conversationId != null) body['conversation_id'] = conversationId;

    try {
      final res = await _dio.post(
        '/v1/coach/chat',
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 90)),
      );
      final data = (res.data['data'] as Map).cast<String, dynamic>();
      return CoachReply(
        reply: data['reply']?.toString() ?? '',
        conversationId: data['conversation_id']?.toString(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Fetch the user's most recent conversation and its messages.
  /// Returns null if the user has no conversation history yet.
  Future<CoachHistory?> loadHistory() async {
    try {
      final res = await _dio.get('/v1/coach/history');
      final data = (res.data['data'] as Map).cast<String, dynamic>();
      final convId = data['conversation_id']?.toString();
      if (convId == null) return null;

      final rawMessages = data['messages'] as List? ?? [];
      final messages = rawMessages
          .cast<Map>()
          .map((m) => CoachHistoryMessage(
                role: m['role']?.toString() ?? 'user',
                content: m['content']?.toString() ?? '',
              ))
          .toList();

      return CoachHistory(conversationId: convId, messages: messages);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Send a message and stream the reply as [CoachChunk] events.
  ///
  /// Yields [CoachChunk.text] events as tokens arrive, then a final
  /// [CoachChunk.isDone] event carrying the [CoachChunk.conversationId].
  Stream<CoachChunk> sendStream(
    String message, {
    String? conversationId,
  }) async* {
    final body = <String, dynamic>{'message': message};
    if (conversationId != null) body['conversation_id'] = conversationId;

    late final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '/v1/coach/stream',
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 3),
        ),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }

    var buffer = '';

    await for (final bytes in response.data!.stream) {
      buffer += utf8.decode(bytes, allowMalformed: true);

      // SSE events are separated by a blank line.
      final parts = buffer.split('\n\n');
      buffer = parts.removeLast(); // Keep any incomplete trailing fragment.

      for (final block in parts) {
        for (final chunk in _parseBlock(block)) {
          yield chunk;
          if (chunk.isDone) return;
        }
      }
    }

    // The stream can close with a complete-but-unterminated final event still
    // sitting in the buffer (no trailing blank line). Flush it so the last
    // tokens / the done event aren't lost.
    for (final chunk in _parseBlock(buffer)) {
      yield chunk;
      if (chunk.isDone) return;
    }

    // Stream ended without an explicit done — emit one so the UI finalises the
    // message and re-enables the input.
    yield const CoachChunk(isDone: true);
  }

  /// Parse one SSE block (which may contain several `data:` lines) into chunks.
  List<CoachChunk> _parseBlock(String block) {
    final out = <CoachChunk>[];
    for (final line in block.split('\n')) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(line.indexOf(':') + 1).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') {
        out.add(const CoachChunk(isDone: true));
        continue;
      }
      try {
        final parsed = jsonDecode(data) as Map<String, dynamic>;
        switch (parsed['type'] as String?) {
          case 'delta':
            out.add(CoachChunk(text: parsed['content'] as String?));
          case 'chart_hint':
            final kind = parsed['kind'] as String?;
            if (kind != null) {
              final rawParams = parsed['params'];
              out.add(CoachChunk(
                chartHint: ChartHint(
                  kind: kind,
                  params: rawParams is Map ? rawParams.cast<String, dynamic>() : const {},
                ),
              ));
            }
          case 'done':
            out.add(CoachChunk(isDone: true, conversationId: parsed['conversation_id']?.toString()));
        }
      } catch (_) {
        // Skip malformed SSE lines.
      }
    }
    return out;
  }
}

final coachRepositoryProvider =
    Provider<CoachRepository>((ref) => CoachRepository(ref.read(dioProvider)));
