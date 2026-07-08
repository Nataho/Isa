class_name ColorPrompt extends Panel
const FILE = preload("uid://bd67yh2f44pv5")

signal color_chosen(color_index: int)

@onready var red: Card = $red
@onready var yellow: Card = $yellow
@onready var green: Card = $green
@onready var blue: Card = $blue
@onready var skip: Card = $skip


var card_type:Card.CardType = Card.CardType.DRAW_FOUR
var card:Card = null
var prompt_cards: Array[Card] = []
var placeholders: Array[Control] = []

static func create(card:Card) -> ColorPrompt:
	var obj:ColorPrompt = FILE.instantiate()
	obj.card_type = card.card_type
	obj.card = card
	return obj

func _ready() -> void:
	red.set_placeholder($hand/red)
	yellow.set_placeholder($hand/yellow)
	green.set_placeholder($hand/green)
	blue.set_placeholder($hand/blue)
	skip.set_placeholder($hand/skip)
	
	if card.card_color == card.CardColor.INVERTED_WILD:
		red.card_color = Card.CardColor.MINT
		yellow.card_color = Card.CardColor.PURPLE
		green.card_color = Card.CardColor.PINK
		blue.card_color = Card.CardColor.ORANGE
		
		red._initialize_card_art()
		yellow._initialize_card_art()
		green._initialize_card_art()
		blue._initialize_card_art()
	
	red.clicked.connect(_red)
	yellow.clicked.connect(_yellow)
	green.clicked.connect(_green)
	blue.clicked.connect(_blue)
	
	skip.clicked.connect(_cancel)
	
	prompt_cards = [red, yellow, green, blue, skip]
	placeholders = [$hand/red, $hand/yellow, $hand/green, $hand/blue, $hand/skip]
	
	var screen_center = WindowManager.get_screen_center()
	for card: Card in prompt_cards:
		card.global_position = screen_center - (card.size / 2.0)
		
		if card != skip:
			card.card_type = card_type as Card.CardType
		card._initialize_card_art()

func _cancel() -> void:
	color_chosen.emit(-1)

func _process(delta: float) -> void:
	for card in prompt_cards:
		if is_instance_valid(card) and card.placeholder and is_instance_valid(card.placeholder):
			var card_position := card.placeholder.global_position
			var card_center := card.placeholder.size / 2.0
			var final_position = card_position + card_center
			var card_offset = card.size / 2.0
			
			card.global_position = card.global_position.lerp(final_position - card_offset, 10 * delta)

func _red():  _on_color_button_pressed(red.card_color); red.z_index += 1
func _yellow(): _on_color_button_pressed(yellow.card_color); yellow.z_index += 1
func _green(): _on_color_button_pressed(green.card_color); green.z_index += 1
func _blue(): _on_color_button_pressed(blue.card_color); blue.z_index += 1

func _on_color_button_pressed(chosen_index: int) -> void:
	color_chosen.emit(chosen_index)
	for i in range(prompt_cards.size()):
		if chosen_index == i:
			prompt_cards[i].z_index += 1
		prompt_cards[i].set_placeholder($Control)
	
	await get_tree().create_timer(0.5).timeout
	for i in range(prompt_cards.size()):
		if chosen_index != i:
			prompt_cards[i].queue_free()
		#placeholders[i].queue_free()
	queue_free() # Safely wipe the prompt out of existence
