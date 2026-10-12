extends RefCounted

const DESERT = preload("res://assets/maps/desert_quarry.tres")
const SAMPLE = preload("res://assets/maps/desert_sample.tres")
const IDS := ["desert_quarry", "desert_sample"]

static func definition(id: String) -> Dictionary:
    if id == "desert_sample":
        return SAMPLE.data.duplicate(true)
    if id == "desert_quarry":
        return DESERT.data.duplicate(true)
    return {}
