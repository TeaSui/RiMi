import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/dio_client.dart';

/// State for the AI chat notifier.
class AiChatState {
  const AiChatState({
    this.isLoading = false,
    this.lastResponse,
    this.error,
  });

  final bool isLoading;
  final AiResponse? lastResponse;
  final String? error;

  AiChatState copyWith({
    bool? isLoading,
    AiResponse? lastResponse,
    String? error,
  }) {
    return AiChatState(
      isLoading: isLoading ?? this.isLoading,
      lastResponse: lastResponse ?? this.lastResponse,
      error: error,
    );
  }
}

/// Response from the AI generate endpoint.
class AiResponse {
  const AiResponse({
    required this.content,
    required this.tokensIn,
    required this.tokensOut,
  });

  final String content;
  final int tokensIn;
  final int tokensOut;
}

/// Notifier that logs AI usage to the backend.
///
/// The Flutter app does NOT call an LLM directly — the backend handles that.
/// This notifier calls POST /v1/ai/usage to record usage after a response is
/// received, and is wired to any in-app AI interaction.
class AiChatNotifier extends Notifier<AiChatState> {
  @override
  AiChatState build() => const AiChatState();

  Dio get _dio => ref.read(dioClientProvider);

  /// Logs a completed AI usage event to the server.
  ///
  /// Call this after the user receives an AI-generated response. The app is
  /// responsible for tracking token counts if calling an LLM directly;
  /// otherwise the backend logs usage internally.
  Future<void> logUsage({
    required String model,
    required String feature,
    required int tokensIn,
    required int tokensOut,
    double? costUsd,
  }) async {
    try {
      await _dio.post<dynamic>('/v1/ai/usage', data: <String, dynamic>{
        'model': model,
        'feature': feature,
        'tokens_in': tokensIn,
        'tokens_out': tokensOut,
        'cost_usd': costUsd,
      });
    } on DioException {
      // Non-fatal — usage log failure does not block the user.
    }
  }
}

final aiChatNotifierProvider =
    NotifierProvider<AiChatNotifier, AiChatState>(AiChatNotifier.new);
