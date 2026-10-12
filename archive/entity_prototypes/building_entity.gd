extends GameEntity
class_name BuildingEntity

var production_queue: Array = []

func queue_production(kind: String) -> void:
    production_queue.append(kind)

func get_actions() -> Array[String]:
    return ["stop", "build_barracks", "build_base"]
