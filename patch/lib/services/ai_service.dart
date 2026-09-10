import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_provider.dart';

class _RateState {
  final List<DateTime> requests = <DateTime>[];
  final List<_TokenUse> tokens = <_TokenUse>[];
}

class _TokenUse {
  final DateTime at;
  final int amount;
  _TokenUse(this.at, this.amount);
}

/// Real HTTP integration for the iappyxOS provider layer.
/// Providers using the OpenAI-compatible protocol share one implementation;
/// Anthropic, Gemini and Sarvam use their native endpoints where required.
class AiService {
  static final Map<String, _RateState> _rateStates = <String, _RateState>{};

  static Future<String> generate({
    required AiProvider provider,
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async {
    if (!provider.isConfigured) {
      throw Exception('${provider.name}: API key is not configured.');
    }
    if (provider.selectedModel.trim().isEmpty) {
      throw Exception('${provider.name}: select a model first.');
    }
    await _waitForRateLimit(provider);

    return _withRetry(() async {
      switch (provider.id) {
        case 'anthropic':
          return _callAnthropic(provider, systemPrompt, messages);
        case 'gemini':
          return _callGemini(provider, systemPrompt, messages);
        case 'sarvam':
          return _callSarvam(provider, systemPrompt, messages);
        default:
          return _callOpenAiCompatible(provider, systemPrompt, messages);
      }
    });
  }

  static Future<bool> testConnection(AiProvider provider) async {
    try {
      final models = await fetchModels(provider);
      if (models.isEmpty) return false;
      if (provider.selectedModel.isEmpty) provider.selectedModel = models.first.id;
      final result = await generate(
        provider: provider,
        systemPrompt: 'Respond with exactly: OK',
        messages: [ChatMessage(role: 'user', content: 'Test')],
      );
      return result.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<List<AiModel>> fetchModels(AiProvider provider) async {
    if (provider.apiKey.trim().isEmpty) {
      throw Exception('${provider.name}: API key is required for model discovery.');
    }
    switch (provider.id) {
      case 'anthropic':
        return fetchAnthropicModels(provider.apiKey);
      case 'openrouter':
        return fetchOpenRouterModels(provider.apiKey);
      case 'gemini':
        return _fetchGeminiModels(provider.apiKey);
      case 'sarvam':
        return _fetchSarvamModels(provider.apiKey);
      default:
        return _fetchOpenAiCompatibleModels(provider);
    }
  }

  static Future<List<AiModel>> fetchAnthropicModels(String apiKey) async {
    final response = await http.get(
      Uri.parse('https://api.anthropic.com/v1/models?limit=1000'),
      headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
    ).timeout(const Duration(seconds: 20));
    _throwApiError(response);
    final data = _decode(response);
    final list = (data['data'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => AiModel(
              id: '${m['id']}',
              name: '${m['display_name'] ?? m['id']}',
              contextLength: (m['max_input_tokens'] as num?)?.toInt(),
              supportsReasoning: '${m['id']}'.contains('opus') || '${m['id']}'.contains('sonnet'),
            ))
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  static Future<List<AiModel>> fetchOpenRouterModels(String apiKey) async {
    final response = await http.get(
      Uri.parse('https://openrouter.ai/api/v1/models'),
      headers: apiKey.trim().isEmpty ? {} : {'Authorization': 'Bearer $apiKey'},
    ).timeout(const Duration(seconds: 20));
    _throwApiError(response);
    final data = _decode(response);
    final list = (data['data'] as List? ?? const [])
        .whereType<Map>()
        .map((m) {
      final pricing = m['pricing'] as Map?;
      final prompt = double.tryParse('${pricing?['prompt'] ?? ''}');
      final completion = double.tryParse('${pricing?['completion'] ?? ''}');
      final free = (prompt ?? 1) == 0 && (completion ?? 1) == 0;
      return AiModel(
        id: '${m['id']}',
        name: '${m['name'] ?? m['id']}',
        contextLength: (m['context_length'] as num?)?.toInt(),
        pricePer1mTokens: prompt == null ? null : prompt * 1000000,
        isFree: free,
        supportsReasoning: '${m['id']}'.contains('thinking') || '${m['id']}'.contains('reason'),
      );
    }).toList();
    list.sort((a, b) {
      if (a.isFree != b.isFree) return a.isFree ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  static Future<List<AiModel>> _fetchGeminiModels(String apiKey) async {
    final response = await http.get(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000'),
      headers: {'x-goog-api-key': apiKey},
    ).timeout(const Duration(seconds: 20));
    _throwApiError(response);
    final data = _decode(response);
    final list = (data['models'] as List? ?? const [])
        .whereType<Map>()
        .where((m) => ((m['supportedGenerationMethods'] as List?) ?? const []).contains('generateContent'))
        .map((m) => AiModel(
              id: '${m['name']}'.replaceFirst('models/', ''),
              name: '${m['displayName'] ?? m['name']}',
              description: m['description'] as String?,
              contextLength: (m['inputTokenLimit'] as num?)?.toInt(),
              supportsReasoning: '${m['name']}'.toLowerCase().contains('thinking') || '${m['name']}'.toLowerCase().contains('pro'),
            ))
        .toList();
    return list;
  }

  static Future<List<AiModel>> _fetchSarvamModels(String apiKey) async {
    final response = await http.get(
      Uri.parse('https://api.sarvam.ai/v2/models'),
      headers: {'api-subscription-key': apiKey},
    ).timeout(const Duration(seconds: 20));
    _throwApiError(response);
    final data = _decode(response);
    return (data['data'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => AiModel(
              id: '${m['id']}',
              name: '${m['id']}',
              supportsReasoning: '${m['id']}'.toLowerCase().contains('glm') || '${m['id']}'.toLowerCase().contains('deepseek') || '${m['id']}'.toLowerCase().contains('105b'),
            ))
        .toList();
  }

  static Future<List<AiModel>> _fetchOpenAiCompatibleModels(AiProvider provider) async {
    final base = _normaliseBase(provider.baseUrl);
    if (base.isEmpty) throw Exception('${provider.name}: set an API base URL before model discovery.');
    final response = await http.get(
      Uri.parse('$base/models'),
      headers: {'Authorization': 'Bearer ${provider.apiKey}'},
    ).timeout(const Duration(seconds: 20));
    _throwApiError(response);
    final data = _decode(response);
    final raw = data['data'] as List? ?? const [];
    final list = raw.whereType<Map>().map((m) => AiModel(
          id: '${m['id']}',
          name: '${m['name'] ?? m['id']}',
          contextLength: (m['context_length'] as num?)?.toInt(),
          supportsReasoning: '${m['id']}'.toLowerCase().contains('reason') || '${m['id']}'.toLowerCase().contains('thinking') || '${m['id']}'.toLowerCase().contains('glm') || '${m['id']}'.toLowerCase().contains('deepseek'),
        )).toList();
    return list;
  }

  static Future<String> _callOpenAiCompatible(
    AiProvider provider,
    String systemPrompt,
    List<ChatMessage> messages,
  ) async {
    final endpoint = _chatEndpoint(provider.baseUrl);
    final allMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...messages.map((m) => {'role': m.role, 'content': m.content}),
    ];

    final body = <String, dynamic>{
      'model': provider.selectedModel,
      'messages': allMessages,
      'max_tokens': 16000,
    };
    if (provider.reasoningEnabled) {
      body['reasoning_effort'] = provider.reasoningLevel;
      body['reasoning'] = {'effort': provider.reasoningLevel};
    }

    final response = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${provider.apiKey}'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 300));
    _throwApiError(response);
    final data = _decode(response);
    final choice = (data['choices'] as List?)?.isNotEmpty == true ? data['choices'][0] : null;
    if (choice is! Map) throw Exception('${provider.name}: empty response.');
    final msg = choice['message'];
    if (msg is Map && msg['content'] != null) return '${msg['content']}';
    if (choice['text'] != null) return '${choice['text']}';
    throw Exception('${provider.name}: response contained no text.');
  }

  static Future<String> _callSarvam(AiProvider provider, String systemPrompt, List<ChatMessage> messages) async {
    final endpoint = 'https://api.sarvam.ai/v2/chat/completions';
    final allMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...messages.map((m) => {'role': m.role, 'content': m.content}),
    ];
    final body = <String, dynamic>{
      'model': provider.selectedModel,
      'messages': allMessages,
      'max_tokens': 16000,
    };
    if (provider.reasoningEnabled) body['reasoning_effort'] = provider.reasoningLevel;
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json', 'api-subscription-key': provider.apiKey},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 300));
    _throwApiError(response);
    final data = _decode(response);
    final choice = (data['choices'] as List?)?.isNotEmpty == true ? data['choices'][0] : null;
    final msg = choice is Map ? choice['message'] : null;
    return msg is Map && msg['content'] != null ? '${msg['content']}' : '${choice?['text'] ?? ''}';
  }

  static Future<String> _callGemini(AiProvider provider, String systemPrompt, List<ChatMessage> messages) async {
    final model = provider.selectedModel.replaceFirst('models/', '');
    final endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';
    final contents = messages.map((m) => {
      'role': m.role == 'assistant' ? 'model' : 'user',
      'parts': [{'text': m.content}],
    }).toList();
    final body = <String, dynamic>{
      'systemInstruction': {'parts': [{'text': systemPrompt}]},
      'contents': contents,
      'generationConfig': {'maxOutputTokens': 16000},
    };
    if (provider.reasoningEnabled) {
      body['generationConfig']['thinkingConfig'] = {
        'thinkingBudget': provider.reasoningLevel == 'low' ? 1024 : (provider.reasoningLevel == 'high' ? 8192 : 4096),
      };
    }
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': provider.apiKey},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 300));
    _throwApiError(response);
    final data = _decode(response);
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) throw Exception('Gemini: empty response.');
    final parts = ((candidates.first as Map)['content'] as Map?)?['parts'] as List? ?? const [];
    final text = parts.whereType<Map>().map((p) => p['text']).whereType<String>().join();
    if (text.isEmpty) throw Exception('Gemini: response contained no text.');
    return text;
  }

  static Future<String> _callAnthropic(AiProvider provider, String systemPrompt, List<ChatMessage> messages) async {
    final body = <String, dynamic>{
      'model': provider.selectedModel,
      'max_tokens': provider.reasoningEnabled ? 20000 : 16000,
      'system': systemPrompt,
      'messages': messages.map((m) => {'role': m.role, 'content': m.content}).toList(),
    };
    if (provider.reasoningEnabled) {
      body['thinking'] = {
        'type': 'enabled',
        'budget_tokens': provider.reasoningLevel == 'low' ? 2048 : (provider.reasoningLevel == 'high' ? 12000 : 6000),
      };
    }
    final response = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': provider.apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 300));
    _throwApiError(response);
    final data = _decode(response);
    final content = data['content'] as List?;
    if (content == null || content.isEmpty) throw Exception('Anthropic: empty response.');
    final text = content.whereType<Map>().map((b) => b['text']).whereType<String>().join();
    if (text.isEmpty) throw Exception('Anthropic: response contained no text.');
    return text;
  }

  static Future<void> _waitForRateLimit(AiProvider provider) async {
    final rpm = provider.requestsPerMinute;
    if (rpm <= 0 && provider.tokensPerMinute <= 0) return;
    final state = _rateStates.putIfAbsent(provider.id, () => _RateState());
    while (true) {
      final now = DateTime.now();
      state.requests.removeWhere((t) => now.difference(t).inMinutes >= 1);
      state.tokens.removeWhere((t) => now.difference(t.at).inMinutes >= 1);
      final requestBlocked = rpm > 0 && state.requests.length >= rpm;
      final tokenBlocked = provider.tokensPerMinute > 0 && state.tokens.fold<int>(0, (s, t) => s + t.amount) >= provider.tokensPerMinute;
      if (!requestBlocked && !tokenBlocked) {
        state.requests.add(now);
        return;
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  static Future<String> _withRetry(Future<String> Function() call, {int maxRetries = 2}) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await call();
      } on SocketException catch (e) {
        if (attempt == maxRetries) rethrow;
        debugPrint('[AI] connection error, retrying: $e');
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      } on HttpException catch (e) {
        if (attempt == maxRetries) rethrow;
        debugPrint('[AI] http error, retrying: $e');
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw Exception('Request failed.');
  }

  static String _normaliseBase(String value) {
    var v = value.trim();
    while (v.endsWith('/')) v = v.substring(0, v.length - 1);
    if (v.endsWith('/v1')) return v;
    return v;
  }

  static String _chatEndpoint(String base) {
    final b = _normaliseBase(base);
    return b.endsWith('/chat/completions') ? b : '$b/chat/completions';
  }

  static Map<String, dynamic> _decode(http.Response response) => jsonDecode(response.body) as Map<String, dynamic>;

  static void _throwApiError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message = 'HTTP ${response.statusCode}';
    try {
      final data = jsonDecode(response.body);
      if (data is Map) message = '${data['error']?['message'] ?? data['message'] ?? message}';
    } catch (_) {}
    throw HttpException(message, uri: response.request?.url);
  }
}
