extends RefCounted
class_name GameEntity

var entity_id: int
var owner: int
var position: Vector2
var hp: int
var max_hp: int
var entity_type: String
var destroyed := false

func _init(id: int, faction: int, pos: Vector2, health: int, kind: String) -> void:
    entity_id = id
    owner = faction
    position = pos
    hp = health
    max_hp = health
    entity_type = kind

func take_damage(amount: int) -> void:
    if destroyed:
        return
    hp = maxi(0, hp - amount)
    if hp == 0:
        destroy()

func destroy() -> void:
    destroyed = true

func is_alive() -> bool:
    return not destroyed and hp > 0

func get_actions() -> Array[String]:
    return []
