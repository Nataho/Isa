class_name LobbyTag extends Button
const FILE = preload("uid://c1ke1cnxmpus7")

var username: String = "player"
var color: Color = Palette.Isa.YELLOW

static func create(username: String, color: Color = Palette.Isa.YELLOW) -> LobbyTag:
	var obj: LobbyTag = FILE.instantiate()
	obj.username = username
	obj.color = color
	return obj  

func _ready() -> void:
	text = username.to_upper()
	
	# ─── THE FIX: Duplicate the shared stylebox and override it locally ───
	var shared_stylebox = get_theme_stylebox("normal")
	if shared_stylebox:
		var unique_stylebox: StyleBoxFlat = shared_stylebox.duplicate()
		unique_stylebox.bg_color = color
		add_theme_stylebox_override("normal", unique_stylebox)

func change_color(new_color: Color):
	color = new_color
	
	# Fetch the unique stylebox override we applied earlier
	var unique_stylebox = get_theme_stylebox("normal") as StyleBoxFlat
	if unique_stylebox:
		unique_stylebox.bg_color = new_color
