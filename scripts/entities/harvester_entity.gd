extends CombatEntity
class_name HarvesterEntity

var cargo := 0

func _init(id: int, faction: int, pos: Vector2, health: int = 160) -> void:
    super(id, faction, pos, health, "harvester")

func get_actions() -> Array[String]:
    return ["stop", "move", "gather"]
