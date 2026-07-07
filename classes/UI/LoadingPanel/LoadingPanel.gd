class_name LoadingPanel extends Panel
const FILE = preload("uid://cvep3e0oxtcki")

@onready var message_node: RichTextLabel = $message

var message:String = "Connecting to server"

static func create(message_text:String) -> LoadingPanel:
	var obj:LoadingPanel = FILE.instantiate()
	obj.message = message_text
	
	return obj

func _ready():
	_update_text()

func _update_text():
	message_node.text = _format_message(message)

func _format_message(text_to_format: String) -> String:
	return "[center][wave amp=30.0 freq=5.0 connected=1]" + text_to_format + "[/wave][/center]"

func update_message(new_message:String):
	message = new_message
	_update_text()
	
