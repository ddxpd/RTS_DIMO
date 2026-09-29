extends SceneTree
## Mechanical alpha-preserving packaging of imagegen cutouts; no redrawing.
const STATES := ["default", "select", "move", "attack", "blocked"]
const SOURCE_HOTSPOTS := {
    "default": Vector2(0.187, 0.090),
    "select": Vector2(0.290, 0.265),
    "move": Vector2(0.312, 0.287),
    "attack": Vector2(0.500, 0.489),
    "blocked": Vector2(0.353, 0.246)
}


func _initialize() -> void:
    var output := "res://assets/ui/cursors"
    DirAccess.make_dir_recursive_absolute(output)
    for state: String in STATES:
        var source := Image.load_from_file("res://assets/concept_art/cursor-source-%s.png" % state)
        if source == null or not source.detect_alpha():
            push_error("Missing transparent source: " + state)
            quit(1)
            return
        source.convert(Image.FORMAT_RGBA8)
        # Ignore imperceptible alpha specks outside the actual generated glyph.
        var lower := source.get_size()
        var upper := Vector2i.ZERO
        for y in range(source.get_height()):
            for x in range(source.get_width()):
                if source.get_pixel(x, y).a >= 0.2:
                    lower = lower.min(Vector2i(x, y))
                    upper = upper.max(Vector2i(x, y))
        var bounds := Rect2i(lower, upper - lower + Vector2i.ONE)
        var glyph := source.get_region(bounds)
        var limit := 30.0 if state == "default" else 38.0
        var ratio := limit / float(maxi(bounds.size.x, bounds.size.y))
        var size := Vector2i(Vector2(bounds.size) * ratio)
        glyph.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
        var canvas := Image.create(40, 40, false, Image.FORMAT_RGBA8)
        canvas.fill(Color.TRANSPARENT)
        var offset := (Vector2i(40, 40) - size) / 2
        canvas.blit_rect(glyph, Rect2i(Vector2i.ZERO, size), offset)
        var hotspot: Vector2 = Vector2(offset) + (SOURCE_HOTSPOTS[state] * Vector2(source.get_size()) - Vector2(bounds.position)) * ratio
        if state == "attack":
            hotspot = Vector2(20, 20)
        var error := canvas.save_png(output.path_join(state + ".png"))
        if error != OK:
            quit(1)
            return
        print("CURSOR_ASSET ", state, " source=", source.get_size(), " bounds=", bounds, " hotspot=", hotspot.round(), " alpha=", canvas.detect_alpha())
    quit(0)
