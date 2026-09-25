class_name Keybinds
extends RefCounted
## Every input action the player can see, and rebinding them.
##
## The defaults live in project.godot's input map, where the editor can edit
## them. Rebinding changes the live InputMap, and only the actions the player
## actually changed are saved, to settings.cfg via Settings. So when a later
## build changes a default, players who never touched that binding get it.
##
## Dev-only actions are hidden from the list AND erased from the InputMap at
## startup in release builds, so a player cannot trigger them even by editing
## settings.cfg -- a saved binding for an action that does not exist is ignored.
## Debug handlers also check OS.is_debug_build() themselves. Note that exports
## made with Godot's *debug* template count as debug builds; only a release
## export hides the dev tools.

enum Category { CAMERA, GAME, MENUS, DEBUG }
const CATEGORY_NAMES := ["Camera", "Game", "Menus", "Debug"]

## action, label, category, rebindable, dev_only.
## To add a shortcut: add the action to the input map, then add a row here.
const ACTIONS := [
	["move_camera",           "Pan camera (hold)", Category.CAMERA, true,  false],
	["zoom_in",               "Zoom in",           Category.CAMERA, true,  false],
	["zoom_out",              "Zoom out",          Category.CAMERA, true,  false],
	["left_click",            "Select / place",    Category.GAME,   true,  false],
	["cancel_placement",      "Cancel placement",  Category.GAME,   true,  false],
	["expand_building_bar",   "Expand building bar (hold, over the bar)", Category.GAME, true, false],
	["game_pause",            "Pause",             Category.GAME,   true,  false],
	["game_speed_1",          "Speed 1x",          Category.GAME,   true,  false],
	["game_speed_2",          "Speed 2x",          Category.GAME,   true,  false],
	["game_speed_3",          "Speed 4x",          Category.GAME,   true,  false],
	["shop",                  "Open shop",         Category.MENUS,  true,  false],
	# Not rebindable: a player who rebinds the menu key can lock themselves out
	# of the menu that would let them fix it.
	["ui_cancel",             "Options menu",      Category.MENUS,  false, false],
	["debug_new_level",       "New level",         Category.DEBUG,  true,  true],
	["debug_grant_resources", "Grant resources",   Category.DEBUG,  true,  true],
	["debug_stat_overlay",    "Stat overlay",      Category.DEBUG,  true,  true],
	["debug_skip_phase",      "Skip to dusk / dawn", Category.DEBUG, true, true],
	["debug_reveal_map",      "Reveal the whole map", Category.DEBUG, true, true],
	["debug_kill_base",       "Destroy the base (ends the run)", Category.DEBUG, true, true],
]

const _MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Left Mouse", MOUSE_BUTTON_RIGHT: "Right Mouse",
	MOUSE_BUTTON_MIDDLE: "Middle Mouse", MOUSE_BUTTON_WHEEL_UP: "Wheel Up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down", MOUSE_BUTTON_WHEEL_LEFT: "Wheel Left",
	MOUSE_BUTTON_WHEEL_RIGHT: "Wheel Right",
}

## Actions the player changed this session or in a previous one.
static var _overridden := {}

## Tests only: behave as a release build would. A debug test run cannot BE a
## release build, and the release gating is exactly what needs proving.
static var simulate_release := false


static func dev_tools_enabled() -> bool:
	return OS.is_debug_build() and not simulate_release


## Rows to show in the controls list: dev actions only in debug builds, and
## only actions that actually exist.
static func visible_rows() -> Array:
	var out := []
	for row in ACTIONS:
		if row[4] and not dev_tools_enabled():
			continue
		if InputMap.has_action(row[0]):
			out.append(row)
	return out


static func is_rebindable(action: String) -> bool:
	for row in ACTIONS:
		if row[0] == action:
			return row[3] and (not row[4] or dev_tools_enabled())
	return false


## Called once at startup, before anything reads input.
static func strip_dev_actions() -> void:
	if dev_tools_enabled():
		return
	for row in ACTIONS:
		if row[4] and InputMap.has_action(row[0]):
			InputMap.erase_action(row[0])


## Keyboard and mouse bindings of an action. Joypad events are left alone and
## not shown; there is no gamepad support yet.
static func bindings(action: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			out.append(e)
	return out


static func describe(event: InputEvent) -> String:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.as_text_physical_keycode() if k.physical_keycode != 0 else k.as_text_keycode()
	if event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		var name: String = _MOUSE_NAMES.get(m.button_index, "Mouse %d" % m.button_index)
		var mods := ""
		if m.ctrl_pressed: mods += "Ctrl+"
		if m.shift_pressed: mods += "Shift+"
		if m.alt_pressed: mods += "Alt+"
		return mods + name
	return "?"


static func describe_action(action: String) -> String:
	var parts := PackedStringArray()
	for e in bindings(action):
		parts.append(describe(e))
	return " / ".join(parts) if not parts.is_empty() else "Unbound"


## Turns a raw input event into a clean binding, or null if it should not be
## one: releases, key repeats, and a modifier pressed on its own (so Ctrl+G can
## be captured without Ctrl alone being taken first).
static func binding_from(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return null
		if k.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
			return null
		var out := InputEventKey.new()
		out.physical_keycode = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		out.ctrl_pressed = k.ctrl_pressed
		out.shift_pressed = k.shift_pressed
		out.alt_pressed = k.alt_pressed
		out.meta_pressed = k.meta_pressed
		return out
	if event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if not m.pressed:
			return null
		var out := InputEventMouseButton.new()
		out.button_index = m.button_index
		out.ctrl_pressed = m.ctrl_pressed
		out.shift_pressed = m.shift_pressed
		out.alt_pressed = m.alt_pressed
		return out
	return null


## Binds `event` to `action`, replacing its bindings.
## Returns {"ok": bool, "taken_from": String, "reason": String}.
## If another action held the same input, it loses it -- never silently gets a
## different key instead -- and the UI shows it red if it is left with none.
## An input held by a non-rebindable action cannot be taken at all.
static func rebind(action: String, event: InputEvent) -> Dictionary:
	var result := {"ok": false, "taken_from": "", "reason": ""}
	if not is_rebindable(action):
		result["reason"] = "This action cannot be rebound."
		return result
	for row in visible_rows():
		var other: String = row[0]
		if other == action:
			continue
		for e in InputMap.action_get_events(other):
			if same_input(e, event) and not row[3]:
				result["reason"] = "%s is reserved for %s." % [describe(event), row[1]]
				return result
	for row in visible_rows():
		var other: String = row[0]
		if other == action:
			continue
		for e in InputMap.action_get_events(other):
			if same_input(e, event):
				InputMap.action_erase_event(other, e)
				_overridden[other] = true
				result["taken_from"] = other
	for e in bindings(action):
		InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, event)
	_overridden[action] = true
	result["ok"] = true
	return result


## True if two bindings are the same physical input with the same modifiers.
##
## Not InputEvent.is_match: Godot's built-in ui_* actions define keys by
## keycode, while this project's actions use physical keycodes, and is_match
## treats those as different keys. That let Escape be taken from the menu.
static func same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		return _key_label(ka) == _key_label(kb) and _mods(ka) == _mods(kb)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		var ma := a as InputEventMouseButton
		var mb := b as InputEventMouseButton
		return ma.button_index == mb.button_index and _mods(ma) == _mods(mb)
	return false


## A key's identity regardless of whether it was defined by keycode or by
## physical keycode, resolved through the current keyboard layout.
static func _key_label(k: InputEventKey) -> int:
	if k.keycode != 0:
		return k.keycode
	return DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)


static func _mods(e: InputEventWithModifiers) -> int:
	return int(e.ctrl_pressed) | int(e.shift_pressed) << 1 | int(e.alt_pressed) << 2 \
		| int(e.meta_pressed) << 3


static func label_of(action: String) -> String:
	for row in ACTIONS:
		if row[0] == action:
			return row[1]
	return action


## Restores every rebindable action to its project.godot default.
static func reset_all() -> void:
	for row in ACTIONS:
		if row[3] and InputMap.has_action(row[0]):
			_restore_default(row[0])
	_overridden.clear()


static func _restore_default(action: String) -> void:
	for e in bindings(action):
		InputMap.action_erase_event(action, e)
	var setting = ProjectSettings.get_setting("input/" + action)
	if setting is Dictionary and setting.has("events"):
		for e in setting["events"]:
			if e is InputEventKey or e is InputEventMouseButton:
				InputMap.action_add_event(action, e)


# --- Persistence (through Settings / settings.cfg) ----------------------------

## Writes only overridden actions. An action left with no binding is saved as an
## empty list, so "deliberately unbound" survives a restart.
static func write_overrides(cfg: ConfigFile) -> void:
	for action in _overridden:
		if not InputMap.has_action(action):
			continue
		var list := []
		for e in bindings(action):
			list.append(_serialize(e))
		cfg.set_value("input", action, list)


static func apply_overrides(cfg: ConfigFile) -> void:
	if not cfg.has_section("input"):
		return
	for action in cfg.get_section_keys("input"):
		# Unknown, reserved or (in release) stripped dev actions are ignored.
		if not is_rebindable(action) or not InputMap.has_action(action):
			continue
		for e in bindings(action):
			InputMap.action_erase_event(action, e)
		for d in cfg.get_value("input", action, []):
			var e := _deserialize(d)
			if e != null:
				InputMap.action_add_event(action, e)
		_overridden[action] = true


static func _serialize(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		var k := e as InputEventKey
		return {"type": "key", "physical": k.physical_keycode if k.physical_keycode != 0 else k.keycode,
			"ctrl": k.ctrl_pressed, "shift": k.shift_pressed, "alt": k.alt_pressed, "meta": k.meta_pressed}
	var m := e as InputEventMouseButton
	return {"type": "mouse", "button": m.button_index,
		"ctrl": m.ctrl_pressed, "shift": m.shift_pressed, "alt": m.alt_pressed}


static func _deserialize(d) -> InputEvent:
	if not d is Dictionary:
		return null
	match d.get("type", ""):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("physical", 0)) as Key
			k.ctrl_pressed = d.get("ctrl", false)
			k.shift_pressed = d.get("shift", false)
			k.alt_pressed = d.get("alt", false)
			k.meta_pressed = d.get("meta", false)
			return k if k.physical_keycode != 0 else null
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.get("button", 0)) as MouseButton
			m.ctrl_pressed = d.get("ctrl", false)
			m.shift_pressed = d.get("shift", false)
			m.alt_pressed = d.get("alt", false)
			return m if m.button_index != 0 else null
	return null
