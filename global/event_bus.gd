extends Node

@warning_ignore_start("unused_signal")
signal player_died
signal base_health_changed(new_health: int)
signal level_up(new_level: int)
signal on_quit_button_pressed()
signal game_speed_changed(speed: float)
signal resource_changed(kind: int, amount: int)
signal roster_changed(kind: int, count: int)
signal shop_purchased(item_id: String, purchases: int)
@warning_ignore_restore("unused_signal")
