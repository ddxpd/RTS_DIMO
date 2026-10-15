extends RefCounted
## Shared, validated lobby contract. Owner IDs stay stable when seats are closed.
const OWNERS := [1, 2, 3, 4]
const COLORS := [Color("#5fa5e0"), Color("#d66551"), Color("#67df92"), Color("#d697ff")]

static func defaults(training: bool = false) -> Dictionary:
    return {"map": "desert_sample" if training else "frontier_four", "training": training,
        "mode": "ffa", "funds": 10000 if training else 6000,
        "seats": ["human", "closed" if training else "ai", "closed", "closed"],
        "teams": [1, 2, 1, 2]}

static func error(config: Dictionary, starting: bool = false) -> String:
    if config.size() != 6 or not config.get("map") is String or not config.get("training") is bool:
        return "Invalid match configuration."
    if config.get("mode") not in ["ffa", "2v2"] or not config.get("funds") is int or config.funds < 1 or config.funds > 1000000:
        return "资金须为 1–1,000,000 的整数。"
    if not config.get("seats") is Array or config.seats.size() != 4 or not config.get("teams") is Array or config.teams.size() != 4:
        return "房间需要四个席位。"
    var occupied := 0
    var counts := {1: 0, 2: 0}
    for i in range(4):
        if config.seats[i] not in ["human", "ai", "open", "closed"] or config.teams[i] not in [1, 2]:
            return "Invalid seat or team."
        if config.seats[i] in ["human", "ai"]:
            occupied += 1
            counts[config.teams[i]] += 1
        if starting and config.seats[i] == "open":
            return "请补充 AI 或关闭空位。"
    if config.map not in ["desert_quarry", "desert_sample", "frontier_four"]:
        return "Unknown map."
    if not config.training and config.map == "desert_sample":
        return "训练地图只用于训练场。"
    if config.map in ["desert_quarry", "desert_sample"] and (config.seats[2] != "closed" or config.seats[3] != "closed"):
        return "此地图最多支持两个席位，请选择四人地图。"
    if starting and occupied < (1 if config.training else 2):
        return "对战至少需要两个参战席位。"
    if starting and config.mode == "2v2" and (counts[1] != 2 or counts[2] != 2):
        return "2v2 需要每队两个席位。"
    return ""

static func color(owner: int) -> Color:
    return COLORS[clampi(owner - 1, 0, 3)]
