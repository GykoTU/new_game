extends CanvasLayer
## Debug builds only: a live view of every modifier source and what the stat
## blocks resolve to. Nothing in Stage 1 *reads* worker stats yet, so without
## this a purchased upgrade would be invisible. It stays useful for balancing.

var _main: Node
var _label: Label


func _ready() -> void:
	visible = false
	var panel := PanelContainer.new()
	panel.self_modulate = Color(0, 0, 0, 0.75)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Top-right, so it never covers the building bar on the left.
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = 52
	panel.offset_right = -8
	add_child(panel)
	_label = Label.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	_label.add_theme_font_override("font", mono)
	_label.add_theme_font_size_override("font_size", 12)
	panel.add_child(_label)


func bind(main: Node) -> void:
	_main = main
	main.modifiers.changed.connect(_refresh)
	main.economy.changed.connect(func(_k, _a): _refresh())


func toggle() -> void:
	visible = not visible
	_refresh()


func _refresh() -> void:
	if not visible or _main == null:
		return
	var lines := PackedStringArray()
	lines.append("STAT OVERLAY   (%s to close)" % Keybinds.describe_action("debug_stat_overlay"))
	var sources: PackedStringArray = _main.modifiers.sources()
	lines.append("modifier sources (%d): %s" % [sources.size(),
		", ".join(sources) if not sources.is_empty() else "none"])
	lines.append("")
	for type in _main.UNIT_TYPES:
		var def: Dictionary = _main.UNIT_TYPES[type]
		var block: StatBlock = _main.type_blocks[type]
		lines.append("%s  [%s]" % [type, ", ".join(PackedStringArray(def["tags"]))])
		for stat in def["stats"]:
			var value := block.get_value(stat)
			var base := block.get_base(stat)
			var mark := "*" if not is_equal_approx(value, base) else " "
			lines.append("  %s %-16s %9.2f   base %.2f" % [mark, Stats.name_of(stat), value, base])
	lines.append("")
	lines.append("shop prices")
	for item in _main.shop.items():
		var parts := PackedStringArray()
		var price: Dictionary = _main.shop.price(item)
		for kind in price:
			parts.append("%d %s" % [price[kind], ResourceKind.key_of(kind)])
		lines.append("    %-16s x%.2f   %s" % [item.display_name, _main.shop.price_multiplier(item),
			"MAX" if _main.shop.is_maxed(item) else ", ".join(parts)])
	_label.text = "\n".join(lines)
