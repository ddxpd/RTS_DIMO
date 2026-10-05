extends RefCounted
# Procedural ground texture used by the 3D prototype map.

static func terrain_image() -> Image:
    var img := Image.create(48, 16, false, Image.FORMAT_RGB8)
    for tile in range(3):
        for y in range(16):
            for x in range(16):
                var colors := [Color("#394936"), Color("#3e5039"), Color("#425238")]
                var col: Color = colors[tile]
                if (x * x * 31 + y * y * 19 + x * y * 17 + tile * 7) % 53 == 0:
                    col = col.lightened(0.12)
                img.set_pixel(tile * 16 + x, y, col)
    return img
