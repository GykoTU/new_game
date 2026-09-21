extends Node
## Player preferences: audio, video, and key bindings. Not a save file -- these
## survive every run and every new game, and live in user://settings.cfg.

const PATH = "user://settings.cfg"
var volume = 1.0
var fullscreen = false


func _ready():
	var cfg = ConfigFile.new()
	var loaded: bool = cfg.load(PATH) == OK
	if loaded:
		volume = cfg.get_value("audio", "volume", 1.0)
		fullscreen = cfg.get_value("video", "fullscreen", false)
	# Dev actions are removed BEFORE bindings are applied, so a release build
	# never re-creates them from a settings file written by a debug build.
	Keybinds.strip_dev_actions()
	if loaded:
		Keybinds.apply_overrides(cfg)
	apply()


func apply():
	AudioServer.set_bus_volume_db(0, linear_to_db(volume))
	var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func save():
	var cfg = ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	Keybinds.write_overrides(cfg)
	cfg.save(PATH)
