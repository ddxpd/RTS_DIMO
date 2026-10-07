extends RefCounted

var player: AnimationPlayer
var wind: AnimationPlayer
var body: Node3D
var visual: Node3D
var last_clip := ""
var last_time := -1.0


func _init(owner_visual: Node3D) -> void:
    visual = owner_visual
    body = visual.model.find_child("BarracksMechanicalV2", true, false)
    if body == null:
        body = visual.model
    var players: Array[Node] = visual.model.find_children("*", "AnimationPlayer", true, false)
    player = players[0] as AnimationPlayer
    var library := AnimationLibrary.new()
    for clip: String in ["Takeoff", "Landing"]:
        var animation := player.get_animation(clip).duplicate() as Animation
        for index in range(animation.get_track_count() - 1, -1, -1):
            var path := animation.track_get_path(index)
            var node := player.get_node(player.root_node).get_node_or_null(NodePath(str(path).get_slice(":", 0)))
            if node == body:
                animation.remove_track(index)
        library.add_animation(clip, animation)
    # Godot's scene importer consumes the _Loop naming suffix; GLTFDocument does not.
    var flag_name := "Flag_Wind_Loop" if player.has_animation("Flag_Wind_Loop") else "Flag_Wind"
    var flag := player.get_animation(flag_name)
    for name in player.get_animation_library_list():
        player.remove_animation_library(name)
    player.add_animation_library("", library)
    wind = AnimationPlayer.new()
    player.get_parent().add_child(wind)
    wind.root_node = player.root_node
    var flag_library := AnimationLibrary.new()
    flag = flag.duplicate()
    # Scene import inserts rest-pose tracks for nodes absent from a GLB clip.
    # A wind player must never reset the mechanical player's nodes each frame.
    for index in range(flag.get_track_count() - 1, -1, -1):
        if flag.track_get_type(index) != Animation.TYPE_BLEND_SHAPE:
            flag.remove_track(index)
    flag.loop_mode = Animation.LOOP_LINEAR
    flag_library.add_animation("wind", flag)
    wind.add_animation_library("", flag_library)
    wind.play("wind")
    body.position = Vector3.ZERO
    apply({"state": "grounded", "ticks": 0})


func apply(flight: Dictionary, fractional_ticks: float = 0.0) -> void:
    var state: String = flight.get("state", "grounded")
    var clip := "Landing" if state == "landing" else "Takeoff"
    var time := clampf((float(flight.get("ticks", 0)) + fractional_ticks) / 20.0, 0, 4)
    if state == "grounded":
        time = 0
    elif state == "airborne":
        time = 4
    if clip == last_clip and is_equal_approx(time, last_time):
        return
    player.play(clip)
    player.seek(time, true)
    player.pause()
    body.position = Vector3.ZERO
    last_clip = clip
    last_time = time
