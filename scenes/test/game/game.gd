class_name Game extends Control
const FILE = preload("uid://dttfkvs2j6lxn")

@onready var pile: Control = $pile
@onready var draw_pile: Card = $deck

@onready var crown: Card = $Card
@onready var win: Control = $win

@onready var timer: Timer = $Timer
@onready var turn_direction_node: TextureRect = $turn_direction
@onready var cards_left: Label = %cards_left #"cards left:\n0"

@onready var turn_time_label: Label = $turn_time_label #Turn Time\n0s
@onready var turn_timer: Timer = $turn_timer
@onready var highlight: Panel = $highlight

var paused := false

var player_hands: Dictionary = {}
var game_mode:Dictionary = {}

var deck: Deck = Deck.new()
var my_lobby_id: int = -1

# ─── HANDSHAKE VARIABLES ───
var players_loaded: Array = []
var handshake_timer: Timer = null

# turn state variables
var current_turn_index: int = 0
var turn_direction: int = 1 # 1 for clockwise, -1 for counter-clockwise
var active_turn_lobby_id: int = -1
var consecutive_skips: int = 0
var is_game_over: bool = false

var is_drawing_card: bool = false         # Client UI lock
var _host_turn_draw_locked: bool = false  # Host Server lock
var is_in_danger = false

# ─── 1. INSTANTIATION ───
static func create(game_mode:Dictionary) -> Game:
	var instance = FILE.instantiate() as Game
	instance.game_mode = game_mode	
	return instance

func _ready() -> void:
	Audio.play_music("battle")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	my_lobby_id = int(GameManager.inst.network_data.get("lobby_id", -1))
	
	Events.inst.sync_data.connect(_on_sync_data)
	
	turn_timer.timeout.connect(_on_turn_timer_timeout)
	_setup_player_hands()
	
	# ─── HANDSHAKE LOGIC ───
	if GameManager.inst.network_data.get("is_host", false):
		print("Host loaded. Waiting for clients...")
		Events.inst.client_left_lobby.connect(_on_player_dropped)
		players_loaded.append(my_lobby_id)
		
		handshake_timer = Timer.new()
		handshake_timer.wait_time = 20.0
		handshake_timer.one_shot = true
		handshake_timer.timeout.connect(_on_connection_timeout)
		add_child(handshake_timer)
		handshake_timer.start()
		
		_check_all_players_loaded()
	else:
		Events.inst.client_disconnected.connect(_on_server_disconnected)
		print("Client loaded. Sending ready signal to Host...")
		var payload := {
			"type": "game_scene_loaded",
			"lobby_id": my_lobby_id
		}
		NetworkSync.sync_data(payload)
	
	draw_pile.clicked.connect(_draw_card)
	timer.timeout.connect(_back_to_lobby)

func _process(delta: float) -> void:
	# ─── OSCILLATION CONFIGURATION ───
	var time: float = Time.get_ticks_msec() / 1000.0
	var base_y: float = 0.0

	# Vertical (Up/Down) settings
	var vertical_amplitude: float = 15.0  # How many pixels it moves up/down
	var vertical_speed: float = 1      # How fast it moves up/down

	# Rotational settings
	var rotation_amplitude: float = 3  # 5 degrees each way = 10 degrees total swing
	var rotation_speed: float = 1.5      # Unsynced speed (not a multiple of vertical_speed)
	var target_rotation_degrees = sin(time * rotation_speed) * rotation_amplitude
	crown.initial_rotation = deg_to_rad(target_rotation_degrees)
	
	var rot_speed:float = 30
	turn_direction_node.rotation_degrees += (rot_speed * delta) * turn_direction
	turn_direction_node.scale = turn_direction_node.scale.lerp(Vector2(1*turn_direction,1), delta * 5)
	
	if turn_timer.time_left > 0 and not is_game_over:
		turn_time_label.text = "Turn Time:\n" + str(ceil(turn_timer.time_left)) + "s"

		# ─── ONLY TRIGGER IF IT IS YOUR TURN AND TIME < 10 ───
		if active_turn_lobby_id == my_lobby_id and turn_timer.time_left < 10.0:
			if not is_in_danger:
				is_in_danger = true
				_in_danger_loop()
		else:
			# Turn it off if time goes back up OR your turn ends
			is_in_danger = false 
	else:
		turn_time_label.text = "Turn Time:\n0s"
		is_in_danger = false
	
	if player_hands.has(active_turn_lobby_id):
		var active_hand = player_hands[active_turn_lobby_id]
		if is_instance_valid(active_hand):
			highlight.show()
			
			# Higher multiplier = snappier movement. Lower multiplier = slower slide.
			var lerp_speed := delta * 8.0 
			
			# Smoothly slide and scale the highlight frame
			highlight.global_position = highlight.global_position.lerp(active_hand.global_position + active_hand.size/2, lerp_speed)
			#highlight.size = highlight.size.lerp(active_hand.size, lerp_speed)
			highlight.pivot_offset = highlight.pivot_offset.lerp(active_hand.pivot_offset, lerp_speed)
			
			# Crucial: lerp_angle stops the frame from doing wild 360-degree spins 
			highlight.rotation = lerp_angle(highlight.rotation, active_hand.rotation, lerp_speed)
	else:
		highlight.hide()
	

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if paused: return
		get_viewport().set_input_as_handled()
		var settings := Settings.create()
		settings.panel_closed.connect(func(): paused = false)
		add_child(settings)
		paused = true

func _draw_card():
	if is_game_over: return
	# 1. NOT YOUR TURN? Block it.
	if active_turn_lobby_id != my_lobby_id:
		print("It is not your turn!")
		return
		
	# 2. ALREADY CLICKED? Block spam/lag clicks.
	if is_drawing_card:
		return
		
	# Lock the client UI so they can't click it again this turn!
	is_drawing_card = true 

	if GameManager.inst.network_data.get("is_host", false):
		_host_process_manual_draw(my_lobby_id)
	else:
		# Client politely asks the host for a card
		NetworkSync.sync_data({
			"type": "request_draw", 
			"lobby_id": my_lobby_id
		})

func _host_process_manual_draw(requesting_player_id: int):
	var players = GameManager.inst.network_data.get("player_list", [])
	var expected_id = int(players[current_turn_index].get("lobby_id", -1))
	
	# SECURITY 1: Is it actually this player's turn?
	if requesting_player_id != expected_id:
		print("Host rejected draw: Not player ", requesting_player_id, "'s turn!")
		return
		
	# SECURITY 2: Have they already drawn a card this turn? (Stops lag packet spam)
	if _host_turn_draw_locked:
		print("Host rejected draw: Player ", requesting_player_id, " already drew a card!")
		return
		
	# Lock the Host from giving out any more manual draws this turn!
	_host_turn_draw_locked = true
	
	# Deal the actual card
	_host_deal_card(requesting_player_id)

func _is_card_compatible(card_to_check: Card) -> bool:
	var top_card = get_top_card()
	
	# If the pile is empty for some reason, anything goes
	if not top_card:
		return true
		
	# Wild cards can always be played
	if card_to_check.card_color == Card.CardColor.WILD:
		return true
		
	# Colors match
	if card_to_check.card_color == top_card.card_color:
		return true
		
	# IDs match (e.g., both are a "7" or both are a "Skip")
	if card_to_check.id == top_card.id:
		return true
		
	# If none of the above, it's an illegal move
	return false

# ─── 2. HAND SETUP ───
func _setup_player_hands():
	var players = GameManager.inst.network_data.get("player_list", [])
	var total_players = players.size()
	
	var my_index = 0
	for i in range(total_players):
		if int(players[i].get("lobby_id", -1)) == my_lobby_id:
			my_index = i
			break
			
	for i in range(total_players):
		var player = players[i]
		var p_id = int(player.get("lobby_id", -1))
		
		var p_name = player.get("name", "Player " + str(p_id)) 
		
		var relative_index = (i - my_index + total_players) % total_players
		var visual_seat = 0
		
		if total_players == 2:
			visual_seat = 0 if relative_index == 0 else 2
		elif total_players == 3:
			if relative_index == 0: visual_seat = 0
			elif relative_index == 1: visual_seat = 1
			elif relative_index == 2: visual_seat = 3
		else:
			visual_seat = relative_index

		var new_hand: Hand
		if p_id == my_lobby_id:
			new_hand = LocalHand.new()
			new_hand.name = "MyLocalHand"
			p_name += " (You)"
		else:
			new_hand = NetworkHand.new()
			new_hand.name = "OpponentHand_" + str(p_id)
			new_hand.assigned_lobby_id = p_id
			
		new_hand.set_game_node(self)
		
		new_hand.empty_hand.connect(_win_sequence.bind(p_id))
		
		match visual_seat:
			0: # BOTTOM 
				new_hand.is_vertical = false
				new_hand.base_rotation_degrees = 0.0
				new_hand.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
				new_hand.offset_bottom = -170
				new_hand.offset_top = -170 - 120 
			1: # LEFT EDGE 
				new_hand.is_vertical = true
				new_hand.base_rotation_degrees = 90.0
				new_hand.set_anchors_preset(Control.PRESET_LEFT_WIDE)
				new_hand.offset_left = 170
				new_hand.offset_right = 170 + 120
			2: # TOP EDGE 
				new_hand.is_vertical = false
				new_hand.base_rotation_degrees = 180.0
				new_hand.set_anchors_preset(Control.PRESET_TOP_WIDE)
				new_hand.offset_top = 170
				new_hand.offset_bottom = 170 + 120
			3: # RIGHT EDGE 
				new_hand.is_vertical = true
				new_hand.base_rotation_degrees = -90.0
				new_hand.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
				new_hand.offset_right = -170
				new_hand.offset_left = -170 - 120

		add_child(new_hand)
		new_hand.set_player_name(p_name)
		player_hands[p_id] = new_hand


# ─── 3. HANDSHAKE METHODS ───
func _check_all_players_loaded():
	var players = GameManager.inst.network_data.get("player_list", [])
	
	if players_loaded.size() >= players.size():
		print("All players have loaded the game scene!")
		if handshake_timer and not handshake_timer.is_stopped():
			handshake_timer.stop()
			
		_host_start_game()

func _on_connection_timeout():
	var players = GameManager.inst.network_data.get("player_list", [])
	var to_remove = []
	
	for player in players:
		var p_id = int(player.get("lobby_id", -1))
		if not players_loaded.has(p_id):
			to_remove.append(p_id)
			
	for p_id in to_remove:
		print("Player ", p_id, " timed out while loading! Kicking...")
		_remove_player(p_id)
		
		NetworkSync.sync_data({
			"type": "player_kicked", 
			"lobby_id": p_id
		})
		
	_host_start_game()

func _remove_player(p_id: int):
	if player_hands.has(p_id):
		var hand_node = player_hands[p_id]
		if is_instance_valid(hand_node):
			hand_node.queue_free()
		player_hands.erase(p_id)
		
	var players = GameManager.inst.network_data.get("player_list", [])
	for i in range(players.size() - 1, -1, -1):
		if int(players[i].get("lobby_id", -1)) == p_id:
			players.remove_at(i)
			break


# ─── 4. HOST LOGIC ───
func _host_start_game():
	print("Host is generating deck and batching starting hands...")
	var mod = game_mode.get("mode", "isa")
	var inverted = game_mode.get("inverted", false)
	if mod == "isa":
		if inverted:
			deck.generate_inverted_standard_deck()
		else:
			deck.generate_standard_deck()
			
	
	var players = GameManager.inst.network_data.get("player_list", [])
	var starting_hands = {}
	
	# Setup empty arrays for each player's starting hand
	for player in players:
		starting_hands[int(player.get("lobby_id", -1))] = []
		
	# Instantly draw 7 cards per player and sort them into the dictionary
	for i in range(7):
		for player in players:
			var target_id = int(player.get("lobby_id", -1))
			var card: Card = deck.draw_card()
			if card:
				starting_hands[target_id].append({
					"card_id": card.id,
					"card_color": card.card_color,
					"card_type": card.card_type
				})
				
	# Send ONE single payload containing everyone's starting hand
	var payload := {
		"type": "initial_deal",
		"hands": starting_hands
	}
	NetworkSync.sync_data(payload)
	
	# The host also needs to run the visual animation locally!
	_process_initial_deal(starting_hands)
	
	var count_payload := {
		"type": "deck_update",
		"count": deck.get_remaining_count()
	}
	NetworkSync.sync_data(count_payload)
	_update_deck_visual(deck.get_remaining_count())

func _host_deal_card(target_id: int):
	var card: Card = deck.draw_card()
	
	if not card:
		# ─── DECK IS EMPTY: FORCE A SKIP INSTEAD ───
		print("Deck is empty! Auto-skipping turn.")
		_host_process_skip_turn(target_id)
		return
	
	var payload := {
		"type": "deal_card",
		"target_lobby_id": target_id,
		"card_id": card.id,
		"card_color": card.card_color,
		"card_type": card.card_type
	}
	NetworkSync.sync_data(payload)
	
	# ─── BROADCAST THE REMAINING DECK COUNT ───
	var count_payload := {
		"type": "deck_update",
		"count": deck.get_remaining_count()
	}
	NetworkSync.sync_data(count_payload)
	_update_deck_visual(deck.get_remaining_count())

func _host_play_card_to_pile(card: Card):
	_process_card_played(my_lobby_id, card.id, card.card_color, card.card_type)


# ─── 5. NETWORK LISTENER ───
func _on_sync_data(data: Dictionary):
	var type = data.get("type", "")
	
	match type:
		"game_scene_loaded":
			if GameManager.inst.network_data.get("is_host", false):
				var p_id = int(data.get("lobby_id", -1))
				if not players_loaded.has(p_id):
					players_loaded.append(p_id)
				_check_all_players_loaded()
				
		"player_kicked":
			var kicked_id = int(data.get("lobby_id", -1))
			_remove_player(kicked_id)
			
			if kicked_id == my_lobby_id:
				print("I was kicked for timing out!")
				GameManager.inst.reset_network_data()
				Transition.change_scene(Transition.Scenes.MAIN, Transition.DISSOLVE)
		
		"initial_deal":
			# Only clients need to catch this, the Host already called it locally
			if not GameManager.inst.network_data.get("is_host", false):
				_process_initial_deal(data.get("hands", {}))
		
		"deal_card":
			Audio.play_sound("deal")
			var target = int(data.get("target_lobby_id", -1))
			
			if target == my_lobby_id:
				# FIXED ORDER: Pass ID first
				_receive_card(data.get("card_id"), data.get("card_color"), data.get("card_type"))
			else:
				if player_hands.has(target):
					# FIXED ORDER: Card.create(ID, color, type)
					var dummy_card = Card.create(data.get("card_id"), data.get("card_color"), data.get("card_type"))
					dummy_card.set_face_down(true)
					player_hands[target].draw_card(dummy_card)
		"deck_update":
			if not GameManager.inst.network_data.get("is_host", false):
				_update_deck_visual(data.get("count", 0))
				
		"request_draw":
			if GameManager.inst.network_data.get("is_host", false):
				var requesting_player = int(data.get("lobby_id", -1))
				_host_deal_card(requesting_player)
		
		"play_card":
			Audio.play_sound("deal")
			if is_game_over: return
			var player_id = int(data.get("lobby_id", -1))
			
			if GameManager.inst.network_data.get("is_host", false):
				var players = GameManager.inst.network_data.get("player_list", [])
				var expected_id = int(players[current_turn_index].get("lobby_id", -1))
				if player_id != expected_id:
					print("Host blocked lag spam! It is no longer Player ", player_id, "'s turn.")
					return
			
			if player_id != my_lobby_id:
				_process_card_played(player_id, data.get("card_id"), data.get("card_color"), data.get("card_type"))
		"turn_update":
			var whose_turn = int(data.get("lobby_id", -1))
			_set_active_turn(whose_turn)
			
			# ─── RESET CLOCK ON NEW TURN ───
			turn_timer.stop()
			if not is_game_over:
				turn_timer.start(30.0)
		
		"skip_turn":
			# Only the Host handles the math for passing the turn
			if GameManager.inst.network_data.get("is_host", false):
				var skipping_player = int(data.get("lobby_id", -1))
				_host_process_skip_turn(skipping_player)
		
		"request_draw":
			if GameManager.inst.network_data.get("is_host", false):
				var requesting_player = int(data.get("lobby_id", -1))
				
				# Route this through our new security function!
				_host_process_manual_draw(requesting_player)
		
		"resolve_softlock":
			if not GameManager.inst.network_data.get("is_host", false):
				_process_softlock()
		
		"player_left":
			var dropped_id = int(data.get("lobby_id", -1))
			GameManager.inst.network_data["player_list"] = data.get("new_list", [])
			
			# Delete their hand from the screen
			if player_hands.has(dropped_id):
				var hand_node = player_hands[dropped_id]
				if is_instance_valid(hand_node):
					hand_node.queue_free()
				player_hands.erase(dropped_id)
		
		"play_action_event":
			var card_details = data.get("card", {})
			var game_turn_direction = int(data.get("turn_direction", 1))
			var target_id = int(data.get("target_id", -1))
			
			if not GameManager.inst.network_data.get("is_host", false):
				turn_direction = game_turn_direction 
				
			# ─── THE FIX: Check the booleans directly from your dictionary! ───
			var is_reverse = card_details.get("reverses_turn", false)
			var is_super_skip = card_details.get("skips_everyone", false)
			
			# 1. IS IT A GLOBAL EFFECT? (Reverse or Tornado)
			if is_reverse or is_super_skip:
				# Everyone gets the full screen effect!
				add_child(CardEffects.create(card_details, game_turn_direction))
				
			# 2. IT'S A TARGETED ATTACK (Draws, Normal Skips)
			else:
				if target_id == my_lobby_id:
					# VICTIM: Full screen jumpscare!
					add_child(CardEffects.create(card_details, game_turn_direction))
				else:
					# EVERYONE ELSE: Tiny version!
					if player_hands.has(target_id):
						var victim_hand = player_hands[target_id]
						
						if is_instance_valid(victim_hand) and is_instance_valid(victim_hand.effect_anchor):
							var mini_effect = CardEffects.create(card_details, game_turn_direction)
							victim_hand.effect_anchor.add_child(mini_effect)
							
							await get_tree().process_frame
							
							if is_instance_valid(mini_effect):
								mini_effect.scale = Vector2(0.25, 0.25)
								var icon_center = mini_effect.icon.position + (mini_effect.icon.size / 2.0)
								mini_effect.position = -icon_center
					

func _process_initial_deal(hands_data: Dictionary):
	var players = GameManager.inst.network_data.get("player_list", [])
	
	# Loop 10 times. In each loop, give 1 card to each player.
	for i in range(10):
		for player in players:
			var p_id = int(player.get("lobby_id", -1))
			
			# ─── THE FIX: Safely extract the array whether the key is an int or a string ───
			var player_hand_data = null
			if hands_data.has(p_id): 
				player_hand_data = hands_data[p_id] # Host catches this
			elif hands_data.has(str(p_id)): 
				player_hand_data = hands_data[str(p_id)] # Client catches this
			
			if player_hand_data != null and i < player_hand_data.size():
				var card_data = player_hand_data[i]
				
				# Create the physical card
				var new_card = Card.create(card_data.card_id, card_data.card_color, card_data.card_type)
				
				if p_id == my_lobby_id:
					# Deal to MY hand (Face Up)
					if player_hands.has(my_lobby_id):
						player_hands[my_lobby_id].draw_card(new_card)
						# NOTE: Local player receive animation / sound goes here
				else:
					# Deal to OPPONENT hand (Face Down)
					new_card.set_face_down(true)
					if player_hands.has(p_id):
						player_hands[p_id].draw_card(new_card)
						# NOTE: Opponent receive animation / sound goes here
						
				# NOTE: The delay that makes the alternating animation visible!
				await get_tree().create_timer(0.08).timeout 
				
	if GameManager.inst.network_data.get("is_host", false):
		await get_tree().create_timer(0.5).timeout
		
		var first_card := deck.draw_starting_card()
		if first_card:
			_host_play_card_to_pile(first_card)
			
			var count_payload := {
				"type": "deck_update",
				"count": deck.get_remaining_count()
			}
			NetworkSync.sync_data(count_payload)
			_update_deck_visual(deck.get_remaining_count())
			
		randomize()
		current_turn_index = randi() % players.size()
		
		_host_process_card_effects(first_card, -1)

func _receive_card(c_id: int, c_color: int, c_type: int):
	var new_card = Card.create(c_id, c_color, c_type)
	
	if active_turn_lobby_id == my_lobby_id:
		if _is_card_compatible(new_card):
			var prompt = DrawPrompt.create(c_id, c_color, c_type)
			add_child(prompt)
			
			var wants_to_play: bool = await prompt.action_chosen
			
			if wants_to_play:
				if new_card.card_color == Card.CardColor.WILD:
					var color_prompt = ColorPrompt.create(new_card)
					add_child(color_prompt)
					var chosen_color_index = await color_prompt.color_chosen
					if chosen_color_index == -1:
						color_prompt.queue_free()
						return # Stop the function from playing the card
					new_card.card_color = chosen_color_index as Card.CardColor
				
				discard_to_pile(new_card, my_lobby_id)
				
				if GameManager.inst.network_data.get("is_host", false):
					_host_process_card_effects(new_card, my_lobby_id)
				
			else:
				if player_hands.has(my_lobby_id):
					player_hands[my_lobby_id].draw_card(new_card)
				_on_skip_button_pressed()
				
		else:
			print("Drawn card is not compatible. Keeping it and ending turn.")
			if player_hands.has(my_lobby_id):
				player_hands[my_lobby_id].draw_card(new_card)
			_on_skip_button_pressed()
			
	else:
		if player_hands.has(my_lobby_id):
			player_hands[my_lobby_id].draw_card(new_card)

# ─── 7. TURN LOGIC (HOST ONLY) ───
func _host_process_card_effects(card: Card, played_by_id: int):
	var players = GameManager.inst.network_data.get("player_list", [])
	var total_players = players.size()
	
	consecutive_skips = 0
	
	# 1. Reverse Logic (Affects everyone globally)
	if card.reverses_turn:
		if total_players == 2:
			pass # Acts as a skip, handled below
		else:
			turn_direction *= -1 
			
	# ─── CALCULATE THE TARGET ───
	# Figure out who is next in line BEFORE we do the skip/draw math
	var next_index = (current_turn_index + turn_direction + total_players) % total_players
	var target_player_id = int(players[next_index].get("lobby_id", -1))
	
	# Broadcast with the target attached!
	_broadcast_action_event(card, target_player_id)

	# 2. Draw Logic
	if card.draw_amount > 0:
		for i in range(card.draw_amount):
			_host_deal_card(target_player_id)
			await get_tree().create_timer(0.25).timeout

	# 3. Skip Logic 
	if card.skips_turn or (total_players == 2 and card.reverses_turn):
		next_index = (next_index + turn_direction + total_players) % total_players

	# 4. Skip Everyone (Tornado/Super Skip)
	if card.skips_everyone:
		#_broadcast_action_event("super_skip", card)
		next_index = current_turn_index

	# 5. Hand Swap
	if card.forces_hand_swap:
		print("UI Hook: SWAP HANDS Animation! (Logic TBD)")

	# Set new index and broadcast it to all clients
	current_turn_index = next_index
	
	var next_player_lobby_id = int(players[current_turn_index].get("lobby_id", -1))
	var payload := {
		"type": "turn_update",
		"lobby_id": next_player_lobby_id
	}
	NetworkSync.sync_data(payload)
	
	# Host processes their own turn update locally
	_set_active_turn(next_player_lobby_id)

func _broadcast_action_event(card: Card, target_id: int = -1):
	var payload := {
		"type": "play_action_event",
		"card": card.get_card_details(),
		"turn_direction": turn_direction,
		"target_id": target_id
	}
	NetworkSync.sync_data(payload)

func _set_active_turn(lobby_id: int):
	active_turn_lobby_id = lobby_id
	print("\n>>> IT IS NOW PLAYER ", lobby_id, "'S TURN <<<")
	
	# ─── UNLOCK THE DRAW PILE ───
	if lobby_id == my_lobby_id:
		is_drawing_card = false # Unlock my local UI
		
	if GameManager.inst.network_data.get("is_host", false):
		_host_turn_draw_locked = false # Unlock the Server for the next player
	
	# Loop through all hands and update their visuals based on whose turn it is
	for p_id in player_hands.keys():
		var hand_node = player_hands[p_id]
		if not is_instance_valid(hand_node): continue
		
		if p_id == lobby_id:
			# ACTIVE PLAYER: Full brightness, normal scale
			hand_node.modulate = Color(1.0, 1.0, 1.0, 1.0)
			hand_node.scale = Vector2(1.00, 1.00) # Pop out slightly
			
			if p_id == my_lobby_id:
				print("my turn alert") #FIXME
				#Audio.play_sound("my_turn_alert") 
		else:
			# WAITING PLAYERS: Dimmed out, slightly smaller
			hand_node.modulate = Color(0.5, 0.5, 0.5, 1.0)
			hand_node.scale = Vector2(1.0, 1.0)

func _process_card_played(played_by_id: int, c_id: int, c_color: int, c_type: int):
	var source_hand: Hand = player_hands.get(played_by_id, null)
	var played_card: Card = null
	
	if source_hand:
		for card in source_hand.deck:
			if card.id == c_id:
				played_card = card
				break
				
	if not played_card:
		# If we somehow don't have the card, create a fresh one with the network data
		played_card = Card.create(c_id, c_color, c_type)
	else:
		# ─── THE MAGIC WILD CARD FIX ───
		# If we DO have the card (it was sitting in their hand), its color is currently WILD.
		# We must update it to the color they selected BEFORE we discard it!
		played_card.card_color = c_color as Card.CardColor
		played_card.card_type = c_type as Card.CardType

	discard_to_pile(played_card, played_by_id)
	
	if GameManager.inst.network_data.get("is_host", false):
		_host_process_card_effects(played_card, played_by_id)

func get_top_card() -> Card:
	if pile.get_child_count() > 0:
		return pile.get_child(pile.get_child_count() - 1) as Card
	return null

func discard_to_pile(card: Card, played_by_id: int):
	if is_game_over: return
	
	if card.hand:
		card.hand.remove_card_from_hand(card)
	
	if played_by_id == my_lobby_id:
		active_turn_lobby_id = -1
		is_drawing_card = true
	
	if card.get_parent():
		if card.get_parent() != pile:
			card.reparent(pile)
	else:
		pile.add_child(card)
		card.global_position = (get_viewport_rect().size / 2.0) - (card.size / 2.0)

	# 3. BRUTE FORCE THE CENTER TARGET
	# This completely ignores any broken UI layouts and guarantees
	# your Card.gd script lerps to the exact center of the game window.
	pile.global_position = get_viewport_rect().size / 2.0

	# 4. Trigger the lerp animation loop inside your Card.gd
	if not card.discarded: 
		card.discard()
		
	card.rotation = deg_to_rad(randf_range(-15, 15))
	card.initial_rotation = card.rotation

	# Outbound Network Broadcast
	if played_by_id == my_lobby_id:
		var payload := {
			"type": "play_card",
			"lobby_id": my_lobby_id,
			"card_id": card.id,
			"card_color": card.card_color,
			"card_type": card.card_type
		}
		NetworkSync.sync_data(payload)

func _host_process_skip_turn(skipping_player_id: int):
	# Double check that the person skipping is actually the active player
	var players = GameManager.inst.network_data.get("player_list", [])
	var expected_player_id = int(players[current_turn_index].get("lobby_id", -1))
	
	if skipping_player_id != expected_player_id:
		print("Warning: Player tried to skip out of turn!")
		return

	var total_players = players.size()
	
	# ─── SOFTLOCK DETECTION ───
	consecutive_skips += 1
	
	# If the deck is empty AND a full round of players have skipped consecutively...
	if deck.get_remaining_count() <= 0 and consecutive_skips >= total_players:
		
		# ─── THE NEW CHECK GOES HERE ───
		if _is_game_truly_softlocked():
			print("Host detected softlock! Resolving game...")
			var payload := { "type": "resolve_softlock" }
			NetworkSync.sync_data(payload)
			
			# Process it locally on the Host machine
			_process_softlock()
			return # STOP the function so the turn doesn't advance!
		else:
			print("Players are skipping, but someone has a playable card! Resetting skip count.")
			consecutive_skips = 0 # Reset skips so the game continues!
	
	# Advance to the next person based on the current turn direction
	current_turn_index = (current_turn_index + turn_direction + total_players) % total_players
	
	var next_player_lobby_id = int(players[current_turn_index].get("lobby_id", -1))
	var payload := {
		"type": "turn_update",
		"lobby_id": next_player_lobby_id
	}
	NetworkSync.sync_data(payload)
	
	# Host processes their own turn update locally
	_set_active_turn(next_player_lobby_id)

func _on_skip_button_pressed():
	if is_game_over: return
	# Only allow the player to skip if it is actually their turn!
	if active_turn_lobby_id == my_lobby_id:
		print("Skipping my turn...")
		# NOTE: Play your local skip button animation or sound here!
		
		# ─── THE FIX: ROUTE HOST SKIP LOCALLY ───
		if GameManager.inst.network_data.get("is_host", false):
			_host_process_skip_turn(my_lobby_id)
		else:
			# Clients ask the network to process the skip
			var payload := {
				"type": "skip_turn",
				"lobby_id": my_lobby_id
			}
			NetworkSync.sync_data(payload)

func _win_sequence(winner_id: int):
	if is_game_over: return
	is_game_over = true
	
	print("Player ", winner_id, " has won!")
	
	# Optional UI cleanup for drama
	draw_pile.hide()
	
	# Grab the visual Hand node of whoever just won
	var winner_hand: Hand = player_hands[winner_id]
	
	# Calculate the exact center of their hand on the screen
	var target_global_pos = winner_hand.global_position + (winner_hand.size / 2.0) - (win.size / 2.0)
	
	# Start the placeholder in the dead center of the screen
	win.global_position = (get_viewport_rect().size / 2.0) - (win.size / 2.0)
	crown.set_placeholder(win)
	
	Audio.play_music("victory")

	await get_tree().create_timer(2.0).timeout
	win.global_position = target_global_pos
	win.scale = Vector2(1.5,1.5)
	
	timer.start()

func _back_to_lobby():
	print("Game over! Returning to the lobby...")
	
	player_hands.clear()
	players_loaded.clear()
	
	timer.stop()
	
	Transition.change_scene(Transition.Scenes.LOBBY, Transition.DISSOLVE)
	await Transition.inst.screen_obscured

	queue_free()
	
func _update_deck_visual(count: int):
	# ─── UPDATE THE LABEL TEXT ───
	if cards_left and is_instance_valid(cards_left):
		cards_left.text = "cards left:\n" + str(count)

	if count <= 0:
		print("Deck empty! Changing into Wild Skip.")
		draw_pile.set_face_down(false)
		draw_pile.card_color = Card.CardColor.WILD
		
		# Note: Ensure "SKIP" matches exactly what is in your Card script's enum!
		draw_pile.card_type = Card.CardType.SKIP 
		
		# Trigger whatever function your Card script uses to update its sprite/texture
		if draw_pile.has_method("_initialize_card_art"):
			draw_pile._initialize_card_art()
	else:
		draw_pile.set_face_down(true)

func _process_softlock():
	if is_game_over: return
	is_game_over = true
	print("Softlock detected. Revealing hands and calculating scores...")
	
	draw_pile.hide()
	
	var lowest_score: int = 999999
	var winner_id: int = -1
	
	for p_id in player_hands.keys():
		var hand_node = player_hands[p_id]
		var score = 0
		
		for card in hand_node.deck:
			if card.is_face_down:
				card.set_face_down(false)
			
			score += card.value
			
		print("Player ", p_id, " final score: ", score)
		
		if score < lowest_score:
			lowest_score = score
			winner_id = p_id
			
	await get_tree().create_timer(4.0).timeout
	if winner_id != -1:
		is_game_over = false 
		
		_win_sequence(winner_id)

func _is_game_truly_softlocked() -> bool:
	# If the deck still has cards, players can draw, so it's not softlocked yet.
	if deck.get_remaining_count() > 0:
		return false
		
	# Check every player's hand for a playable card
	for p_id in player_hands:
		var hand = player_hands[p_id]
		for card in hand.deck:
			if _is_card_compatible(card):
				return false # Someone has a valid card, keep playing!
				
	return true # Deck is empty AND literally no one can play

func reset_turn_timer() -> void:
	turn_timer.stop()
	if not is_game_over:
		turn_timer.start(30.0) # 30-second window

# This triggers on the host when the 30-second timer hits zero
func _on_turn_timer_timeout() -> void:
	if is_game_over: 
		return
		
	# Stop the timer instantly so it doesn't double-fire!
	turn_timer.stop()
		
	# Security check: Only the Host modifies the game state and turn order!
	if GameManager.inst.network_data.get("is_host", false):
		print("Player ", active_turn_lobby_id, " timed out! Penalty: Draw 10 and skip.")
		
		# 1. Save the ID of the AFK player before we change the turn
		var afk_player_id = active_turn_lobby_id
		
		# 2. Skip their turn IMMEDIATELY.
		# This tells their client "Your turn is over!" which permanently disables the draw prompt.
		_host_process_skip_turn(afk_player_id)
		
		# 3. Now deal the 10 cards using the exact same logic as a +2 or +4.
		# Because it's no longer their turn, the cards will slip quietly into their hand.
		for i in range(10):
			_host_deal_card(afk_player_id)
			await get_tree().create_timer(0.25).timeout

#handles player disconnection after 15 seconds
func _on_player_dropped(player_data: Dictionary) -> void:
	if is_game_over: return
	
	var dropped_id = int(player_data.get("lobby_id", -1))
	var players = GameManager.inst.network_data.get("player_list", [])
	var dropped_index = -1
	
	# 1. Find where they were in the turn order
	for i in range(players.size()):
		if int(players[i].get("lobby_id", -1)) == dropped_id:
			dropped_index = i
			break
			
	if dropped_index == -1: return # Player wasn't found, abort
	
	print("Game: Player ", dropped_id, " abandoned the match!")
	
	# 2. Remove them from the master list
	players.remove_at(dropped_index)
	GameManager.inst.network_data["player_list"] = players
	
	# 3. Tell everyone to delete their cards
	NetworkSync.sync_data({
		"type": "player_left", 
		"lobby_id": dropped_id, 
		"new_list": players
	})
	
	# Host deletes cards locally
	if player_hands.has(dropped_id):
		var hand_node = player_hands[dropped_id]
		if is_instance_valid(hand_node):
			hand_node.queue_free()
		player_hands.erase(dropped_id)
	
	# if only 1 player remains (the Host), abort the game and go back to Lobby!
	if players.size() <= 1:
		print("Game: All clients disconnected! Aborting match and returning to lobby...")
		is_game_over = true
		
		GameManager.inst.network_data["game_status"] = "getting ready"
		
		Transition.change_scene(Transition.Scenes.LOBBY, Transition.DISSOLVE)
		return
		
	# 5. Fix the turn order!
	if dropped_index < current_turn_index:
		# If someone BEFORE the current player left, shift the index down to compensate
		current_turn_index -= 1
	elif dropped_index == current_turn_index:
		# If it was THEIR turn when they left, immediately force the turn to the next person!
		if current_turn_index >= players.size():
			current_turn_index = 0
			
		var next_id = int(players[current_turn_index].get("lobby_id", -1))
		NetworkSync.sync_data({"type": "turn_update", "lobby_id": next_id})
		_set_active_turn(next_id)
		reset_turn_timer()

func _on_server_disconnected() -> void:
	print("Game: Lost connection to server! Returning to main menu...")
	
	NetworkClient.stop()
	GameManager.inst.reset_network_data()
	Transition.change_scene(Transition.Scenes.MAIN, Transition.DISSOLVE)

func _in_danger_loop():
	if !is_in_danger: return
	print("danger")
	Audio.play_sound("danger")
	await get_tree().create_timer(0.5).timeout
	_in_danger_loop()
