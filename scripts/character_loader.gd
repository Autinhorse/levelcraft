class_name CharacterLoader extends RefCounted

class FormData extends RefCounted:
	var sprite_frames: SpriteFrames
	var shape: RectangleShape2D
	var size: Vector2

class CharacterData extends RefCounted:
	var name: String
	var default_form: String
	var forms: Dictionary = {}

static func load_from_json(path: String) -> CharacterData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open character JSON: %s" % path)
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid character JSON: %s" % path)
		return null
	var data: Dictionary = parsed

	var cd := CharacterData.new()
	cd.name = data.get("name", "")
	cd.default_form = data.get("defaultForm", "")

	var forms_dict: Dictionary = data.get("forms", {})
	for form_name in forms_dict:
		cd.forms[form_name] = _build_form(cd.name, form_name, forms_dict[form_name])
	return cd

static func _build_form(char_name: String, form_name: String, form_json: Dictionary) -> FormData:
	var form := FormData.new()

	var coll: Dictionary = form_json.get("collision", {})
	form.size = Vector2(int(coll.get("width", 16)), int(coll.get("height", 16)))
	form.shape = RectangleShape2D.new()
	form.shape.size = form.size

	var sprites_path: String = form_json.get("spritesPath", "")
	var anims: Dictionary = form_json.get("animations", {})

	form.sprite_frames = SpriteFrames.new()
	if form.sprite_frames.has_animation("default"):
		form.sprite_frames.remove_animation("default")

	for anim_name in anims:
		var cfg: Dictionary = anims[anim_name]
		var frame_count: int = int(cfg.get("frames", 1))
		var fps: float = float(cfg.get("fps", 1.0))
		var loop: bool = bool(cfg.get("loop", false))

		var textures: Array[Texture2D] = []
		var any_real := false
		for i in range(frame_count):
			var tex_path := "%s/%s_%d.png" % [sprites_path, anim_name, i]
			var tex: Texture2D = null
			if ResourceLoader.exists(tex_path):
				tex = load(tex_path) as Texture2D
				if tex != null:
					any_real = true
			textures.append(tex)

		if not any_real:
			continue

		form.sprite_frames.add_animation(anim_name)
		form.sprite_frames.set_animation_speed(anim_name, fps)
		form.sprite_frames.set_animation_loop(anim_name, loop)
		for i in range(frame_count):
			var t: Texture2D = textures[i]
			if t == null:
				t = _placeholder(char_name, form_name, i, form.size)
			form.sprite_frames.add_frame(anim_name, t)
	return form

static func _placeholder(char_name: String, form_name: String, frame_idx: int, size: Vector2) -> ImageTexture:
	var w := int(size.x)
	var h := int(size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var base := _pick_color(char_name, form_name)
	var shade := 0.7 + 0.3 * (float(frame_idx % 3) / 2.0)
	img.fill(Color(base.r * shade, base.g * shade, base.b * shade, 1.0))
	for x in range(w):
		img.set_pixel(x, 0, Color.BLACK)
		img.set_pixel(x, h - 1, Color.BLACK)
	for y in range(h):
		img.set_pixel(0, y, Color.BLACK)
		img.set_pixel(w - 1, y, Color.BLACK)
	return ImageTexture.create_from_image(img)

static func _pick_color(char_name: String, form_name: String) -> Color:
	if char_name == "mario":
		match form_name:
			"small": return Color(0.9, 0.2, 0.2)
			"big":   return Color(0.95, 0.5, 0.2)
			"fire":  return Color(1.0, 0.95, 0.7)
	elif char_name == "goomba":
		return Color(0.5, 0.3, 0.1)
	return Color(0.5, 0.5, 0.5)
