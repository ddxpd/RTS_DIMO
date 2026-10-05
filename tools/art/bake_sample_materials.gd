extends SceneTree
## Offline, deterministic, seamless PBR maps. No startup texture generation.

const SIZE := 1024
const DIRECTORY := "res://assets/maps/sample/"


func _initialize() -> void:
    bake.call_deferred()


func field(seed_value: int, frequency: float, cellular: bool = false) -> Image:
    var noise := FastNoiseLite.new()
    noise.seed = seed_value
    noise.frequency = frequency
    noise.fractal_octaves = 3
    if cellular:
        noise.noise_type = FastNoiseLite.TYPE_CELLULAR
        noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
        noise.fractal_type = FastNoiseLite.FRACTAL_NONE
    return noise.get_seamless_image(SIZE, SIZE)


func bake() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
    var names := ["sand", "soil", "gravel", "rock"]
    var palette := [Color("#b9a17b"), Color("#8e775a"), Color("#938574"), Color("#a27e5c")]
    for kind in range(4):
        var broad := field(29531 + kind, 0.012)
        var grain := field(429 + kind, 0.32)
        var cells := field(876 + kind, 0.047 if kind < 2 else 0.10, true)
        var height := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
        var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
        var roughness := PackedFloat32Array()
        roughness.resize(SIZE * SIZE)
        for y in range(SIZE):
            for x in range(SIZE):
                var macro := broad.get_pixel(x, y).r
                var fine := grain.get_pixel(x, y).r
                var cell := cells.get_pixel(x, y).r
                var ripple := sin(TAU * (float(x) * 12.0 + float(y) * 4.0) / SIZE + macro * 3.0)
                var h := 0.5
                var light := 1.0
                match kind:
                    0:
                        h = 0.48 + ripple * 0.035 + (fine - 0.5) * 0.16
                        light = 0.90 + macro * 0.16 + fine * 0.08 + ripple * 0.025
                    1:
                        var crack := smoothstep(0.05, 0.14, cell)
                        h = crack * 0.2 + macro * 0.1 + fine * 0.07
                        light = 0.73 + crack * 0.21 + macro * 0.14 + fine * 0.07
                    2:
                        var pebble := smoothstep(0.11, 0.60, cell)
                        h = pebble * 0.5 + fine * 0.10
                        light = 0.66 + pebble * 0.38 + macro * 0.22 + fine * 0.08
                    3:
                        var crack := smoothstep(0.035, 0.14, cell)
                        var layers := sin(TAU * float(y) * 8.0 / SIZE + macro * 2.0)
                        h = macro * 0.24 + crack * 0.22 + fine * 0.06 + layers * 0.045
                        light = 0.66 + crack * 0.21 + macro * 0.20 + layers * 0.045
                height.set_pixel(x, y, Color(h, h, h, 1))
                albedo.set_pixel(x, y, palette[kind] * light)
                roughness[y * SIZE + x] = clampf(0.78 + fine * 0.15 - (h - 0.5) * 0.1, 0.65, 0.98)
        # Central differences wrap across tile boundaries. RGB=OpenGL normal;
        # alpha=roughness, kept linear by the shader's non-color sampler.
        var normal_roughness := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
        for y in range(SIZE):
            for x in range(SIZE):
                var dx := height.get_pixel((x + 1) % SIZE, y).r - height.get_pixel(posmod(x - 1, SIZE), y).r
                var dy := height.get_pixel(x, (y + 1) % SIZE).r - height.get_pixel(x, posmod(y - 1, SIZE)).r
                var n := Vector3(-dx * 3.5, dy * 3.5, 1).normalized()
                normal_roughness.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, roughness[y * SIZE + x]))
        var error := albedo.save_png(DIRECTORY + names[kind] + "_color.png")
        error |= normal_roughness.save_png(DIRECTORY + names[kind] + "_nr.png")
        if error != OK:
            push_error("Material save failed")
            quit(1)
            return
        print("MATERIAL_BAKED ", names[kind], " 1024x1024 color + normal/roughness")
    quit(0)
