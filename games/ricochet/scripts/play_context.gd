class_name PlayContext
extends RefCounted

# Process-lifetime state passed from the editor (or future main menu) into
# the play scene. Static so we don't need an autoload for one int.
static var start_page_index: int = 0
