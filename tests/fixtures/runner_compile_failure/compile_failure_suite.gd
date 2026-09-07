extends RefCounted

const BrokenDependency = preload("res://tests/fixtures/runner_compile_failure/broken_dependency.gd")


func run(_harness: TestHarness) -> void:
	BrokenDependency.new()
