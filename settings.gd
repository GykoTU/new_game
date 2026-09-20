extends Node

const PATH = "user://settings.cfg"
var volume = 1.0
var fullscreen = false

func _ready():
	var cfg = ConfigFile.new()
	if cfg.load(PATH) == OK:
		volume = cfg.get_value("audio", "volume", 1.0)
		fullscreen = cfg.get_value("video", "fullscreen", false)
	apply()

func apply():
	AudioServer.set_bus_volume_db(0, linear_to_db(volume))
	var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

func save():
	var cfg = ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(PATH)
