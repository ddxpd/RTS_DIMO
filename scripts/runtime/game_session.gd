class_name GameSession
extends Node

signal simulation_tick(previous_winner: int, current_winner: int)

const Simulation = preload("res://scripts/simulation.gd")

var simulation
var accumulator := 0.0

func configure(value) -> void:
    simulation = value

func reset_clock() -> void:
    accumulator = 0.0

func advance(delta: float, active: bool, host_mode: bool, connected: bool) -> int:
    if simulation == null or not active or (connected and not host_mode):
        return 0

    accumulator += minf(delta, 0.25)
    var steps := 0
    while accumulator >= 0.05:
        accumulator -= 0.05
        var previous_winner: int = simulation.winner
        simulation.step()
        simulation_tick.emit(previous_winner, simulation.winner)
        steps += 1
    return steps
