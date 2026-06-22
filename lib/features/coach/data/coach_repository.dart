import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';

class CoachReply {
  const CoachReply({required this.reply, this.conversationId});
  final String reply;
  final String? conversationId;
}

class CoachRepository {
  CoachRepository(this._dio);

  final Dio _dio;

  Future<CoachReply> send(String message, {String? conversationId}) async {
    final body = <String, dynamic>{'message': message};
    if (conversationId != null) body['conversation_id'] = conversationId;

    try {
      final res = await _dio.post(
        '/v1/coach/chat',
        data: body,
        // The coach calls tools and the model — allow a generous read timeout.
        options: Options(receiveTimeout: const Duration(seconds: 60)),
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
}

final coachRepositoryProvider =
    Provider<CoachRepository>((ref) => CoachRepository(ref.read(dioProvider)));
