from pathlib import Path

root = Path(__file__).resolve().parents[1]
work = root / 'build_source'
patch = root / 'patch'

# Copy our patched source files into the cloned upstream Flutter project.
for rel in [
    'lib/models/ai_provider.dart',
    'lib/services/ai_service.dart',
    'lib/screens/ai_fleet_screen.dart',
]:
    src = patch / rel
    dst = work / 'src' / 'container_app' / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(src.read_text(encoding='utf-8'), encoding='utf-8')

settings = work / 'src' / 'container_app' / 'lib' / 'screens' / 'settings_screen.dart'
s = settings.read_text(encoding='utf-8')

if "import 'ai_fleet_screen.dart';" not in s:
    s = s.replace("import 'create_screen.dart' show ProviderSetupPage;", "import 'create_screen.dart' show ProviderSetupPage;\nimport 'ai_fleet_screen.dart';")

marker = "              // App ID Prefix"
card = """              // AI Fleet\n              _sectionTitle('AI Fleet'),\n              _card(children: [\n                _actionRow('Open multi-provider AI settings', Icons.hub, () async {\n                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const AiFleetScreen()));\n                  _load();\n                }),\n              ]),\n\n              const SizedBox(height: 24),\n\n"""
if "Open multi-provider AI settings" not in s:
    s = s.replace(marker, card + marker, 1)
settings.write_text(s, encoding='utf-8')

create = work / 'src' / 'container_app' / 'lib' / 'screens' / 'create_screen.dart'
c = create.read_text(encoding='utf-8')
old = """      if (_provider.id == 'anthropic') {\n        _models = await AiService.fetchAnthropicModels(apiKey);\n      } else if (_provider.id == 'openrouter') {\n        _models = await AiService.fetchOpenRouterModels(apiKey);\n      }\n"""
new = """      _provider.apiKey = apiKey;\n      _models = await AiService.fetchModels(_provider);\n"""
if old in c:
    c = c.replace(old, new, 1)
else:
    print('create_screen model-discovery block not found; existing source may already differ')
create.write_text(c, encoding='utf-8')

print('Patch applied successfully')
