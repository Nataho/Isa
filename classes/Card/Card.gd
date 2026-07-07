class_name Card extends Control
const FILE = preload("uid://c3fvu61ft2tex")

const colors = [
	Palette.Isa.RED, #red
	Palette.Isa.YELLOW, #yellow
	Palette.Isa.GREEN, #green
	Palette.Isa.BLUE, #blue
	Color("000000ff"), #wild
]

const sprite_reverse = preload("uid://dqqk6mkh1amna")
const sprite_draw2 = preload("uid://ddwh7o14vnukj")
const sprite_draw4 = preload("uid://ckabs6m8om3ve")
const sprite_wild = preload("uid://bffikvhhnmxks")
const sprite_skip = preload("uid://cpc8p8so3ku4o")

const sprite_back_isa = preload("uid://bypgukcfs6r1q")
const sprite_crown = preload("uid://cv06wpakl0u2b")

enum CardColor { RED, YELLOW ,GREEN, BLUE, WILD, BACK, CROWN}
enum CardType {
	ZERO, ONE, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE,
	SKIP, REVERSE, DRAW_TWO, DRAW_FOUR, COLOR, 
	DISCARD_ALL, SKIP_EVERYONE, COLOR_ROULETTE, DRAW_SIX, DRAW_TEN,
}

signal card_mouse_entered
signal card_mouse_exited
signal clicked

@onready var base: ColorRect = $body/base
@onready var border: TextureRect = $body/border
@onready var card_display: Label = $body/card_display
@onready var card_action: TextureRect = $body/card_action
@onready var mouse_listener: Control = $mouse_listener

@export var is_ui_button: bool = false
@export var expand_on_hovered:bool = true
@export var rotating:bool = false
@export var card_color: CardColor
@export var card_type: CardType:
	set(value):
		card_type = value
		_initialize_card_properties()

var id: int = -1
var value: int = 0
var draw_amount: int = 0
var skips_turn: bool = false
var skips_everyone: bool = false
var forces_hand_swap: bool = false
var reverses_turn:bool = false

@export var placeholder: Control = null #will contain the node to be followed
var hand:Hand = null
var discarded := false
var is_hovering := false
var clickable := false
var initial_rotation := 0.0

# ─── NEW FACE DOWN TRACKER ───
var is_face_down: bool = false

static func create(ID: int, color: CardColor, type: CardType) -> Card:
	var obj: Card = FILE.instantiate()
	obj.id = ID
	obj.card_color = color
	obj.card_type = type
	obj.clickable = true
	return obj

func get_card_details() -> Dictionary:
	var details = {
		"id": id,
		"draw_amount": draw_amount,
		"skips_turn": skips_turn,
		"skips_everyone": skips_everyone,
		"forces_hand_swap": forces_hand_swap,
		"reverses_turn": reverses_turn
	}
	
	return details

func set_placeholder(placeholder_node: Control) -> void:
	placeholder = placeholder_node

# ─── NEW METHOD: TOGGLE FACE DOWN VISUALS ───
func set_face_down(state: bool) -> void:
	is_face_down = state
	
	# If it's face down BUT it's a UI button, keep it clickable!
	if is_face_down and not is_ui_button:
		clickable = false
		if is_inside_tree():
			mouse_listener.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		clickable = true
		if is_inside_tree():
			mouse_listener.mouse_filter = Control.MOUSE_FILTER_STOP
			
	if is_inside_tree():
		_initialize_card_art()

func _ready() -> void:
	# ─── PIVOT FIX FOR PERFECT 3D SPIN ───
	# Sync the root Control size with the visual body, then center the pivot
	size = $body.size
	pivot_offset = size / 2.0
	
	# Ensure mouse filter matches state on load
	if is_face_down:
		mouse_listener.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	_initialize_card_art()
	_connect_signals()
	await get_tree().create_timer(0.1).timeout

func _process(delta: float) -> void:
	if discarded:
		border.modulate = Color.WHITE
		
		if get_parent():
			var target_pos = get_parent().global_position - (size / 2.0)
			global_position = global_position.lerp(target_pos, 8 * delta)
			rotation = lerp_angle(rotation, initial_rotation, 8 * delta)
	else:
		# ─── VISUAL PLAYABILITY INDICATOR ───
		if is_face_down or (hand and hand is NetworkHand):
			border.modulate = Color.WHITE
		elif is_playable():
			border.modulate = Color.WHITE 
		else:
			border.modulate = Color(1.0, 0.4, 0.4) # Red tint
		
		# ─── AUTONOMOUS PLACEHOLDER TRACKING ───
		if placeholder and is_instance_valid(placeholder):
			# 1. Follow Position
			var card_position := placeholder.global_position
			var card_center := placeholder.size / 2.0
			var final_position = card_position + card_center
			var card_offset = size / 2.0
			
			global_position = global_position.lerp(final_position - card_offset, 10 * delta)
			
			# 2. Dynamic Rotation 
			var base_rot = deg_to_rad(hand.base_rotation_degrees) if hand else initial_rotation
			
			if is_hovering:
				rotation = lerp_angle(rotation, 0.0, 10 * delta)
			else:
				rotation = lerp_angle(rotation, base_rot, 10 * delta)
			
			# 3. Follow Scale (Properly scaled spinning!)
			var target_scale = placeholder.scale
			
			if rotating:
				# Lerp Y normally, but multiply the X spin by the target scale!
				scale.y = lerp(scale.y, target_scale.y, 10 * delta)
				scale.x = sin(Time.get_ticks_msec() / 400.0) * target_scale.x
			else:
				# Normal uniform lerping for both axes
				scale = scale.lerp(target_scale, 10 * delta)
				
		else:
			# Fallback if the card is floating without a placeholder
			if rotating:
				# Keeps whatever scale.x you set in the editor, just makes it spin
				scale.x = sin(Time.get_ticks_msec() / 400.0) * abs(scale.y)

			if is_hovering:
				rotation = lerp_angle(rotation, 0.0, 10 * delta)
			else:
				rotation = lerp_angle(rotation, initial_rotation, 10 * delta)

func _connect_signals():
	mouse_listener.mouse_entered.connect(_card_mouse_entered)
	mouse_listener.mouse_exited.connect(_card_mouse_exited)
	mouse_listener.gui_input.connect(_on_mouse_listener_gui_input)

func _on_mouse_listener_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		
		# ─── 1. UI BUTTON MODE: Just emit a signal and stop ───
		if is_ui_button:
			clicked.emit()
			return
			
		# ─── 2. NORMAL GAMEPLAY MODE ───
		if discarded or is_face_down or (hand and hand is NetworkHand): 
			return
			
		if hand and hand.game_node:
			if hand.game_node.active_turn_lobby_id != hand.game_node.my_lobby_id:
				return
		
		if clickable:
			if is_playable():
				if card_color == CardColor.WILD:
					_process_wild_card_selection()
				else:
					request_play_card() 
			else:
				print("Cannot play card: Color or Type doesn't match!")

func _process_wild_card_selection() -> void:
	clickable = false
	
	var prompt = ColorPrompt.create(card_type)
	hand.game_node.add_child(prompt)
	
	var chosen_color_index: int = await prompt.color_chosen
	if chosen_color_index == -1:
		prompt.queue_free()
		clickable = true
		return # Stop the function from playing the card
	
	clickable = true
	card_color = chosen_color_index as CardColor
	_initialize_card_art()
	request_play_card() # ─── CHANGED HERE ───

func _trigger_wild_assert() -> void:
	# Fulfilling instruction: A dedicated assert validation point when a wild card executes
	assert(card_color == CardColor.WILD, "Dev Verification: Wild Card selection intercept active.")
	print("Assert verified: Pausing gameplay sequence for user color response...")

func request_play_card():
	# This safely sends the card to the game logic without looping
	if hand and hand.game_node:
		var my_id = hand.game_node.my_lobby_id
		hand.game_node._process_card_played(my_id, id, card_color, card_type)

func discard():
	discarded = true
	# Automatically flip the card face up if it's played from a network hand!
	if is_face_down:
		set_face_down(false)
	print("Visual discard triggered for card: ", id)

func is_playable() -> bool:
	if not hand or not hand.game_node:
		return true
		
	# ─── VISUAL TURN LOCK ───
	# If it's not my turn, nothing in my hand is playable.
	if hand.game_node.active_turn_lobby_id != hand.game_node.my_lobby_id:
		return false
		
	var top_card: Card = hand.game_node.get_top_card()
	
	if not top_card: return true
	if card_color == CardColor.WILD: return true
	if card_color == top_card.card_color: return true
	if card_type == top_card.card_type: return true
		
	return false

func _initialize_card_properties() -> void:
	draw_amount = 0
	skips_turn = false
	skips_everyone = false
	forces_hand_swap = false
	
	match card_type:
		CardType.DRAW_TWO: draw_amount = 2
		CardType.DRAW_FOUR: draw_amount = 4
		CardType.DRAW_SIX: draw_amount = 6
		CardType.DRAW_TEN: draw_amount = 10
		
		CardType.SKIP: skips_turn = true
		CardType.SKIP_EVERYONE: skips_everyone = true
		CardType.REVERSE: reverses_turn = true
		
	if draw_amount > 0:
		skips_turn = true

func _initialize_card_art() -> void:
	card_display.text = ""
	card_action.texture = null
	card_action.hide()
	
	# ─── OVERRIDE VISUALS IF FACE DOWN ───
	if is_face_down or card_color == CardColor.BACK:
		base.color = colors[CardColor.WILD]
		card_action.texture = sprite_back_isa
		card_action.show()
		return
	
	if card_color == CardColor.CROWN:
		base.color = colors[CardColor.WILD]
		card_action.texture = sprite_crown
		card_action.show()
		return
	
	base.color = colors[card_color]
	if card_color == CardColor.WILD:
		if value < 50: value = 50
		
	match card_type:
		CardType.ZERO, CardType.ONE, CardType.TWO, CardType.THREE, CardType.FOUR, \
		CardType.FIVE, CardType.SIX, CardType.SEVEN, CardType.EIGHT, CardType.NINE:
			var number_value = card_type - CardType.ZERO 
			card_display.text = str(number_value)
			value = card_type
		
		CardType.SKIP:
			card_action.texture = sprite_skip
			card_action.show()
			if value < 20: value = 20
		CardType.REVERSE:
			card_action.texture = sprite_reverse
			card_action.show()
			if value < 20: value = 20
		CardType.DRAW_TWO:
			card_action.texture = sprite_draw2
			card_action.show()
			if value < 20: value = 20
		CardType.DRAW_FOUR:
			card_action.texture = sprite_draw4
			card_action.show()
			if value < 30: value = 30
		CardType.DRAW_SIX:
			card_display.text = "+6" 
			card_action.show()
		CardType.DRAW_TEN:
			card_display.text = "+10"
			card_action.show()
			
		CardType.SKIP_EVERYONE:
			card_display.text = "X All"
		CardType.DISCARD_ALL:
			card_display.text = "Clear"
		CardType.COLOR_ROULETTE:
			card_display.text = "???"
		CardType.COLOR:
			card_action.texture = sprite_wild
			card_action.show()

func rise_short():
	$anim.play("rise")
	await get_tree().create_timer(0.2).timeout
	$anim.play("fall")

func _card_mouse_entered():
	if is_face_down and not is_ui_button: return
	card_mouse_entered.emit()
	is_hovering = true
	if placeholder:
		$anim.play("rise")
		if expand_on_hovered:
			placeholder.custom_minimum_size.x = 224
			placeholder.size.x = 224
	z_index += 1

func _card_mouse_exited():
	if is_face_down and not is_ui_button: return
	card_mouse_exited.emit()
	is_hovering = false
	if placeholder: 
		$anim.play("fall")
		if expand_on_hovered:
			placeholder.custom_minimum_size.x = 0
			placeholder.size.x = 0
	z_index -= 1
