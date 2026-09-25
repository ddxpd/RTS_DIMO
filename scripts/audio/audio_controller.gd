class_name AudioController
extends Node

const SAMPLE_RATE := 44100.0
const Simulation = preload("res://scripts/simulation.gd")

var audio_player: AudioStreamPlayer
var audio_playback: AudioStreamGeneratorPlayback
var audio_effect_frame := -1
var simulation
var local_slot := 1

func configure(value, slot: int) -> void:
    simulation = value
    local_slot = slot

func initialize() -> void:
    var stream := AudioStreamGenerator.new()
    stream.mix_rate      = int(SAMPLE_RATE)
    stream.buffer_length = 1.0
    audio_player         = AudioStreamPlayer.new()
    audio_player.stream  = stream
    add_child(audio_player)
    audio_player.play()
    audio_playback = audio_player.get_stream_playback() as AudioStreamGeneratorPlayback

func set_local_slot(slot: int) -> void:
    local_slot = slot

func play_tone(frequency: float, duration: float, volume: float = 0.16, slide: float = 0.0) -> void:
    if audio_playback == null:
        return
    var frames := mini(int(duration * SAMPLE_RATE), 16000)
    for i in range(frames):
        var t := float(i) / SAMPLE_RATE
        var envelope := minf(1.0, float(i) / 220.0) * minf(1.0, float(frames - i) / 900.0)
        var phase := TAU * (frequency * t + slide * t * t * 0.5)
        var sample := sin(phase) * volume * envelope
        audio_playback.push_frame(Vector2(sample, sample))

func play_attack_sound() -> void:
    play_tone(180.0, 0.055, 0.16, 420.0)

func play_hit_sound() -> void:
    play_tone(78.0, 0.10, 0.20, -25.0)

func consume_effects() -> void:
    if simulation == null:
        return
    for effect: Dictionary in simulation.effects:
        var effect_frame := int(effect.get("frame", -1))
        if effect_frame <= audio_effect_frame or not simulation.can_see(local_slot, effect.to):
            continue
        audio_effect_frame = maxi(audio_effect_frame, effect_frame)
        if effect.kind == "shot":
            play_attack_sound()
        elif effect.kind == "death":
            play_hit_sound()
