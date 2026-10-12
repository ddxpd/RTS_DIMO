extends RefCounted
## Canonical gameplay definitions; includes retired assets for explicit preview fixtures.
const CELL = preload("res://scripts/world_grid.gd").CELL
const WEAPON_TARGETS := {"soldier": ["ground"], "mobile_infantry": ["ground"], "bunker": ["ground"]}
const EYE_HEIGHTS := {"soldier": 40.0, "mobile_infantry": 40.0, "harvester": 32.0, "base": 80.0, "barracks": 40.0, "refinery": 56.0, "bunker": 48.0}
const ACTIVE_UNIT_TYPES := ["mobile_infantry", "harvester"]
const UNIT_TYPES := {
    "mobile_infantry": {"hp": 100, "speed": 100.0, "range": 125.0, "damage": 16, "cooldown": 12, "radius": 0.375 * CELL, "cost": 100, "time": 50},
    "soldier": {"hp": 100, "speed": 100.0, "range": 125.0, "damage": 16, "cooldown": 12, "radius": 16.0, "cost": 100, "time": 50},
    "harvester": {"hp": 160, "speed": 75.0, "range": 0.0, "damage": 0, "cooldown": 20, "radius": 48.0, "cost": 200, "time": 70}
}
const BUILD_CELLS := {"base": Vector2i(10, 6), "barracks": Vector2i(4, 3), "refinery": Vector2i(4, 4), "bunker": Vector2i(2, 2)}
const REFINERY_DOCK_RECTS := [Rect2(Vector2(-2, -2) * CELL, Vector2(1, 2) * CELL), Rect2(Vector2(1, -2) * CELL, Vector2(1, 2) * CELL)]
const REFINERY_SOLID_RECTS := [Rect2(Vector2(-2, 0) * CELL, Vector2(4, 2) * CELL), Rect2(Vector2(-1, -2) * CELL, Vector2(2, 2) * CELL)]
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
    "refinery": "矿石卸载站",
    "bunker": "地堡",
    "shared": "公共规则"
}
const DESCRIPTIONS := {
    "soldier": "地面远程步兵。攻击带有可见弹道。",
    "mobile_infantry": "地面远程单位。攻击立即在目标上呈现命中效果。",
    "harvester": "以地面单位规则移动，外观悬浮。采矿时作业爪运动，货仓按载量分阶段变化；卸货无需倾倒动画。",
    "base": "GAIA 指挥基地，为周围建筑部署提供起点。本身不生产单位。",
    "barracks": "生产机动兵。可起飞迁移，落地后恢复地面建筑功能。",
    "refinery": "生产采集作业机，提供双泊位卸矿。进入、卸货、退出期间占用泊位。模型中央矿仓为固定展示，不代表玩家库存。",
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
