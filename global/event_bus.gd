extends Node

@warning_ignore_start("unused_signal")
signal player_died
signal base_health_changed(new_health: int)
signal level_up(new_level: int)
signal on_quit_button_pressed()
signal game_speed_changed(speed: float)
@warning_ignore_restore("unused_signal")
