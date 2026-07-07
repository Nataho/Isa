extends Control

@onready var players: VBoxContainer = $MarginContainer/HBoxContainer/players
@onready var ready_button: Button = %ReadyButton
@onready var timer: Timer = $Timer
@onready var time_label: Label = $MarginContainer/HBoxContainer/GameButtons/time_label


var max_players = 4 # Limited to 4 players as per seating layout
var player_list: Array = [] 
var countdown_time: int = 120

func _ready() -> void:
	# Reset local ready status so the button defaults back to Yellow
	GameManager.inst.network_data["is_ready"] = false
	
	_connect_signals()
	_setup_network_data()
	Audio.play_music("lobby", Audio.SOUND_END_EFFECTS.FADE)

func _setup_network_data():
	var existing_players = GameManager.inst.network_data.get("player_list", [])
	
	if GameManager.inst.network_data["is_host"]:
		GameManager.inst.network_data["game_status"] = "getting ready"
		
		# If the list is empty, this is a BRAND NEW lobby creation
		if existing_players.is_empty():
			NetworkServer.start()
			GameManager.inst.network_data["lobby_id"] = 1
			
			player_list.clear()
			player_list.append({
				"lobby_id": 1,
				"name": GameManager.inst.player_data["name"],
				"is_ready": false
			})
		else:
			Events.inst.client_disconnected.connect(_on_server_disconnected)
			# RETURNING FROM A MATCH: Restore the list
			player_list = existing_players
			# Reset everyone's ready status!
			for p in player_list:
				p["is_ready"] = false
		
		_update_player_ui()
		_broadcast_current_list() # Guarantee clients get the fresh un-readied list
		
	else:
		# Client returning from a match: Instantly build UI so it doesn't blink empty
		if not existing_players.is_empty():
			player_list = existing_players
			for p in player_list:
				p["is_ready"] = false
			_update_player_ui()
			
		print("Client loaded. Requesting latest player list from host...")
		var request_payload := {
			"type": "request_player_list"
		}
		NetworkSync.sync_data(request_payload)

func _connect_signals():
	if GameManager.inst.network_data.get("is_host", false):
		Events.inst.join_requested.connect(_on_join_requested)
		Events.inst.client_left_lobby.connect(_on_client_left_lobby)
		Events.inst.client_left_lobby.connect(_on_player_dropped)
	else:
		Events.inst.client_disconnected.connect(_on_client_disconnected)
	
	Events.inst.sync_data.connect(_on_sync_data)
	ready_button.pressed.connect(_ready_toggle)
	timer.timeout.connect(_countdown)

func _on_sync_data(data: Dictionary):
	var type = data.get("type", "")
	match type:
		"update_player_list":
			player_list = data["player_list"]
			_update_player_ui()
		"request_player_list":
			if GameManager.inst.network_data["is_host"]:
				_broadcast_current_list()
		"toggle_ready":
			if GameManager.inst.network_data["is_host"]:
				var p_id = data.get("lobby_id", -1)
				var p_ready = data.get("is_ready", false)
				_host_update_player_ready(p_id, p_ready)
		
		# ─── MULTIPLAYER TIMER LISTENERS ───
		"lobby_countdown":
			countdown_time = data.get("time", 120)
			_update_countdown_time()
			print("Game starting in: ", countdown_time)
			
		"lobby_countdown_cancelled":
			countdown_time = 120
			print("Countdown stopped. Not enough players ready.")
			
		"start_game":
			_start_sequence()

func _update_player_ui():
	for player in players.get_children():
		player.queue_free()
	
	for player_profile in player_list:
		if typeof(player_profile) == TYPE_DICTIONARY:
			var player_name: String = player_profile.get("name", "Unknown")
			var is_ready: bool = player_profile.get("is_ready", false)
			var color = Palette.Isa.GREEN if is_ready else Palette.Isa.YELLOW
			
			var tag = LobbyTag.create(player_name, color)
			players.add_child(tag)



func _on_join_requested(ws_peer: WebSocketPeer, player_data: Dictionary):
	print("someone is trying to join: ", player_data)
	
	var joining_name = player_data.get("name", "").strip_edges()
	var joining_id = player_data.get("lobby_id", -1)
	
	if NetworkServer.inst.active_players.size() >= max_players:
		NetworkServer.reject_join(ws_peer, "The lobby is full.")
		return
	if joining_name == "" or joining_name == "player":
		NetworkServer.reject_join(ws_peer, "Invalid username.")
		return
	if joining_id == -1:
		NetworkServer.reject_join(ws_peer, "Missing lobby_id in join request.")
		return
		
	NetworkServer.approve_join(ws_peer, player_data)
	
	player_list.append({
		"lobby_id": joining_id,
		"name": joining_name,
		"is_ready": false
	})
	
	# ─── TIMER RESET ON JOIN ───
	if GameManager.inst.network_data["is_host"]:
		if not timer.is_stopped():
			timer.stop() 
		countdown_time = 120
		print("A new player has joined! Resetting lobby timer.")
	
	_update_player_ui()
	_broadcast_current_list()
	
	if GameManager.inst.network_data["is_host"]:
		_check_start_condition()

func _broadcast_current_list():
	var sync_payload := {
		"type": "update_player_list",
		"player_list": player_list
	}
	NetworkSync.sync_data(sync_payload)

func _host_update_player_ready(target_id: int, ready_state: bool):
	for profile in player_list:
		if profile.get("lobby_id", -1) == target_id:
			profile["is_ready"] = ready_state
			break
	_update_player_ui()
	_broadcast_current_list()
	_check_start_condition()

# ─── DYNAMIC START CONDITIONS ───
func _check_start_condition():
	if player_list.is_empty():
		return

	var total_players = player_list.size()
	var ready_count = 0
	for profile in player_list:
		if profile.get("is_ready", false):
			ready_count += 1
			
	# Condition 1: ALL players are ready -> Skip straight to 10 seconds remaining
	if ready_count == total_players and total_players >= 2:
		countdown_time = 10
		if timer.is_stopped():
			timer.start()
		print("Everyone is ready! Fast-forwarding timer to 10 seconds.")
		NetworkSync.sync_data({"type": "lobby_countdown", "time": countdown_time})
		
	# Condition 2: At least 2 players are ready -> Normal 120s count
	elif ready_count >= 2:
		if timer.is_stopped():
			countdown_time = 120
			timer.start()
			print("2+ players ready. Starting lobby timer at 120 seconds.")
			NetworkSync.sync_data({"type": "lobby_countdown", "time": countdown_time})
			
	# Condition 3: Less than 2 players are ready -> Stop the timer entirely
	else:
		if not timer.is_stopped():
			timer.stop()
			countdown_time = 120
			print("Not enough players ready. Stopping timer.")
			NetworkSync.sync_data({"type": "lobby_countdown_cancelled"})

func _on_client_left_lobby(player_data: Dictionary) -> void:
	var left_id = player_data.get("lobby_id", -1)
	
	for i in range(player_list.size() - 1, -1, -1):
		if player_list[i].get("lobby_id", -1) == left_id:
			player_list.remove_at(i)
			break
			
	_update_player_ui()
	_broadcast_current_list()
	_check_start_condition()

func _on_player_dropped(player_data: Dictionary) -> void:
	var dropped_id = player_data.get("lobby_id", -1)
	print("Lobby: Player ", dropped_id, " disconnected!")
	
	# Find and remove them from the host's master list
	for i in range(player_list.size() - 1, -1, -1):
		if int(player_list[i].get("lobby_id", -1)) == dropped_id:
			player_list.remove_at(i)
			break
			
	# Update the UI and tell all remaining clients about the new list!
	_update_player_ui()
	_broadcast_current_list()

func _on_server_disconnected() -> void:
	print("Lobby: Lost connection to server! Returning to main menu")
	
	NetworkClient.stop()
	GameManager.inst.reset_network_data()
	Transition.change_scene(Transition.Scenes.MAIN, Transition.DISSOLVE)

func _on_client_disconnected() -> void:
	GameManager.inst.reset_network_data()
	Transition.change_scene(Transition.Scenes.MAIN, Transition.DISSOLVE)

func _ready_toggle():
	var ready_status = GameManager.inst.network_data.get("is_ready", false)
	ready_status = !ready_status
	GameManager.inst.network_data["is_ready"] = ready_status
	
	var new_button_color = Palette.Isa.GREEN if ready_status else Palette.Isa.YELLOW
	var stylebox: StyleBoxFlat = ready_button.get_theme_stylebox("normal")
	stylebox.bg_color = new_button_color
	
	var my_id = GameManager.inst.network_data.get("lobby_id", -1)
	
	if GameManager.inst.network_data["is_host"]:
		_host_update_player_ready(my_id, ready_status)
	else:
		var payload := {
			"type": "toggle_ready",
			"lobby_id": my_id,
			"is_ready": ready_status
		}
		NetworkSync.sync_data(payload)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if GameManager.inst.network_data["is_host"]:
			NetworkServer.stop()
		else:
			NetworkClient.stop()
			
		GameManager.inst.reset_network_data()
		Transition.change_scene(Transition.Scenes.MAIN, Transition.DISSOLVE)

# ─── COUNTDOWN TICK AND AUTOMATIC READY ───
func _countdown():
	if not GameManager.inst.network_data["is_host"]: 
		return 

	countdown_time -= 1
	NetworkSync.sync_data({"type": "lobby_countdown", "time": countdown_time})
	
	if countdown_time <= 0:
		timer.stop()
		NetworkSync.sync_data({"type": "start_game"})

func _host_force_everyone_ready():
	print("10 seconds remaining! Automatically readying all players.")
	for profile in player_list:
		profile["is_ready"] = true
	_update_player_ui()
	_broadcast_current_list()

# ─── CLEAN SCENE SWAP VIA ROOT ───
func _start_sequence():
	GameManager.inst.network_data["player_list"] = player_list
	GameManager.inst.network_data["game_status"] = "in game"
	
	Transition.change_scene(Transition.Scenes.DUMMY, Transition.DISSOLVE)
	# Instantiate cleanly via your static function
	await Transition.inst.screen_obscured
	var game_instance = Game.create()
	
	# Add directly to root so it sits fresh on screen without lobby baggage
	get_tree().root.add_child(game_instance)
	
	# Cleanly wipe the lobby scene and its inputs out of existence
	queue_free()

func _update_countdown_time():
	time_label.text = "Time Left:\n" + str(countdown_time)
	pass
