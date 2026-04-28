class_name ArtStyle
extends RefCounted

# Active art style is read from GameState.art_style.
# When the active style is missing an asset, fall back to FALLBACK_STYLE
# so partially-built styles still work end-to-end.
const ROOT := "res://sprites"
const FALLBACK_STYLE := "default"

static func path(rel: String) -> String:
	var primary := "%s/%s/%s" % [ROOT, GameState.art_style, rel]
	if ResourceLoader.exists(primary):
		return primary
	return "%s/%s/%s" % [ROOT, FALLBACK_STYLE, rel]
