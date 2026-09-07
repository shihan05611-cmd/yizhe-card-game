extends Node

const RunContractScript = preload("res://systems/roguelike/run_contract.gd")

signal state_changed(snapshot: Dictionary)

var _state: Dictionary = RunContractScript.create()


func reset_run(errors: Array[String] = []) -> bool:
	if not RunContractScript.reset(_state, errors):
		return false
	state_changed.emit(RunContractScript.snapshot(_state))
	return true


func snapshot(errors: Array[String] = []) -> Dictionary:
	return RunContractScript.snapshot(_state, errors)


func transition(command: Callable, errors: Array[String] = []) -> bool:
	if not RunContractScript.transition(_state, command, errors):
		return false
	state_changed.emit(RunContractScript.snapshot(_state))
	return true


func has_active_run() -> bool:
	return bool(_state["active"])
