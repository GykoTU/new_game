extends Node

const SAVE_PATH = "user://savegame.dat"
var data = {}

func reset() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var err := DirAccess.remove_absolute(SAVE_PATH)
		if err != OK:
			push_error("Couldn't delete save: " + error_string(err))
			return
	
func has_save() -> bool:
	var save := load_game()
	return not save.is_empty()

func save_game(level) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Couldn't save: " + error_string(FileAccess.get_open_error()))
		return
	file.store_var({
		"level": level.get_save_data(),
		# Add other save data here later: resources, workers, player base...
	})

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	data = file.get_var()
	return data if data is Dictionary else {}
