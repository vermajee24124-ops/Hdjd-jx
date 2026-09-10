class AiModel {
  final String id;
  final String name;
  final String? description;
  final int? contextLength;
  final double? pricePer1mTokens;
  final bool supportsReasoning;
  final bool isFree;

  const AiModel({
    required this.id,
    required this.name,
    this.description,
    this.contextLength,
    this.pricePer1mTokens,
    this.supportsReasoning = false,
    this.isFree = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'contextLength': contextLength,
    'pricePer1mTokens': pricePer1mTokens,
    'supportsReasoning': supportsReasoning,
    'isFree': isFree,
  };

  factory AiModel.fromJson(Map<String, dynamic> j) => AiModel(
    id: j['id'] as String,
    name: j['name'] as String? ?? j['id'] as String,
    description: j['description'] as String?,
    contextLength: j['contextLength'] as int?,
    pricePer1mTokens: (j['pricePer1mTokens'] as num?)?.toDouble(),
    supportsReasoning: j['supportsReasoning'] as bool? ?? false,
    isFree: j['isFree'] as bool? ?? false,
  );
}

class AiProvider {
  final String id;
  final String name;
  String baseUrl;
  String apiKey;
  String selectedModel;
  List<AiModel> models;
  bool reasoningEnabled;
  String reasoningLevel;
  int requestsPerMinute;
  int requestsPerDay;
  int tokensPerMinute;

  AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.selectedModel = '',
    List<AiModel>? models,
    this.reasoningEnabled = false,
    this.reasoningLevel = 'medium',
    this.requestsPerMinute = 60,
    this.requestsPerDay = 10000,
    this.tokensPerMinute = 0,
  }) : models = models ?? [];

  bool get isConfigured => apiKey.trim().isNotEmpty;
  bool get isOpenAiCompatible => const {
    'openai', 'openrouter', 'zai', 'tokenroute', 'nararoute', 'omniroute', 'nvidia',
  }.contains(id);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'selectedModel': selectedModel,
    'models': models.map((m) => m.toJson()).toList(),
    'reasoningEnabled': reasoningEnabled,
    'reasoningLevel': reasoningLevel,
    'requestsPerMinute': requestsPerMinute,
    'requestsPerDay': requestsPerDay,
    'tokensPerMinute': tokensPerMinute,
  };

  factory AiProvider.fromJson(Map<String, dynamic> j) => AiProvider(
    id: j['id'] as String,
    name: j['name'] as String,
    baseUrl: j['baseUrl'] as String,
    apiKey: j['apiKey'] as String? ?? '',
    selectedModel: j['selectedModel'] as String? ?? '',
    models: (j['models'] as List?)?.map((m) => AiModel.fromJson(m as Map<String, dynamic>)).toList(),
    reasoningEnabled: j['reasoningEnabled'] as bool? ?? false,
    reasoningLevel: j['reasoningLevel'] as String? ?? 'medium',
    requestsPerMinute: j['requestsPerMinute'] as int? ?? 60,
    requestsPerDay: j['requestsPerDay'] as int? ?? 10000,
    tokensPerMinute: j['tokensPerMinute'] as int? ?? 0,
  );

  static List<AiProvider> catalog() => [
    AiProvider(id: 'anthropic', name: 'Anthropic', baseUrl: 'https://api.anthropic.com/v1/messages', selectedModel: 'claude-sonnet-4-20250514'),
    AiProvider(id: 'openrouter', name: 'OpenRouter', baseUrl: 'https://openrouter.ai/api/v1', selectedModel: ''),
    AiProvider(id: 'openai', name: 'OpenAI', baseUrl: 'https://api.openai.com/v1', selectedModel: ''),
    AiProvider(id: 'gemini', name: 'Google Gemini', baseUrl: 'https://generativelanguage.googleapis.com/v1beta', selectedModel: ''),
    AiProvider(id: 'sarvam', name: 'Sarvam AI', baseUrl: 'https://api.sarvam.ai/v2', selectedModel: 'sarvam-105b'),
    AiProvider(id: 'zai', name: 'Z.ai', baseUrl: 'https://api.z.ai/api/paas/v4', selectedModel: ''),
    AiProvider(id: 'nvidia', name: 'NVIDIA NIM', baseUrl: 'https://integrate.api.nvidia.com/v1', selectedModel: ''),
    AiProvider(id: 'tokenroute', name: 'TokenRoute', baseUrl: '', selectedModel: ''),
    AiProvider(id: 'nararoute', name: 'Nara Route', baseUrl: '', selectedModel: ''),
    AiProvider(id: 'omniroute', name: 'OmniRoute', baseUrl: '', selectedModel: ''),
  ];

  static AiProvider anthropic() => catalog().firstWhere((p) => p.id == 'anthropic');
  static AiProvider openRouter() => catalog().firstWhere((p) => p.id == 'openrouter');
}

class ChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;

  ChatMessage({required this.role, required this.content, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}
