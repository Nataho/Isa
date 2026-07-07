class_name Deck extends Node

# Signal to alert your GameManager if both the deck AND discard pile are totally empty
signal deck_completely_empty

var cards: Array[Card] = []
var id_counter: int = 0

### 1. DECK GENERATION
# Generates a standard 108-card UNO deck
func generate_standard_deck() -> void:
	_clear_deck()
	
	# Grouping all colored cards together for loop generation
	var colored_types = [
		Card.CardType.ZERO, Card.CardType.ONE, Card.CardType.TWO, Card.CardType.THREE,
		Card.CardType.FOUR, Card.CardType.FIVE, Card.CardType.SIX, Card.CardType.SEVEN,
		Card.CardType.EIGHT, Card.CardType.NINE, Card.CardType.SKIP, Card.CardType.REVERSE,
		Card.CardType.DRAW_TWO
	]
	
	# Loop through the 4 core colors (Indices 0 to 3 in your enum)
	for color_index in [Card.CardColor.RED, Card.CardColor.GREEN, Card.CardColor.BLUE, Card.CardColor.YELLOW]:
		for type in colored_types:
			if type == Card.CardType.ZERO:
				# Standard UNO only has ONE '0' card per color
				_add_new_card(color_index, type)
			else:
				# Standard UNO has TWO of every number 1-9 and action card per color
				_add_new_card(color_index, type)
				_add_new_card(color_index, type)
				
	# Add Wild Cards (Index 4 is WILD in your enum)
	for i in range(4):
		_add_new_card(Card.CardColor.WILD, Card.CardType.COLOR)     # Standard Wild
		_add_new_card(Card.CardColor.WILD, Card.CardType.DRAW_FOUR) # Wild Draw 4

	shuffle()

# Helper function to generate and track IDs seamlessly
func _add_new_card(color: Card.CardColor, type: Card.CardType) -> void:
	var new_card = Card.create(id_counter,color, type)
	cards.append(new_card)
	id_counter += 1

func _clear_deck() -> void:
	for card in cards:
		if is_instance_valid(card) and not card.is_inside_tree():
			card.queue_free()
	cards.clear()
	id_counter = 0


### 2. CORE GAMEPLAY FUNCTIONS
# Shuffles the remaining cards in the deck
func shuffle() -> void:
	cards.shuffle()

# Draws a card from the top of the deck
func draw_card() -> Card:
	if cards.is_empty():
		return null
	return cards.pop_back()

# Returns how many cards are left in the draw pile
func get_remaining_count() -> int:
	return cards.size()


### 3. RECOMMENDED EXTENSIONS
# Takes cards from a discard pile, resets them, and populates the deck again
func reshuffle_from_discard(discard_pile: Array[Card]) -> void:
	if discard_pile.is_empty():
		deck_completely_empty.emit()
		return
		
	print("Draw pile empty. Reshuffling discard pile back into the deck...")
	
	for card in discard_pile:
		# If the card was previously placed into the scene tree, remove it
		if card.get_parent():
			card.get_parent().remove_child(card)
			
		# Reset any scaling or positioning adjustments made by UI/animations
		card.position = Vector2.ZERO
		card.rotation = 0
		card.scale = Vector2.ONE
		
		cards.append(card)
		
	shuffle()

func draw_starting_card() -> Card:
	if cards.is_empty():
		return null
		
	# Search backwards (from the top of the deck downwards)
	for i in range(cards.size() - 1, -1, -1):
		var card = cards[i]
		
		# Check if it is a standard number card (0-9) and completely ignore Wilds/Actions
		if card.card_type >= Card.CardType.ZERO and card.card_type <= Card.CardType.NINE and card.card_color != Card.CardColor.WILD:
			# Pull this exact card out of the deck and return it
			return cards.pop_at(i)
			
	# Fallback if somehow no number cards exist (extremely rare)
	return draw_card()
