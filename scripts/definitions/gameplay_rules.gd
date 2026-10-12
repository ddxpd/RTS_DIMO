extends RefCounted
## Shared by simulation, validation and the read-only balance export.
const CAPACITY := 60
const MINING_INTERVAL := 20
const MINING_AMOUNT := 10
const MINING_REACH := 74.0
const BUILD_REACH := 360
const QUEUE_LIMIT := 5
const DOCK_RETRY := 100
# Temporary exterior stops leave clearance between the unchanged large vehicles.
const DOCK_OFFSET := 52
const DOCK_DEPTH := -116
const DOCK_ENTRANCE := -192
const VISION := 340.0
