import 'dart:async';
import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/inference/local_inference.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/models/enums.dart';
import '../../../core/utils/bpe_decoder.dart';
import '../data/models/on_device_model.dart';
import 'on_device_providers.dart';

final externalInferenceProvider = Provider<LocalInference>(
  (ref) => OnDeviceExternalInference(ref),
);

/// Adapts the existing loaded engines without entering the in-app chat or
/// conversation stack. The HTTP service holds the shared inference lease.
class OnDeviceExternalInference implements LocalInference {
  OnDeviceExternalInference(this._ref);

  final Ref _ref;

  static const _toolModels = {'gemma4-e2b-instruct', 'gemma4-e4b-instruct'};

  @override
  LocalInferenceModel? get model {
    final engine = _ref.read(onDeviceEngineProvider);
    final id = engine.loadedModelId;
    if (engine.status != OnDeviceEngineStatus.loaded || id == null) return null;
    switch (engine.loadedRuntime) {
      case OnDeviceModelRuntime.llamaCpp:
        final llama = _ref.read(onDeviceLlamaServiceProvider);
        if (llama.isLoaded && llama.currentModelId == id) {
          return LocalInferenceModel(
            id,
            supportsTools: false,
            supportsSampling: true,
          );
        }
      case OnDeviceModelRuntime.gemma:
        final service = _ref.read(onDeviceGemmaServiceProvider);
        final spec = OnDeviceModel.curatedModels
            .where((model) => model.id == id)
            .firstOrNull;
        if (spec != null &&
            !spec.isBuiltIn &&
            service.isLoaded &&
            service.currentModelId == id) {
          return LocalInferenceModel(
            id,
            supportsTools: _toolModels.contains(id),
            supportsSampling: false,
          );
        }
      default:
        break;
    }
    return null;
  }

  @override
  Stream<InferenceEvent> generate(
    InferenceRequest request,
    InferenceCancellation cancellation,
  ) async* {
    final model = this.model;
    if (model == null || model.id != request.model) {
      throw StateError('The requested model is no longer loaded.');
    }
    if (model.supportsSampling) {
      final settings = _ref.read(settingsProvider);
      yield* _ref
          .read(onDeviceLlamaServiceProvider)
          .generateExternal(
            request,
            cancellation,
            defaultTemperature: settings.temperature,
            defaultTopP: settings.topP,
            defaultMaxTokens: settings.maxTokens,
          );
      return;
    }

    final runtime = _ref.read(onDeviceGemmaServiceProvider);
    final system = request.messages
        .where((m) => m.role == InferenceRole.system)
        .map((m) => m.text)
        .join('\n\n');
    final session = await runtime.createChat(
      systemInstruction: system.isEmpty ? null : system,
      supportImage: false,
      tools: [
        for (final tool in request.tools)
          gemma.Tool(
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters,
          ),
      ],
    );
    StreamIterator<gemma.ModelResponse>? iterator;
    final id = model.id.toLowerCase();
    final decoder = id.contains('qwen') || id.contains('deepseek')
        ? BpeDecoder()
        : null;
    try {
      if (cancellation.isCancelled) return;
      await session.addQueryChunk(
        gemma.Message.text(text: _prompt(request.messages), isUser: true),
      );
      if (cancellation.isCancelled) return;
      iterator = StreamIterator(session.generateChatResponseAsync());
      while (await cancellation.moveNext(iterator)) {
        switch (iterator.current) {
          case gemma.TextResponse(:final token):
            final text = decoder?.decodeChunk(token) ?? token;
            if (text.isNotEmpty) yield InferenceText(text);
          case gemma.FunctionCallResponse call:
            yield _call(call, request.tools);
          case gemma.ParallelFunctionCallResponse(:final calls):
            for (final call in calls) {
              yield _call(call, request.tools);
            }
          case gemma.ThinkingResponse():
            break;
        }
      }
      if (cancellation.isCancelled) return;
      final tail = decoder?.flush();
      if (tail != null && tail.isNotEmpty) yield InferenceText(tail);
    } finally {
      try {
        await iterator
            ?.cancel(); // The session wrapper stops and drains native inference.
      } finally {
        await session.close();
      }
    }
  }

  static InferenceCall _call(
    gemma.FunctionCallResponse call,
    List<InferenceTool> tools,
  ) {
    if (!tools.any((tool) => tool.name == call.name)) {
      throw StateError(
        'The model returned a function outside the request schema.',
      );
    }
    return InferenceCall(InferenceToolCall(call.name, jsonEncode(call.args)));
  }

  /// LiteRT's public chat interface does not accept a complete native
  /// conversation as input. Replay prior turns as data in a fresh session,
  /// including tool IDs, names and results, as the in-app adapter does.
  static String _prompt(List<InferenceMessage> messages) {
    final turns = messages
        .where((m) => m.role != InferenceRole.system)
        .toList();
    if (turns.length == 1) return turns.single.text;
    return 'Continue this conversation from the last turn. Use any supplied tool '
        'results to answer the user. The conversation history is JSON:\n'
        '${jsonEncode([
          for (final turn in turns) {
              'role': turn.role.name,
              'content': turn.text,
              if (turn.calls.isNotEmpty) 'tool_calls': [
                  for (final call in turn.calls) {'id': call.id, 'name': call.name, 'arguments': call.arguments},
                ],
              if (turn.toolCallId != null) 'tool_call_id': turn.toolCallId,
            },
        ])}';
  }
}
