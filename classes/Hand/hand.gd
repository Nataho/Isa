class_name Hand extends Control

@export var is_vertical: bool = false
@export var base_rotation_degrees: float = 0.0
const USERNAME_LABEL_SETTINGS = preload("uid://ox0kiicrcoi7")

signal empty_hand

var deck: Array[Card] = []
var game_deck: Deck = null
var game_node: Game = null
var effect_anchor: Control = null

var _cards_container: Container = null
var name_tag: Label = null

func _ready() -> void:
	_ensure_cards_container_exists()

# ─── AUTONOMOUS CONTAINER BUILDER WITH SEPARATION ───
func _ensure_cards_container_exists() -> Container:
	if _cards_container and is_instance_valid(_cards_container):
		return _cards_container
		
	if has_node("cards"):
		_cards_container = get_node("cards") as Container
	else:
		if is_vertical:
			_cards_container = VBoxContainer.new()
		else:
			_cards_container = HBoxContainer.new()
			
		_cards_container.name = "cards"
		add_child(_cards_container)
	
	_cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cards_container.add_theme_constant_override("separation", 40)
	
	# ─── NEW: CREATE THE ANCHOR ───
	if not has_node("effect_anchor"):
		# 1. The Anchor
		effect_anchor = Control.new()
		effect_anchor.name = "effect_anchor"
		effect_anchor.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		effect_anchor.size = Vector2.ZERO
		add_child(effect_anchor)
		
		# 2. The Name Tag
		name_tag = Label.new()
		name_tag.name = "name_tag"
		name_tag.label_settings = USERNAME_LABEL_SETTINGS
		name_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		# FORCE THE LABEL TO GROW OUTWARDS FROM THE CENTER 
		name_tag.grow_horizontal = Control.GROW_DIRECTION_BOTH
		name_tag.grow_vertical = Control.GROW_DIRECTION_BOTH
		
		effect_anchor.add_child(name_tag)
		name_tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		
		# REMOVED the hardcoded position push here! We do it in the setter below.
		
	else:
		effect_anchor = get_node("effect_anchor")
		if has_node("name_tag"):
			name_tag = get_node("name_tag")
	# ──────────────────────────────
			
	if custom_minimum_size == Vector2.ZERO:
		if is_vertical:
			custom_minimum_size = Vector2(120, 500)
		else:
			custom_minimum_size = Vector2(500, 120)
			
	return _cards_container

func draw_card(card: Card):
	var container = _ensure_cards_container_exists()

	var placeholder = Control.new()
	card.hand = self
	
	if is_vertical:
		placeholder.custom_minimum_size = Vector2(68, 48)
	else:
		placeholder.custom_minimum_size = Vector2(48, 68) 
		
	card.set_placeholder(placeholder)
	
	placeholder.custom_minimum_size = Vector2.ZERO
	placeholder.size = Vector2.ZERO
	
	deck.append(card)
	container.add_child(placeholder)
	
	add_child(card)
	
	if game_node and game_node.draw_pile:
		card.global_position = game_node.draw_pile.global_position
	else:
		card.global_position = get_viewport_rect().size / 2.0
		
	card.rotation_degrees = base_rotation_degrees

func remove_card_from_hand(card: Card) -> void:
	deck.erase(card)
	
	if card.placeholder and is_instance_valid(card.placeholder):
		card.placeholder.queue_free()
		card.placeholder = null
	
	if deck.size() <= 0:
		empty_hand.emit()
		

func set_game_deck(game_deck: Deck):
	self.game_deck = game_deck
	
func set_game_node(game_node: Game):
	self.game_node = game_node

func set_player_name(player_name: String) -> void:
	_ensure_cards_container_exists()
	if name_tag:
		name_tag.text = player_name
		await get_tree().process_frame
		
		if base_rotation_degrees != 180:
			name_tag.rotation_degrees = base_rotation_degrees
		name_tag.pivot_offset = name_tag.size / 2.0
		
		var edge_direction = Vector2.DOWN.rotated(deg_to_rad(base_rotation_degrees))
		var push_distance = 175.0 
		
		name_tag.position = -(name_tag.size / 2.0) + (edge_direction * push_distance)
