extends BuildingEntity
class_name BarracksEntity
func _init(id: int, faction: int, pos: Vector2, health: int=420) -> void: super(id,faction,pos,health,"barracks")
func get_actions() -> Array[String]: return ["stop", "train_soldier", "build_barracks", "build_base"]
