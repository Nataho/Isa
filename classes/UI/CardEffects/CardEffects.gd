class_name CardEffects extends Control
const FILE = preload("uid://2f3bl606807e")

const REVERSE_CCW = "reverse_ccw" 	#reverse counter clockwise
const REVERSE_CW = "reverse_cw"		#reverse clockwise
const START_DROP = "start_drop"
const FLASH = "flash"

const SKIP = "skip"
const DRAW = "draw"
const DRAWPLUS = "drawplus"
const WILD = "wild"

const ICON_DRAW_2 = preload("uid://08s7xpw34ud7")
const ICON_REVERSE = preload("uid://b2ef61bpnv737")
const ICON_SKIP = preload("uid://csp7jlgr5g01i")

const ICON_DRAW_4 = preload("uid://bpksqntw7mc7p")
const ICON_WILD = preload("uid://cn3xqht56c64m")

@onready var anim: AnimationPlayer = $anim
@onready var icon: TextureRect = $icon
@onready var pulse: TextureRect = $pulse

var turn_direction:int
var target_id = -1
var animation_order :Array[String] = []
var card:Dictionary = {
	"id": -1,
	"draw_amount": 0
	,
	"skips_turn": false,
	"skips_everyone": false,
	"forces_hand_swap": false,
	"reverses_turn": true
}
var playing := ""
var debug := true
#NOTE:give animations to all kinds of cards and have priority

##card: is the action card that is discarded
static func create(card_data: Dictionary, turn_dir: int, target_id: int = -1) -> CardEffects:
	var obj:CardEffects = FILE.instantiate()
	obj.card = card_data.duplicate()
	obj.turn_direction = turn_dir
	obj.target_id = target_id
	obj.debug = false
	return obj

#static func create() -> CardEffects:
	#var obj:CardEffects = FILE.instantiate()
	#
	#return obj

func _ready() -> void:
	_do_animations()
	
func _do_animations():
	if card["reverses_turn"]:
		if turn_direction == 1:
			animation_order.append(REVERSE_CW)
		else:
			animation_order.append(REVERSE_CCW)
	
	if card["draw_amount"] > 0:
		animation_order.append(START_DROP)
	if card["skips_turn"]:
		if card["draw_amount"] == 0:
			animation_order.append(FLASH)
	
	for animation in animation_order:
		anim.play(animation)
		playing = animation
		_change_icon()
		await anim.animation_finished
		
		if animation_order.find(animation) < animation_order.size() -1:
			anim.play("RESET")
			await  anim.animation_finished
	
	if !debug: queue_free()

func _do_sfx():
	match playing:
		START_DROP:
			Audio.play_sound("drawed")
		FLASH:
			Audio.play_sound("skip")
		REVERSE_CCW, REVERSE_CW:
			Audio.play_sound("reverse")

func _change_icon():
	var texture = null
	match playing:
		REVERSE_CCW, REVERSE_CW:
			texture = ICON_REVERSE
		START_DROP:
			if card["draw_amount"] == 2: texture = ICON_DRAW_2
			if card["draw_amount"] == 4: texture = ICON_DRAW_4
			#if card["draw_amount"] == 6: texture = ICON_DRAW_6
			#texture = ICON_DRAW_2
		FLASH:
			texture = ICON_SKIP
	
	for node:TextureRect in [icon, pulse]:
		node.texture = texture
		
func shake(duration: float = 0.4, intensity: float = 30.0) -> void:
	var target_node = icon
	var tween = create_tween()
	var original_pos = target_node.position
	
	# We want a rapid movement every 0.05 seconds
	var step_time: float = 0.05
	var shake_steps = int(duration / step_time)
	
	# Loop through and create random jagged movements
	for i in range(shake_steps):
		var random_offset = Vector2(
			randf_range(-intensity, intensity), 
			randf_range(-intensity, intensity)
		)
		tween.tween_property(target_node, "position", original_pos + random_offset, step_time)
		
	# Always snap exactly back to the original position at the end!
	tween.tween_property(target_node, "position", original_pos, step_time)
	
	# Wait for the tween to finish before moving on
	await tween.finished
