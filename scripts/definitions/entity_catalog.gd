extends RefCounted
## Canonical gameplay definitions; includes retired assets for explicit preview fixtures.
const CELL = preload("res://scripts/world_grid.gd").CELL
const HARVESTER_RADIUS := CELL
const HARVESTER_VISUAL_RADIUS := CELL * 0.9
# Folded idle/move mesh radius measures 2.026; keep a small pose margin.
const HARVESTER_SOURCE_RADIUS := 2.05
const HARVESTER_MODEL_SCALE := HARVESTER_VISUAL_RADIUS / HARVESTER_SOURCE_RADIUS
const HARVESTER_HEIGHT := 2.52 * HARVESTER_MODEL_SCALE
const BODY_GAP := CELL * 0.125
const HARVESTER_TURN_RATE := TAU # Radians per second; a half-turn takes 0.5 s.
const BARRACKS_DOOR_X_FRACTION := 0.0965625
const WEAPON_TARGETS := {"soldier": ["ground"], "mobile_infantry": ["ground"], "bunker": ["ground"]}
const EYE_HEIGHTS := {"soldier": 40.0, "mobile_infantry": 40.0, "harvester": HARVESTER_HEIGHT * 0.73, "base": 80.0, "barracks": 40.0, "refinery": 56.0, "bunker": 48.0}
const ACTIVE_UNIT_TYPES := ["mobile_infantry", "harvester"]
const UNIT_TYPES := {
    "mobile_infantry": {"hp": 100, "speed": 100.0, "range": 125.0, "damage": 16, "cooldown": 12, "radius": 0.375 * CELL, "cost": 100, "time": 50},
    "soldier": {"hp": 100, "speed": 100.0, "range": 125.0, "damage": 16, "cooldown": 12, "radius": 16.0, "cost": 100, "time": 50},
    "harvester": {"hp": 160, "speed": 75.0, "range": 0.0, "damage": 0, "cooldown": 20, "radius": HARVESTER_RADIUS, "cost": 200, "time": 70}
}
const BUILD_CELLS := {"base": Vector2i(10, 6), "barracks": Vector2i(4, 3), "refinery": Vector2i(4, 4), "bunker": Vector2i(2, 2)}
const REFINERY_SIZE := Vector2(BUILD_CELLS.refinery) * CELL
const REFINERY_SOURCE_SIZE := Vector2(6.4, 6.4)
const REFINERY_MODEL_SCALE := 20.0
const REFINERY_DECK_HEIGHT := 0.18 * REFINERY_MODEL_SCALE
# Facing the receiver from the front (-Z), screen-right is local -X.
const REFINERY_DOCK_RECTS := [Rect2(REFINERY_SIZE * Vector2(-0.5, -0.5), REFINERY_SIZE * 0.5)]
const REFINERY_SOLID_RECTS := [Rect2(REFINERY_SIZE * Vector2(-0.5, 0), REFINERY_SIZE * Vector2(1, 0.5)), Rect2(REFINERY_SIZE * Vector2(0, -0.5), REFINERY_SIZE * 0.5)]
const BUILD_TYPES := {
    "base": {"hp": 800, "size": Vector2(BUILD_CELLS.base) * CELL, "cost": 500, "time": 140},
    "barracks": {"hp": 420, "size": Vector2(BUILD_CELLS.barracks) * CELL, "cost": 250, "time": 80},
    "refinery": {"hp": 600, "size": Vector2(BUILD_CELLS.refinery) * CELL, "cost": 400, "time": 100},
    "bunker": {"hp": 500, "size": Vector2(BUILD_CELLS.bunker) * CELL, "cost": 300, "time": 120, "range": 190.0, "damage": 14, "cooldown": 14}
}
const NAMES := {
    "soldier": "士兵",
    "mobile_infantry": "机动兵",
    "harvester": "悬浮采集作业机",
    "base": "指挥基地",
    "barracks": "兵营",
    "refinery": "矿石冶炼场",
    "bunker": "地堡",
    "shared": "公共规则"
}
const DESCRIPTIONS := {
    "soldier": "地面远程步兵。攻击带有可见弹道。",
    "mobile_infantry": "地面远程单位。攻击立即在目标上呈现命中效果。",
    "harvester": "以地面单位规则移动，外观悬浮，作业车之间始终允许重叠。采矿时作业爪运动，开放式低护栏货盘按载量分阶段显示矿石；支持同时交矿，无需倾倒动画。",
    "base": "GAIA 指挥基地，可起飞迁移并重新部署；部署后提供周围建造范围。本身不生产单位。",
    "barracks": "生产机动兵。可起飞迁移，落地后恢复地面建筑功能。",
    "refinery": "生产采集作业机。总占地4×4格，右前方2×2格为可通行卸载区，其余12格阻挡。作业车可重叠并同时交矿，无需排队。矿仓为固定展示，不代表玩家库存。",
    "bunker": "自动攻击地面目标的防御建筑。",
    "shared": "当前已实现的采矿、卸矿、生产与视野规则。修改仅作用于当前草案。"
}
const PRODUCERS := {
    "mobile_infantry": "barracks",
    "soldier": "barracks",
    "harvester": "refinery"
}


static func produced_by(building: String) -> Array[String]:
    var result: Array[String] = []
    for kind: String in ACTIVE_UNIT_TYPES:
        if PRODUCERS.get(kind) == building:
            result.append(kind)
    return result


static func dock_fit(radius: float = HARVESTER_RADIUS, size: Vector2 = REFINERY_SIZE) -> bool:
    return radius > 0 and radius * 2 <= minf(size.x, size.y) * 0.5


static func dock_point(slot: int, outside: bool, radius: float = HARVESTER_RADIUS, size: Vector2 = REFINERY_SIZE) -> Vector2:
    assert(slot >= 0 and slot < REFINERY_DOCK_RECTS.size() and dock_fit(radius, size), "Vehicle does not fit the unloading pad")
    return Vector2(-size.x * 0.25, -size.y * 0.5 - radius - BODY_GAP if outside else -size.y * 0.25)
