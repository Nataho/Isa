class_name DrawPrompt extends Panel
const FILE = preload("uid://bvig0ujsm5m7b")

# Signal emits true if they want to play the card, false if they want to keep it
signal action_chosen(play_card: bool)

@onready var main_card: Card = $main
@onready var skip_card: Card = $skip

# Store the drawn card's info
var c_id: int
var c_color: int
var c_type: int

static func create(card_id: int, color: int, type: int) -> DrawPrompt:
	var obj: DrawPrompt = FILE.instantiate()
	obj.c_id = card_id
	obj.c_color = color
	obj.c_type = type
	return obj

func _ready() -> void:
	# Assign the UI placeholders
	main_card.set_placeholder($hand/main_card)
	skip_card.set_placeholder($hand/skip_card)
	
	# Apply the drawn card's data to the main card so it looks correct
	main_card.id = c_id
	main_card.card_color = c_color as Card.CardColor
	main_card.card_type = c_type as Card.CardType
	main_card._initialize_card_art()
	
	# Start them in the center of the screen so they fly outwards!
	var screen_center = get_viewport_rect().size / 2.0
	main_card.global_position = screen_center - (main_card.size / 2.0)
	skip_card.global_position = screen_center - (skip_card.size / 2.0)
	
	# Connect the click signals from your Card.gd script
	main_card.clicked.connect(_on_play_pressed)
	skip_card.clicked.connect(_on_keep_pressed)

func _process(delta: float) -> void:
	_lerp_card(main_card, delta)
	_lerp_card(skip_card, delta)

func _lerp_card(card: Card, delta: float) -> void:
	if is_instance_valid(card) and card.placeholder and is_instance_valid(card.placeholder):
		var final_position = card.placeholder.global_position + (card.placeholder.size / 2.0)
		var card_offset = card.size / 2.0
		card.global_position = card.global_position.lerp(final_position - card_offset, 10 * delta)

func _on_play_pressed() -> void:
	action_chosen.emit(true)
	if c_color == Card.CardColor.WILD:
		_close_prompt(main_card, skip_card, true)
		return
	_close_prompt(main_card, skip_card)

func _on_keep_pressed() -> void:
	action_chosen.emit(false)
	_close_prompt(skip_card, main_card)

func _close_prompt(chosen: Card, rejected: Card, instant:bool = false) -> void:
	if instant:
		queue_free()
		return
	# Bring chosen card to the front
	chosen.z_index += 1
	
	# Send them both to a center 'Control' node so they fly away
	chosen.set_placeholder($Control)
	rejected.set_placeholder($Control)
	
	# Wait for the animation to finish before destroying the prompt
	await get_tree().create_timer(0.5).timeout
	queue_free()
