extends Control

const CONFIG_PATH := "user://ai_power_game_factory.cfg"

var providers := [
	{"id":"anthropic","name":"Anthropic","base":"https://api.anthropic.com/v1/messages","model":"claude-sonnet-4-20250514","kind":"anthropic"},
	{"id":"openrouter","name":"OpenRouter","base":"https://openrouter.ai/api/v1","model":"","kind":"openai"},
	{"id":"openai","name":"OpenAI","base":"https://api.openai.com/v1","model":"","kind":"openai"},
	{"id":"gemini","name":"Google Gemini","base":"https://generativelanguage.googleapis.com/v1beta","model":"","kind":"gemini"},
	{"id":"sarvam","name":"Sarvam AI","base":"https://api.sarvam.ai/v2","model":"sarvam-105b","kind":"sarvam"},
	{"id":"zai","name":"Z.ai","base":"https://api.z.ai/api/paas/v4","model":"","kind":"openai"},
	{"id":"nvidia","name":"NVIDIA NIM","base":"https://integrate.api.nvidia.com/v1","model":"","kind":"openai"},
	{"id":"tokenroute","name":"TokenRoute","base":"","model":"","kind":"openai"},
	{"id":"nararoute","name":"Nara Route","base":"","model":"","kind":"openai"},
	{"id":"omniroute","name":"OmniRoute","base":"","model":"","kind":"openai"}
]

var selected_index := 0
var key_edit: LineEdit
var base_edit: LineEdit
var model_edit: LineEdit
var rpm_spin: SpinBox
var reason_check: CheckBox
var reason_level: OptionButton
var status_label: Label
var models_list: ItemList
var mcp_url: LineEdit
var mcp_key: LineEdit
var mcp_status: Label
var mcp_tools: ItemList
var request: HTTPRequest
var mcp_request: HTTPRequest
var config := {}

func _ready() -> void:
	_load_config()
	_build_ui()
	_select_provider(0)

func _style_panel(node: Control) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("161a26")
	sb.border_color = Color("2a3145")
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	node.add_theme_stylebox_override("panel", sb)

func _label(text: String, size := 17) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 16)
	return b

func _line(placeholder: String, secret := false) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 48)
	e.add_theme_font_size_override("font_size", 16)
	if secret:
		e.secret = true
	return e

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("090c14")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_right = -16
	add_child(scroll)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(0, 1900)
	root.add_theme_constant_override("separation", 12)
	scroll.add_child(root)

	var title := _label("AI Power Game Factory", 29)
	title.add_theme_color_override("font_color", Color("e8ecff"))
	root.add_child(title)
	var subtitle := _label("Godot 4.7.2 • AI providers • model discovery • MCP")
	subtitle.add_theme_color_override("font_color", Color("9aa3bc"))
	root.add_child(subtitle)

	var provider_panel := PanelContainer.new()
	_style_panel(provider_panel)
	root.add_child(provider_panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	provider_panel.add_child(pv)
	pv.add_child(_label("AI Provider", 20))
	var providers_box := HBoxContainer.new()
	var provider_menu := OptionButton.new()
	provider_menu.name = "ProviderMenu"
	for p in providers:
		provider_menu.add_item(p.name)
	provider_menu.add_theme_font_size_override("font_size", 16)
	provider_menu.custom_minimum_size = Vector2(0, 50)
	provider_menu.item_selected.connect(_select_provider)
	providers_box.add_child(provider_menu)
	pv.add_child(providers_box)

	pv.add_child(_label("API Key"))
	key_edit = _line("Enter provider API key", true)
	pv.add_child(key_edit)
	pv.add_child(_label("Base URL / Endpoint"))
	base_edit = _line("Provider base URL")
	pv.add_child(base_edit)
	pv.add_child(_label("Selected Model"))
	model_edit = _line("Model ID, or discover models")
	pv.add_child(model_edit)

	var actions := HBoxContainer.new()
	var discover := _button("Discover Models")
	discover.pressed.connect(_discover_models)
	var test := _button("Test Connection")
	test.pressed.connect(_test_connection)
	var save := _button("Save Settings")
	save.pressed.connect(_save_current)
	actions.add_child(discover)
	actions.add_child(test)
	actions.add_child(save)
	pv.add_child(actions)

	models_list = ItemList.new()
	models_list.custom_minimum_size = Vector2(0, 210)
	models_list.add_theme_font_size_override("font_size", 15)
	models_list.item_clicked.connect(_model_clicked)
	pv.add_child(models_list)
	status_label = _label("Ready", 14)
	status_label.add_theme_color_override("font_color", Color("9aa3bc"))
	pv.add_child(status_label)

	var reasoning_panel := PanelContainer.new()
	_style_panel(reasoning_panel)
	root.add_child(reasoning_panel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	reasoning_panel.add_child(rv)
	rv.add_child(_label("Reasoning / Thinking", 20))
	reason_check = CheckBox.new()
	reason_check.text = "Enable extended reasoning when provider/model supports it"
	reason_check.add_theme_font_size_override("font_size", 16)
	rv.add_child(reason_check)
	var rl := HBoxContainer.new()
	rl.add_child(_label("Reasoning level"))
	reason_level = OptionButton.new()
	for x in ["low","medium","high"]:
		reason_level.add_item(x)
	rl.add_child(reason_level)
	rv.add_child(rl)
	var limits := HBoxContainer.new()
	limits.add_child(_label("Requests/min"))
	rpm_spin = SpinBox.new()
	rpm_spin.min_value = 1
	rpm_spin.max_value = 10000
	rpm_spin.value = 60
	rpm_spin.step = 1
	rpm_spin.custom_minimum_size = Vector2(130, 48)
	limits.add_child(rpm_spin)
	limits.add_spacer(false)
	limits.add_child(_label("Configurable per provider"))
	rv.add_child(limits)

	var mcp_panel := PanelContainer.new()
	_style_panel(mcp_panel)
	root.add_child(mcp_panel)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	mcp_panel.add_child(mv)
	mv.add_child(_label("MCP / Agent Tools", 20))
	mv.add_child(_label("Connect this app to an MCP server and inspect its tools."))
	mcp_url = _line("MCP server URL, e.g. https://host/mcp")
	mv.add_child(mcp_url)
	mcp_key = _line("Optional MCP authorization token", true)
	mv.add_child(mcp_key)
	var mcp_buttons := HBoxContainer.new()
	var mcp_connect := _button("Connect MCP")
	mcp_connect.pressed.connect(_connect_mcp)
	var mcp_refresh := _button("Refresh Tools")
	mcp_refresh.pressed.connect(_list_mcp_tools)
	mcp_buttons.add_child(mcp_connect)
	mcp_buttons.add_child(mcp_refresh)
	mv.add_child(mcp_buttons)
	mcp_status = _label("MCP not connected", 14)
	mcp_status.add_theme_color_override("font_color", Color("9aa3bc"))
	mv.add_child(mcp_status)
	mcp_tools = ItemList.new()
	mcp_tools.custom_minimum_size = Vector2(0, 250)
	mcp_tools.add_theme_font_size_override("font_size", 15)
	mv.add_child(mcp_tools)

	var note := _label("API keys stay on the device in the app config. Do not commit keys to GitHub.", 13)
	note.add_theme_color_override("font_color", Color("77819b"))
	root.add_child(note)

	request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_request_completed)
	mcp_request = HTTPRequest.new()
	add_child(mcp_request)
	mcp_request.request_completed.connect(_on_mcp_completed)

func _select_provider(index: int) -> void:
	selected_index = index
	var p = providers[index]
	var saved = config.get(p.id, {})
	key_edit.text = saved.get("api_key", "")
	base_edit.text = saved.get("base_url", p.base)
	model_edit.text = saved.get("model", p.model)
	reason_check.button_pressed = saved.get("reasoning", false)
	reason_level.select(max(0, ["low","medium","high"].find(saved.get("reasoning_level", "medium"))))
	rpm_spin.value = saved.get("rpm", 60)
	models_list.clear()
	status_label.text = p.name + " selected"

func _save_current() -> void:
	var p = providers[selected_index]
	config[p.id] = {
		"api_key": key_edit.text.strip_edges(),
		"base_url": base_edit.text.strip_edges(),
		"model": model_edit.text.strip_edges(),
		"reasoning": reason_check.button_pressed,
		"reasoning_level": reason_level.get_item_text(reason_level.selected),
		"rpm": int(rpm_spin.value)
	}
	_save_config()
	status_label.text = "Settings saved for " + p.name

func _save_config() -> void:
	var f := ConfigFile.new()
	for id in config.keys():
		var d = config[id]
		for k in d.keys():
			f.set_value("providers", id + "." + k, d[k])
	f.set_value("mcp", "url", mcp_url.text if mcp_url else "")
	f.set_value("mcp", "key", mcp_key.text if mcp_key else "")
	f.save(CONFIG_PATH)

func _load_config() -> void:
	var f := ConfigFile.new()
	if f.load(CONFIG_PATH) != OK:
		return
	for p in providers:
		var d := {}
		for k in ["api_key","base_url","model","reasoning","reasoning_level","rpm"]:
			var v = f.get_value("providers", p.id + "." + k, null)
			if v != null:
				d[k] = v
		config[p.id] = d
	var mcp_d := {}
	mcp_d.url = f.get_value("mcp", "url", "")
	mcp_d.key = f.get_value("mcp", "key", "")
	config["_mcp"] = mcp_d

func _headers(key: String, kind: String) -> PackedStringArray:
	var h := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if kind == "gemini":
		h.append("x-goog-api-key: " + key)
	elif kind == "sarvam":
		h.append("api-subscription-key: " + key)
	else:
		h.append("Authorization: Bearer " + key)
	return h

func _discover_models() -> void:
	_save_current()
	var p = providers[selected_index]
	var key := key_edit.text.strip_edges()
	var base := base_edit.text.strip_edges().trim_suffix("/")
	if key.is_empty() or base.is_empty():
		status_label.text = "API key and base URL are required"
		return
	models_list.clear()
	status_label.text = "Discovering models..."
	if p.kind == "gemini":
		request.request(base + "/models", _headers(key, p.kind), HTTPClient.METHOD_GET)
	elif p.kind == "sarvam":
		request.request(base + "/models", _headers(key, p.kind), HTTPClient.METHOD_GET)
	else:
		request.request(base + "/models", _headers(key, p.kind), HTTPClient.METHOD_GET)

func _test_connection() -> void:
	status_label.text = "Testing..."
	_discover_models()

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code < 200 or response_code >= 300:
		status_label.text = "Request failed: HTTP " + str(response_code)
		return
	var text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		status_label.text = "Provider returned invalid JSON"
		return
	models_list.clear()
	var items: Array = []
	if parsed is Dictionary and parsed.has("data") and parsed.data is Array:
		items = parsed.data
	elif parsed is Dictionary and parsed.has("models") and parsed.models is Array:
		items = parsed.models
	for item in items:
		if item is Dictionary:
			var id = str(item.get("id", item.get("name", "")))
			if not id.is_empty():
				models_list.add_item(id)
	if items.is_empty():
		status_label.text = "Connected, but no model list was returned"
	else:
		status_label.text = str(items.size()) + " model(s) discovered"

func _model_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		model_edit.text = models_list.get_item_text(index)
		_save_current()

func _connect_mcp() -> void:
	var url := mcp_url.text.strip_edges()
	if url.is_empty():
		mcp_status.text = "Enter an MCP URL first"
		return
	mcp_status.text = "Connecting to MCP..."
	var hs := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if not mcp_key.text.strip_edges().is_empty():
		hs.append("Authorization: Bearer " + mcp_key.text.strip_edges())
	var init_id := 1
	var payload := {"jsonrpc":"2.0","id":init_id,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"AI Power Game Factory","version":"1.0.0"}}}
	mcp_request.set_meta("op", "initialize")
	mcp_request.request(url, hs, HTTPClient.METHOD_POST, JSON.stringify(payload))

func _list_mcp_tools() -> void:
	var url := mcp_url.text.strip_edges()
	if url.is_empty():
		mcp_status.text = "Enter an MCP URL first"
		return
	var hs := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if not mcp_key.text.strip_edges().is_empty():
		hs.append("Authorization: Bearer " + mcp_key.text.strip_edges())
	var payload := {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
	mcp_request.set_meta("op", "tools/list")
	mcp_request.request(url, hs, HTTPClient.METHOD_POST, JSON.stringify(payload))

func _on_mcp_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code < 200 or response_code >= 300:
		mcp_status.text = "MCP HTTP error: " + str(response_code)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null:
		mcp_status.text = "MCP returned invalid JSON"
		return
	var op = mcp_request.get_meta("op", "")
	if op == "initialize":
		mcp_status.text = "MCP initialized"
		_list_mcp_tools()
		return
	mcp_tools.clear()
	var result_obj = parsed.get("result", {}) if parsed is Dictionary else {}
	var tools = result_obj.get("tools", []) if result_obj is Dictionary else []
	for t in tools:
		if t is Dictionary:
			var name := str(t.get("name", "unnamed_tool"))
			var desc := str(t.get("description", ""))
			mcp_tools.add_item(name + (" — " + desc if not desc.is_empty() else ""))
	mcp_status.text = str(tools.size()) + " MCP tool(s) available"
