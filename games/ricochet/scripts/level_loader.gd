class_name LevelLoader
extends RefCounted

# Parses a Ricochet level JSON file. Schema v1:
#   {
#     "id":   string,
#     "name": string,
#     "exit": { "page": int, "x": int, "y": int },     # one per level
#     "pages": [
#       {
#         "tiles":     [ "WWWW...", ... ],              # W=wall, .=empty
#         "spawn":     { "x": int, "y": int },          # one per page
#         "teleports": [ { "x": int, "y": int, "target_page": int }, ... ]
#       },
#       ...
#     ]
#   }
# Returns the parsed Dictionary, or {} on failure (errors logged).

static func load_level(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[level_loader] file not found: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[level_loader] could not open: %s" % path)
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[level_loader] not a JSON object: %s" % path)
		return {}
	if not data.has("pages") \
			or typeof(data.pages) != TYPE_ARRAY \
			or (data.pages as Array).is_empty():
		push_error("[level_loader] level must have a non-empty 'pages' array: %s" % path)
		return {}
	return data
