extends BuildingEntity
class_name BaseEntity
func _init(id: int, faction: int, pos: Vector2, health: int=800) -> void: super(id,faction,pos,health,"base")
func get_actions() -> Array[String]: return ["stop", "train_harvester", "build_barracks", "build_base"]
