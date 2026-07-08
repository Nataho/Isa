extends Control

@onready var players: VBoxContainer = $MarginContainer/HBoxContainer/players
@onready var ready_button: Button = %ReadyButton
@onready var timer: Timer = $Timer
@onready var time_label: Label = $MarginContainer/HBoxContainer/GameButtons/time_label

@onready var mods_panel: Panel = %ModsPanel
@onready var blank_panel: Control = $MarginContainer/HBoxContainer/Control

@onready var mods_button: Button = %ModsButton

@onready var mod_cards:Array[Card] = [
	$MarginContainer/HBoxContainer/GameButtons/Control/isa
]
@onready var mod_placeholders:Array[Control] = [
	$MarginContainer/HBoxContainer/ModsPanel/hand/isa
]
@onready var mod_placeholder: Control = $MarginContainer/HBoxContainer/GameButtons/Control/mod_placeholder

var max_players = 4 # Limited to 4 players as per seating layout
var player_list: Array = [] 
var countdown_time: int = 120

# ─── LOBBY CONFIGURATION TRACKERS ───
var mods_panel_visible: bool = false
var game_mode: Dictionary = {
	"mode": "isa",
	"inverted": false
}

func _ready() -> void:
	# Reset local ready status so the button defaults back to Yellow
	GameManager.inst.network_data["is_ready"] = false
	
	_connect_signals()
	_setup_network_data()
	
	# ─── ROLE-BASED VISUAL INITIALIZATION ───
	if GameManager.inst.network_data.get("is_host", false):
		_update_mods_layout() # Host sets up their unique interactive layout
	else:
		mods_button.hide() # Hide the panel toggle button entirely for clients
		for card in mod_cards:
			card.clickable = false # Strip click authorization
			card.is_holdable = false # Strip hold authorization
			card.set_placeholder(mod_placeholder) # Lock client cards to the main floating layout
			
	_update_mod_cards_visuals()
	Audio.play_music("lobby", Audio.SOUND_END_EFFECTS.FADE)

func _setup_network_data():
	var existing_players = GameManager.inst.network_data.get("player_list", [])
	
	# ─── RETRIEVE PERSISTENT SETTINGS ───
	# Pull from GameManager if it exists, otherwise use the standard default fallback
	game_mode = GameManager.inst.network_data.get("game_mode", {
		"mode": "isa",
		"inverted": false
	})

	if GameManager.inst.network_data["is_host"]:
		GameManager.inst.network_data["game_status"] = "getting ready"
		
		if existing_players.is_empty():
			NetworkServer.start()
			GameManager.inst.network_data["lobby_id"] = 1
			
			player_list.clear()
			player_list.append({
				"lobby_id": 1,
				"name": GameManager.inst.player_data["name"],
				"is_ready": false
			})
			# Store the initial configuration setup safely
			GameManager.inst.network_data["game_mode"] = game_mode
		else:
			Events.inst.client_disconnected.connect(_on_server_disconnected)
			player_list = existing_players
			for p in player_list:
				p["is_ready"] = false
		
		_update_player_ui()
		_broadcast_current_list()
		
	else:
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
		
		# ─── HOST-ONLY INTERACTION CONNECTIONS ───
		mods_button.pressed.connect(_on_mods_button_pressed)
		for i in range(mod_cards.size()):
			var card = mod_cards[i]
			card.clickable = true
			card.is_holdable = true
			card.clicked.connect(func(): _on_mod_card_interact(card, false))
			card.held_click.connect(func(): _on_mod_card_interact(card, true))
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
			
			if data.has("game_mode"):
				game_mode = data["game_mode"]
				# Keep client-side memory mirrors in sync too
				GameManager.inst.network_data["game_mode"] = game_mode
				_update_mod_cards_visuals()
				
			_update_player_ui()
			
		"request_player_list":
			if GameManager.inst.network_data["is_host"]:
				_broadcast_current_list()
				
		"toggle_ready":
			if GameManager.inst.network_data["is_host"]:
				var p_id = data.get("lobby_id", -1)
				var p_ready = data.get("is_ready", false)
				_host_update_player_ready(p_id, p_ready)
		
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

# ─── HOST-ONLY VISUAL LAYOUT MANAGER ───
func _update_mods_layout() -> void:
	mods_panel.visible = mods_panel_visible
	blank_panel.visible = !mods_panel_visible
	
	for i in range(mod_cards.size()):
		if mods_panel_visible:
			mod_cards[i].set_placeholder(mod_placeholders[i])
		else:
			mod_cards[i].set_placeholder(mod_placeholder)

func _update_mod_cards_visuals() -> void:
	for card in mod_cards:
		var target_mode = card.name.to_lower()
		
		if target_mode == game_mode["mode"]:
			if game_mode["inverted"]:
				if card.has_method("invert_rotation"): card.invert_rotation()
				elif card.has_method("_invert_rotation"): card._invert_rotation()
			else:
				if card.has_method("reset_rotation"): card.reset_rotation()
		else:
			if card.has_method("reset_rotation"): card.reset_rotation()

# ─── HOST INTERACTION PROCESSORS ───
func _on_mods_button_pressed() -> void:
	mods_panel_visible = !mods_panel_visible
	_update_mods_layout() # Only fires locally on the host's screen

func _on_mod_card_interact(card: Card, is_inverted_hold: bool) -> void:
	var selected_mode = card.name.to_lower()
	
	game_mode = {
		"mode": selected_mode,
		"inverted": is_inverted_hold
	}
	
	# ─── SAVE TO PERSISTENT CACHE ───
	GameManager.inst.network_data["game_mode"] = game_mode
	
	_update_mod_cards_visuals()
	_broadcast_current_list()

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
	
	if GameManager.inst.network_data["is_host"]:
		if not timer.is_stopped():
			timer.stop()
		countdown_time = 120
		print("A new player has joined! Resetting lobby timer.")
	
	_update_player_ui()
	_broadcast_current_list() # Automatically updates the newly joined player's mode configuration!
	
	if GameManager.inst.network_data["is_host"]:
		_check_start_condition()

func _broadcast_current_list():
	var sync_payload := {
		"type": "update_player_list",
		"player_list": player_list,
		"game_mode": game_mode # Sent cleanly down to everyone
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

func _check_start_condition():
	if player_list.is_empty():
		return

	var total_players = player_list.size()
	var ready_count = 0
	for profile in player_list:
		if profile.get("is_ready", false):
			ready_count += 1
			
	if ready_count == total_players and total_players >= 2:
		countdown_time = 10
		if timer.is_stopped():
			timer.start()
		print("Everyone is ready! Fast-forwarding timer to 10 seconds.")
		NetworkSync.sync_data({"type": "lobby_countdown", "time": countdown_time})
		
	elif ready_count >= 2:
		if timer.is_stopped():
			countdown_time = 120
			timer.start()
			print("2+ players ready. Starting lobby timer at 120 seconds.")
			NetworkSync.sync_data({"type": "lobby_countdown", "time": countdown_time})
			
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
	
	for i in range(player_list.size() - 1, -1, -1):
		if int(player_list[i].get("lobby_id", -1)) == dropped_id:
			player_list.remove_at(i)
			break
			
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

func _start_sequence():
	GameManager.inst.network_data["player_list"] = player_list
	GameManager.inst.network_data["game_status"] = "in game"
	
	# Handoff configuration payload seamlessly to the gameplay layer
	GameManager.inst.network_data["game_mode"] = game_mode
	
	Transition.change_scene(Transition.Scenes.DUMMY, Transition.DISSOLVE)
	await Transition.inst.screen_obscured
	var game_instance = Game.create(game_mode)
	
	get_tree().root.add_child(game_instance)
	queue_free()

func _update_countdown_time():
	time_label.text = "Time Left:\n" + str(countdown_time)
	pass
