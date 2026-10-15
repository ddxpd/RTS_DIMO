extends RefCounted
## Shared by simulation, validation and the read-only balance export.
const CAPACITY := 60
const MINING_INTERVAL := 20
const MINING_AMOUNT := 10
const MINING_REACH := 74.0
const MINING_CONTACT_RADIUS := 36.0
const BUILD_REACH := 360
const QUEUE_LIMIT := 5
const DOCK_RETRY := 100
const Catalog = preload("res://scripts/definitions/entity_catalog.gd")
# Compatibility names for the read-only encyclopedia; derived from geometry.
const DOCK_OFFSET := -Catalog.REFINERY_SIZE.x * 0.25
const DOCK_DEPTH := -Catalog.REFINERY_SIZE.y * 0.25
const DOCK_ENTRANCE := -Catalog.REFINERY_SIZE.y * 0.5 - Catalog.HARVESTER_RADIUS - Catalog.BODY_GAP
const VISION := 340.0
