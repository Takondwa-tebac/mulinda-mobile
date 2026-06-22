import 'package:dio/dio.dart';

/// A user-presentable API error, parsed from a Laravel JSON error response
/// (`{message, errors: {field: [..]}}`) or a transport failure.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.errors = const {}});

  final String message;
  final int? statusCode;
  final Map<String, List<String>> errors;

  /// The first field-level validation message, if any, else [message].
  String get displayMessage {
    if (errors.isNotEmpty) return errors.values.first.first;
    return message;
  }

  factory ApiException.fromDio(DioException e) {
    final response = e.response;
    final data = response?.data;

    if (data is Map) {
      final message = data['message']?.toString() ?? 'Something went wrong.';
      final errors = <String, List<String>>{};
      if (data['errors'] is Map) {
        (data['errors'] as Map).forEach((key, value) {
          if (value is List) {
            errors[key.toString()] = value.map((v) => v.toString()).toList();
          }
        });
      }
      return ApiException(message, statusCode: response?.statusCode, errors: errors);
    }

    final transport = switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'The server took too long to respond. Please try again.',
      DioExceptionType.connectionError =>
        'Cannot reach the server. Check your internet connection.',
      _ => 'Something went wrong. Please try again.',
    };
    return ApiException(transport, statusCode: response?.statusCode);
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
