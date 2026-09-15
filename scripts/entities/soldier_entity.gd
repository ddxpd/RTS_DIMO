extends CombatEntity
class_name SoldierEntity
func _init(id: int, faction: int, pos: Vector2, health: int=100) -> void: super(id,faction,pos,health,"soldier",125.0,16)
func get_actions() -> Array[String]: return ["stop", "move", "attack"]
