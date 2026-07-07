class_name LocalHand extends Hand

var is_sorting: bool = false

func _ready() -> void:
	# Local hands should always be face up!
	pass

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_next"):
		sort_hand()

# Local hand retains the cool visual sorting logic
func sort_hand() -> void:
	if deck.is_empty() or is_sorting:
		return

	is_sorting = true

	deck.sort_custom(func(a: Card, b: Card) -> bool:
		if a.card_color != b.card_color:
			return a.card_color < b.card_color
		return a.card_type < b.card_type
	)
	
	for i in range(deck.size()):
		if i >= deck.size(): 
			break
			
		var target_card = deck[i]
		target_card.rise_short()
		
		if is_instance_valid(target_card):
			if "placeholder" in target_card and target_card.placeholder != null:
				_cards_container.move_child(target_card.placeholder, i)
			move_child(target_card, -1)
		
		await get_tree().create_timer(0.05).timeout

	is_sorting = false
