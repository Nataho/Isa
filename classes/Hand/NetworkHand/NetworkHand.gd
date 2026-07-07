class_name NetworkHand extends Hand

# Assign this in the editor or when spawning the player so it knows who to listen to
@export var assigned_lobby_id: int = -1 

func _ready() -> void:
	# Connect to your global network events
	Events.inst.sync_data.connect(_on_sync_data)

# Override draw_card to force the card face down
func draw_card(card: Card):
	super.draw_card(card) # Run the base positioning logic
	
	# Assuming your Card class has a way to hide the front!
	if card.has_method("set_face_down"):
		card.set_face_down(true)

func _on_sync_data(data: Dictionary):
	var type = data.get("type", "")
	var target_id = data.get("lobby_id", -1)
	
	# Ignore if the network packet isn't meant for this specific hand
	if target_id != assigned_lobby_id:
		return
		
	match type:
		"opponent_drew_card":
			# Let the game node handle pulling from the deck, 
			# but this hand will receive the card instance
			pass
			
		"opponent_played_card":
			# Find the specific card (or just the first one if we only know they played 'a' card)
			# and trigger the removal animation/logic
			pass
