import 'package:dio/dio.dart';

/// Typed error codes from the RiMi API error envelope.
/// Source: docs/contracts/README.md §6 Error-code catalog.
enum ApiErrorCode {
  validationError,
  weakPassword,
  unauthorized,
  invalidCredentials,
  refreshTokenInvalid,
  refreshTokenReused,
  workspaceForbidden,
  workspaceNotFound,
  tokenInvalidOrExpired,
  workspaceIdConflict,
  payloadTooLarge,
  rateLimited,
  accountLocked,
  internalError,
  serviceUnavailable,
  unknown,
}

/// Maps the API's SCREAMING_SNAKE_CASE codes to typed enum values.
ApiErrorCode _parseCode(String? code) => switch (code) {
      'VALIDATION_ERROR' => ApiErrorCode.validationError,
      'WEAK_PASSWORD' => ApiErrorCode.weakPassword,
      'UNAUTHORIZED' => ApiErrorCode.unauthorized,
      'INVALID_CREDENTIALS' => ApiErrorCode.invalidCredentials,
      'REFRESH_TOKEN_INVALID' => ApiErrorCode.refreshTokenInvalid,
      'REFRESH_TOKEN_REUSED' => ApiErrorCode.refreshTokenReused,
      'WORKSPACE_FORBIDDEN' => ApiErrorCode.workspaceForbidden,
      'WORKSPACE_NOT_FOUND' => ApiErrorCode.workspaceNotFound,
      'TOKEN_INVALID_OR_EXPIRED' => ApiErrorCode.tokenInvalidOrExpired,
      'WORKSPACE_ID_CONFLICT' => ApiErrorCode.workspaceIdConflict,
      'PAYLOAD_TOO_LARGE' => ApiErrorCode.payloadTooLarge,
      'RATE_LIMITED' => ApiErrorCode.rateLimited,
      'ACCOUNT_LOCKED' => ApiErrorCode.accountLocked,
      'INTERNAL_ERROR' => ApiErrorCode.internalError,
      'SERVICE_UNAVAILABLE' => ApiErrorCode.serviceUnavailable,
      _ => ApiErrorCode.unknown,
    };

/// Per-field validation detail.
class ApiErrorDetail {
  const ApiErrorDetail({required this.field, required this.issue});
  final String field;
  final String issue;

  factory ApiErrorDetail.fromJson(Map<String, dynamic> json) =>
      ApiErrorDetail(
        field: (json['field'] as String?) ?? '',
        issue: (json['issue'] as String?) ?? '',
      );
}

/// Typed API exception wrapping the error envelope.
/// { "error": { "code": "...", "message": "...", "details": [] } }
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.details = const [],
    this.statusCode,
  });

  final ApiErrorCode code;
  final String message;
  final List<ApiErrorDetail> details;
  final int? statusCode;

  /// Whether this is an authentication failure (401 on protected endpoint).
  bool get isUnauthorized => code == ApiErrorCode.unauthorized;

  /// Whether the refresh token is invalid/expired/reused.
  bool get isRefreshTokenFailure =>
      code == ApiErrorCode.refreshTokenInvalid ||
      code == ApiErrorCode.refreshTokenReused;

  @override
  String toString() => 'ApiException($code, $message)';

  /// Parses a Dio error into an [ApiException]. Handles the error envelope,
  /// network errors, and unknown shapes defensively.
  static ApiException fromDioError(DioException e) {
    final statusCode = e.response?.statusCode;

    // Try to parse the error envelope: { "error": { code, message, details } }
    try {
      final data = e.response?.data;
      if (data is Map<String, dynamic> && data.containsKey('error')) {
        final errorBody = data['error'] as Map<String, dynamic>;
        final rawCode = errorBody['code'] as String?;
        final message = (errorBody['message'] as String?) ?? 'Unknown error';
        final rawDetails = errorBody['details'];
        final details = <ApiErrorDetail>[];
        if (rawDetails is List) {
          for (final d in rawDetails) {
            if (d is Map<String, dynamic>) {
              details.add(ApiErrorDetail.fromJson(d));
            }
          }
        }
        return ApiException(
          code: _parseCode(rawCode),
          message: message,
          details: details,
          statusCode: statusCode,
        );
      }
    } catch (_) {
      // Fall through to generic error
    }

    // Network / timeout errors
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException(
        code: ApiErrorCode.unknown,
        message: 'Kết nối bị gián đoạn. Vui lòng thử lại.',
        statusCode: statusCode,
      );
    }

    if (e.type == DioExceptionType.connectionError) {
      return ApiException(
        code: ApiErrorCode.unknown,
        message: 'Không thể kết nối đến máy chủ.',
        statusCode: statusCode,
      );
    }

    return ApiException(
      code: ApiErrorCode.unknown,
      message: 'Đã có lỗi xảy ra. Vui lòng thử lại.',
      statusCode: statusCode,
    );
  }
}
