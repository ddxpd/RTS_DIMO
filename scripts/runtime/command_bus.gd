class_name CommandBus
extends RefCounted

signal command_rejected(message: String)

var _sink: Callable

func configure(sink: Callable) -> void:
    _sink = sink

func submit(order: Dictionary) -> void:
    if not _sink.is_valid():
        command_rejected.emit("Command service is unavailable.")
        return
    _sink.call(order)
