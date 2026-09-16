extends GameEntity
class_name CombatEntity
var attack_range: float
var attack_damage: int
func _init(id: int, faction: int, pos: Vector2, health: int, kind: String, range_value: float=0.0, damage_value: int=0) -> void:
    super(id, faction, pos, health, kind)\n    attack_range = range_value\n    attack_damage = damage_value
func can_attack() -> bool: return attack_damage > 0 and attack_range > 0.0

