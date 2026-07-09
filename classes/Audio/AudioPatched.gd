extends Audio

func _enter_tree() -> void:
	# Overwrite the global reference to point to THIS new patched script
	active_node = self
	music_player_node = AudioStreamPlayer.new()
	add_child(music_player_node)

	# Re-initialize the dictionaries dynamically at runtime
	_sound = {
		"hover" : 	[load("res://assets/audio/sfx/hover.mp3"), 0],
		"confirm1": [load("res://assets/audio/sfx/confirm1.mp3"), 0],
		"confirm2": [load("res://assets/audio/sfx/confirm2.mp3"), 0],
		"confirm3": [load("res://assets/audio/sfx/confirm3.mp3"), 0],
		"drawed": 	[load("res://assets/audio/sfx/drawed.wav"), 0],
		"skip": 	[load("res://assets/audio/sfx/skip.mp3"), 0],
		"reverse": 	[load("res://assets/audio/sfx/reverse.mp3"), 0],
		"danger": 	[load("res://assets/audio/sfx/danger.wav"), 0],
		"deal": 	[load("res://assets/audio/sfx/deal.mp3"), 0],
		"scroll": 	[load("res://assets/audio/sfx/scroll.mp3"), 0]
	}

	_music = {
		"main": [load("res://assets/audio/music/main_menu.mp3"), -5],
		"lobby": [load("res://assets/audio/music/lobby.mp3"), 0],
		"victory": [load("res://assets/audio/music/victory.mp3"), 0],
		"battle": [load("res://assets/audio/music/Tetris Chaos - Epic Battle.mp3"), 0],
	}
