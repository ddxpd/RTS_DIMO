extends SceneTree

func _initialize() -> void:
    var paths := OS.get_cmdline_user_args()
    if paths.is_empty():
        print("Pass a project-local snapshot pair .bin after --")
        quit(2)
        return
    for argument in paths:
        if not argument.ends_with(".bin"):
            continue
        var file := FileAccess.open(argument, FileAccess.READ)
        var pair: Array = file.get_var()
        file.close()
        print("NETWORK_STATE_AUDIT ", argument)
        compare(pair[0], pair[1], "")
    quit()

func compare(expected: Variant, actual: Variant, path: String) -> void:
    if expected == actual:
        return
    if expected is Dictionary and actual is Dictionary:
        for key in expected:
            compare(expected[key], actual.get(key), path + "/" + str(key))
        for key in actual:
            if not expected.has(key):
                print(path + "/" + str(key), " unexpected=", actual[key])
    else:
        print(path, " expected=", str(expected).left(700), " actual=", str(actual).left(700))
