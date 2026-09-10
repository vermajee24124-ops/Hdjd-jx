import 'package:flutter/material.dart';
import '../models/ai_provider.dart';
import '../services/ai_service.dart';
import '../services/settings_service.dart';

class AiFleetScreen extends StatefulWidget {
  const AiFleetScreen({super.key});

  @override
  State<AiFleetScreen> createState() => _AiFleetScreenState();
}

class _AiFleetScreenState extends State<AiFleetScreen> {
  List<AiProvider> _providers = [];
  AiProvider? _selected;
  bool _loading = true;
  bool _discovering = false;
  bool _testing = false;
  String? _status;
  final _keyController = TextEditingController();
  final _urlController = TextEditingController();
  final _rpmController = TextEditingController(text: '60');
  final _rpdController = TextEditingController(text: '10000');
  final _tpmController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _urlController.dispose();
    _rpmController.dispose();
    _rpdController.dispose();
    _tpmController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await Settings.getProviders();
    final byId = {for (final p in saved) p.id: p};
    final merged = AiProvider.catalog().map((p) {
      final s = byId[p.id];
      return s ?? p;
    }).toList();
    if (!mounted) return;
    setState(() {
      _providers = merged;
      _loading = false;
      _select(merged.first);
    });
  }

  void _select(AiProvider provider) {
    _selected = provider;
    _keyController.text = provider.apiKey;
    _urlController.text = provider.baseUrl;
    _rpmController.text = '${provider.requestsPerMinute}';
    _rpdController.text = '${provider.requestsPerDay}';
    _tpmController.text = '${provider.tokensPerMinute}';
    _status = null;
  }

  Future<void> _save({bool makeActive = false}) async {
    final p = _selected;
    if (p == null) return;
    p.apiKey = _keyController.text.trim();
    p.baseUrl = _urlController.text.trim();
    p.requestsPerMinute = int.tryParse(_rpmController.text) ?? 60;
    p.requestsPerDay = int.tryParse(_rpdController.text) ?? 10000;
    p.tokensPerMinute = int.tryParse(_tpmController.text) ?? 0;
    await Settings.updateProvider(p);
    if (makeActive) await Settings.setActiveProvider(p);
    setState(() => _status = makeActive ? 'Saved and selected as active provider.' : 'Saved securely on this device.');
  }

  Future<void> _discover() async {
    final p = _selected;
    if (p == null) return;
    setState(() {
      _discovering = true;
      _status = 'Discovering models from ${p.name}…';
    });
    p.apiKey = _keyController.text.trim();
    p.baseUrl = _urlController.text.trim();
    try {
      final models = await AiService.fetchModels(p);
      if (models.isNotEmpty && !models.any((m) => m.id == p.selectedModel)) {
        p.selectedModel = models.first.id;
      }
      p.models = models;
      await Settings.updateProvider(p);
      if (mounted) setState(() => _status = '${models.length} models discovered.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Discovery failed: $e');
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _test() async {
    final p = _selected;
    if (p == null) return;
    await _save();
    setState(() {
      _testing = true;
      _status = 'Testing ${p.name}…';
    });
    final ok = await AiService.testConnection(p);
    if (mounted) setState(() {
      _testing = false;
      _status = ok ? 'Connection OK. The selected model answered.' : 'Connection test failed. Check key, model and endpoint.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final p = _selected!;
    return Scaffold(
      appBar: AppBar(title: const Text('AI Fleet'), centerTitle: false),
      body: Row(
        children: [
          SizedBox(
            width: 170,
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _providers.length,
              itemBuilder: (_, i) {
                final item = _providers[i];
                final active = identical(item, p);
                return Card(
                  color: active ? Theme.of(context).colorScheme.primaryContainer : null,
                  child: ListTile(
                    dense: true,
                    title: Text(item.name, style: const TextStyle(fontSize: 12)),
                    subtitle: Text(item.models.isEmpty ? 'No models cached' : '${item.models.length} models', style: const TextStyle(fontSize: 10)),
                    onTap: () => setState(() => _select(item)),
                  ),
                );
              },
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 5),
                  Text('Real API connection, model discovery, reasoning and rate limits', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 18),
                  TextField(controller: _keyController, obscureText: true, decoration: const InputDecoration(labelText: 'API key', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: _urlController, decoration: const InputDecoration(labelText: 'API base URL', helperText: 'Used for OpenAI-compatible providers and local/proxy routes.', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: p.selectedModel.isEmpty ? null : p.selectedModel,
                    decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder()),
                    isExpanded: true,
                    items: p.models.map((m) => DropdownMenuItem(value: m.id, child: Text('${m.name}${m.isFree ? ' · FREE' : ''}'))).toList(),
                    onChanged: (v) => setState(() => p.selectedModel = v ?? ''),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: FilledButton.icon(onPressed: _discovering ? null : _discover, icon: const Icon(Icons.refresh), label: Text(_discovering ? 'Discovering…' : 'Discover models'))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(onPressed: _testing ? null : _test, icon: const Icon(Icons.wifi_tethering), label: Text(_testing ? 'Testing…' : 'Test connection'))),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Reasoning / Thinking', style: TextStyle(fontWeight: FontWeight.w700)),
                        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Enable reasoning'), value: p.reasoningEnabled, onChanged: (v) => setState(() => p.reasoningEnabled = v)),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'low', label: Text('Low')),
                            ButtonSegment(value: 'medium', label: Text('Medium')),
                            ButtonSegment(value: 'high', label: Text('High')),
                          ],
                          selected: {p.reasoningLevel},
                          onSelectionChanged: (v) => setState(() => p.reasoningLevel = v.first),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Rate limits', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: TextField(controller: _rpmController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Requests / minute', border: OutlineInputBorder()))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: _rpdController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Requests / day', border: OutlineInputBorder()))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: _tpmController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tokens / minute', border: OutlineInputBorder()))),
                        ]),
                        const SizedBox(height: 5),
                        const Text('Set 0 for unlimited where supported by your account.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: FilledButton.icon(onPressed: () => _save(makeActive: true), icon: const Icon(Icons.check_circle), label: const Text('Save + make active'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save'))),
                  ]),
                  if (_status != null) ...[
                    const SizedBox(height: 14),
                    SelectableText(_status!, style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
