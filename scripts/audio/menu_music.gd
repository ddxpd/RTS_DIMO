extends Node
## Front-end-only music. No simulation or transport dependency.

const TRACK_PATH := "res://assets/audio/music/menu_theme.ogg"
const BUS := "MenuMusic"
const LEVEL_DB := -8.0
const FADE_IN := 0.6
const FADE_OUT := 0.4

var player: AudioStreamPlayer
var transition: Tween
var menu_active := false


func _ready() -> void:
    if AudioServer.get_bus_index(BUS) < 0:
        AudioServer.add_bus()
        AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
    player = AudioStreamPlayer.new()
    player.name = "MenuTrack"
    player.bus = BUS
    player.volume_linear = 0.0
    var track := load(TRACK_PATH) as AudioStreamOggVorbis
    if track == null:
        push_error("Menu music could not be loaded: " + TRACK_PATH)
        return
    track = track.duplicate() as AudioStreamOggVorbis
    track.loop = true
    player.stream = track
    add_child(player)


func set_menu_active(value: bool) -> void:
    if menu_active == value or player == null or player.stream == null:
        return
    menu_active = value
    if transition != null and transition.is_valid():
        transition.kill()
    transition = create_tween()
    if value:
        # Returning during a fade reverses it without creating another voice.
        if not player.playing:
            player.volume_linear = 0.0
            player.play()
        transition.tween_property(player, "volume_linear", db_to_linear(LEVEL_DB), FADE_IN)
    else:
        transition.tween_property(player, "volume_linear", 0.0, FADE_OUT)
        transition.tween_callback(player.stop)


func _exit_tree() -> void:
    if transition != null and transition.is_valid():
        transition.kill()
    if player != null:
        player.stop()
        player.stream = null
