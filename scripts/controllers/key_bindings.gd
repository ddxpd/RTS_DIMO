extends RefCounted
## Local keyboard preferences. Stable action IDs also drive command-card labels.
signal changed

const MODIFIERS := KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_MASK_ALT
const BASE_KEYS := [
    ["menu", "菜单 / 取消", KEY_ESCAPE],
    ["attack", "攻击", KEY_A], ["stop", "停止", KEY_S],
    ["move", "移动", KEY_M], ["gather", "采矿", KEY_G],
    ["barracks", "建造兵营", KEY_B], ["refinery", "建造冶炼场", KEY_F],
    ["bunker", "建造地堡", KEY_N], ["base", "建造基地", KEY_H],
    ["mobile_infantry", "训练机动兵", KEY_T], ["harvester", "生产作业机", KEY_U],
    ["cancel", "取消最后一项生产", KEY_C],
    ["takeoff", "起飞", KEY_L], ["deploy", "部署", KEY_D],
    ["rally", "设置集结点", KEY_R], ["clear_rally", "清除集结点", KEY_R | KEY_MASK_SHIFT],
    ["cycle_building", "切换选中建筑", KEY_TAB],
    ["camera_up", "镜头向上", KEY_UP], ["camera_down", "镜头向下", KEY_DOWN],
    ["camera_left", "镜头向左", KEY_LEFT], ["camera_right", "镜头向右", KEY_RIGHT],
    ["zoom_in", "拉近镜头", KEY_PAGEUP], ["zoom_out", "拉远镜头", KEY_PAGEDOWN]
]
var defaults := {}
var titles := {}
var bindings := {}
var settings_path := "user://settings.cfg"
var load_error := ""


func _init() -> void:
    for item in BASE_KEYS:
        defaults[item[0]] = int(item[2])
        titles[item[0]] = item[1]
    for group in range(1, 10):
        for item in [["recall", "调用", 0], ["assign", "创建", KEY_MASK_CTRL], ["append", "追加", KEY_MASK_SHIFT]]:
            var id := "group_%s_%d" % [item[0], group]
            defaults[id] = (KEY_0 + group) | int(item[2])
            titles[id] = "%s编队 %d" % [item[1], group]
    bindings = defaults.duplicate()


static func chord(event: InputEventKey) -> int:
    var key := int(event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode)
    return key | (KEY_MASK_CTRL if event.ctrl_pressed else 0) | (KEY_MASK_SHIFT if event.shift_pressed else 0) | (KEY_MASK_ALT if event.alt_pressed else 0) | (KEY_MASK_META if event.meta_pressed else 0)


static func invalid_reason(value: int, action: String) -> String:
    var key := value & KEY_CODE_MASK
    if key in [KEY_NONE, KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META] or OS.get_keycode_string(key).is_empty():
        return "请选择一个普通按键，可组合 Ctrl / Shift / Alt。"
    if value & ~(KEY_CODE_MASK | MODIFIERS) != 0 or key in [KEY_PRINT, KEY_SYSREQ]:
        return "该组合由系统保留。"
    if key == KEY_ESCAPE and (action != "menu" or value != KEY_ESCAPE):
        return "Esc 保留为安全返回键。"
    if (key == KEY_F4 and value & KEY_MASK_ALT) or (key == KEY_TAB and value & KEY_MASK_ALT) or (key == KEY_DELETE and value & KEY_MASK_CTRL and value & KEY_MASK_ALT):
        return "该组合由系统保留。"
    return ""


func label(action: String, default_value: bool = false) -> String:
    return OS.get_keycode_string(int((defaults if default_value else bindings).get(action, 0)))


func action_for(event: InputEventKey) -> String:
    var value := chord(event)
    for action: String in bindings:
        if int(bindings[action]) == value:
            return action
    return ""


func rebind(action: String, value: int) -> String:
    if not bindings.has(action):
        return "未知操作。"
    var error := invalid_reason(value, action)
    if not error.is_empty():
        return error
    for other: String in bindings:
        if other != action and int(bindings[other]) == value:
            return "按键已被「%s」占用。" % titles[other]
    var previous: int = bindings[action]
    bindings[action] = value
    if save_settings() != OK:
        bindings[action] = previous
        return "保存失败，已保留原来的按键。"
    changed.emit()
    return ""


func reset_all() -> String:
    var previous := bindings
    bindings = defaults.duplicate()
    if save_settings() != OK:
        bindings = previous
        return "保存失败，未更改按键。"
    changed.emit()
    return "已恢复全部默认按键。"


func save_settings() -> Error:
    var config := ConfigFile.new()
    config.load(settings_path)
    for action: String in bindings:
        config.set_value("keybindings", action, bindings[action])
    return config.save(settings_path)


func load_settings() -> void:
    var config := ConfigFile.new()
    if config.load(settings_path) != OK:
        return
    var candidate := defaults.duplicate()
    var used := {}
    for action: String in defaults:
        var value = config.get_value("keybindings", action, defaults[action])
        if not value is int or not invalid_reason(int(value), action).is_empty() or used.has(value):
            load_error = "按键配置无效或重复，本次使用默认配置。"
            bindings = defaults.duplicate()
            return
        candidate[action] = value
        used[value] = true
    bindings = candidate


func held(action: String) -> bool:
    var value: int = bindings[action]
    return Input.is_physical_key_pressed(value & KEY_CODE_MASK) and Input.is_key_pressed(KEY_CTRL) == bool(value & KEY_MASK_CTRL) and Input.is_key_pressed(KEY_SHIFT) == bool(value & KEY_MASK_SHIFT) and Input.is_key_pressed(KEY_ALT) == bool(value & KEY_MASK_ALT) and not Input.is_key_pressed(KEY_META)


func camera_direction() -> Vector2:
    return Vector2(float(held("camera_right")) - float(held("camera_left")), float(held("camera_down")) - float(held("camera_up"))).limit_length()
