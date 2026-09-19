extends RefCounted
# Small original pixel sprites generated from authored pixel masks, no external assets.
static func texture(rows: Array, team: Color) -> ImageTexture:
    var img := Image.create(str(rows[0]).length(), rows.size(), false, Image.FORMAT_RGBA8)
    var palette := {".": Color.TRANSPARENT, "x": Color("#101b22"), "t": team, "s": team.darkened(0.35),
        "w": Color("#d8e8d9"), "g": Color("#566551"), "d": Color("#303e36"), "y": Color("#e5b94b"), "b": Color("#73d8d2")}
    for y in range(rows.size()):
        for x in range(str(rows[y]).length()):
            img.set_pixel(x, y, palette.get(str(rows[y])[x], Color.MAGENTA))
    return ImageTexture.create_from_image(img)

static func sprites(team: Color) -> Dictionary:
    return {
        "soldier": texture(["....xxxx....", "...xttttx...", "...xttttx...", "....xwwx....", "...xssssx...", "..xttttttx..", "..xstttsx...", "..xxsssx....", "....xgxx....", "...xggxgx...", "...xxx.xx...", "............"], team),
        "harvester": texture(["..xxxxxxxx..", ".xggggggggx.", "xxttttttttxx", "xsttyyyyttsx", "xsttyyyyttsx", "xsttyyyyttsx", "xsttssss ttx".replace(" ", "s"), "xsttbbbbttsx", "xsttbbbbttsx", "xxttttttttxx", ".xggggggggx.", "..xxxxxxxx.."], team),
        "base": texture(["......xxxx......", "......xyyx......", "...xxxxxxxxxx...", "..xttttttttttx..", ".xttttttttttttx.", "xttttttttttttttx", "xssssssssssssssx", "xgwwgwwggwwgwwgx", "xgwwgwwggwwgwwgx", "xggggggggggggggx", "xgggxxxxxxxxgggx", "xgggxddddddxgggx", "xgggxddddddxgggx", "xgggxddddddxgggx", "xxxxxxxxxxxxxxxx", ".dddddddddddddd."], team),
        "barracks": texture(["................", ".....xx.........", ".....xtyxx......", ".....xtttyx.....", ".....xx.........", "..xxxxxxxxxxxx..", ".xttttttttttttx.", "xttttttttttttttx", "xssssssssssssssx", "xggwwggggggwwggx", "xggwwgxxxxgwwggx", "xgggggxddxgggggx", "xgggggxddxgggggx", "xgggggxddxgggggx", "xxxxxxxxxxxxxxxx", ".dddddddddddddd."], team),
        "bunker": texture(["................", "......xtx.......", ".....xtttx......", ".....xtttx......", "......xxx.......", "..xxxxxxxxxxxx..", ".xggggggggggggx.", "xggwwggggggwwggx", "xggwwggxxggwwggx", "xgggggxxxxgggggx", "xgggggxxxxgggggx", "xggggggggggggggx", "xgggxxxxxxxxgggx", "xxxxxxxxxxxxxxxx", ".dddddddddddddd.", "................"], team),
        "refinery": texture(["................", "....x...........", "...xyy..........", "...xyyx.........", "...xyyyyx.......", "...xyyyyyx......", "..xxyyyyyyx.....", ".xyyxxxyyyx.....", "xyyxttxyyx......", "xyyxttxyx.......", "xyyxttxxyx......", "xyyyxxyyyx......", ".xyyyyyyx.......", "..xxxxxx........", "................", "................"], team),
        "ore": texture(["................", ".....yy.........", "....ywwy..yy....", "..yywyywy.ywy...", ".ywwyyyyyywwy...", ".yywyyyywyyyyy..", "..yyyywwyyyywy..", ".ywwyyyyywwyyy..", "..yyyywwyyyyy...", "...yyyyyyyy.....", ".....dddd.......", "................"], team),
        "rock": texture(["....xxxxx.......", "..xxgggggxxx....", ".xggwwggggggx...", "xggwwggggggggx..", "xgggggggggggggx.", "xgggggggggggggx.", ".xggggggggggggx.", "..xggggggggggx..", "...xxddddddxx...", ".....xxxxxx.....", "................", "................"], team)
    }

static func terrain() -> TileSet:
    var img := Image.create(48, 16, false, Image.FORMAT_RGBA8)
    for tile in range(3):
        for y in range(16):
            for x in range(16):
                var colors := [Color("#394936"), Color("#3e5039"), Color("#425238")]
                var col: Color = colors[tile]
                if (x * x * 31 + y * y * 19 + x * y * 17 + tile * 7) % 53 == 0:
                    col = col.lightened(0.12)
                img.set_pixel(tile * 16 + x, y, col)
    var source := TileSetAtlasSource.new()
    source.texture = ImageTexture.create_from_image(img)
    source.texture_region_size = Vector2i(16, 16)
    for i in range(3):
        source.create_tile(Vector2i(i, 0))
    var tiles := TileSet.new()
    tiles.tile_size = Vector2i(16, 16)
    tiles.add_source(source, 0)
    return tiles
