extends RefCounted

const REVISION := 1
const KINDS := ["sand", "gravel", "plateau", "ramp", "quarry", "rock"]

# Returns height, x/z gradients, buildability, material and movement permission.
# Quarter turns rotate both geometry and its gameplay data.
static func sample(module: Dictionary, world: Vector2) -> Dictionary:
    var size: Vector2 = module.size
    var local: Vector2 = world - (module.position as Vector2)
    var turns := int(module.get("rotation", 0))
    if turns == 1:
        local = Vector2(local.y, size.x - local.x)
        size = Vector2(size.y, size.x)
    elif turns == 2:
        local = size - local
    elif turns == 3:
        local = Vector2(size.y - local.y, local.x)
        size = Vector2(size.y, size.x)
    var h := float(module.get("height", 0.0))
    var gradient := Vector2.ZERO
    var buildable := true
    var passable := true
    var material := 0
    match str(module.kind):
        "sand":
            h = 0.0
        "gravel":
            h = 0.0
            material = 1
        "plateau":
            var corner := Vector2(minf(local.x, size.x - local.x), minf(local.y, size.y - local.y))
            if corner.x + corner.y < 128.0:
                h = 0.0
            material = 1
        "ramp":
            gradient.x = h / size.x
            h *= local.x / size.x
            buildable = false
            material = 2
        "quarry":
            var rim := minf(minf(local.x, size.x - local.x), minf(local.y, size.y - local.y))
            var corner := Vector2(minf(local.x, size.x - local.x), minf(local.y, size.y - local.y))
            rim = minf(rim, (corner.x + corner.y - 128.0) * 0.7071)
            h = 0.0 if rim < 0.0 else (-48.0 if rim < 96.0 else -96.0)
            if absf(local.y - size.y * 0.5) < 96.0 and local.x < 384.0:
                h = -96.0 * local.x / 384.0
                gradient.x = -0.25
                buildable = false
            material = 1
        "rock":
            buildable = false
            passable = false
            material = 3
    gradient = gradient.rotated(turns * PI * 0.5)
    return {"height": h, "gradient": gradient, "buildable": buildable, "passable": passable, "material": material}
