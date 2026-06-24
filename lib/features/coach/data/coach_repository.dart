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

      // SSE events are separated by double newline.
      final parts = buffer.split('\n\n');
      buffer = parts.removeLast(); // Keep any incomplete trailing fragment.

      for (final block in parts) {
        for (final line in block.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data == '[DONE]') return;
          try {
            final parsed = jsonDecode(data) as Map<String, dynamic>;
            final type = parsed['type'] as String?;
            if (type == 'delta') {
              yield CoachChunk(text: parsed['content'] as String?);
            } else if (type == 'chart_hint') {
              final kind = parsed['kind'] as String?;
              if (kind != null) {
                final rawParams = parsed['params'];
                final params = rawParams is Map
                    ? rawParams.cast<String, dynamic>()
                    : <String, dynamic>{};
                yield CoachChunk(chartHint: ChartHint(kind: kind, params: params));
              }
            } else if (type == 'done') {
              yield CoachChunk(
                isDone: true,
                conversationId: parsed['conversation_id']?.toString(),
              );
              return;
            }
          } catch (_) {
            // Skip malformed SSE lines.
          }
        }
      }
    }
  }
}

final coachRepositoryProvider =
    Provider<CoachRepository>((ref) => CoachRepository(ref.read(dioProvider)));
