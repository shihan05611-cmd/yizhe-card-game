extends Node

## M0 lifecycle boundary only. Domain signals belong to later milestones.
signal application_ready
signal battle_started(view_model: Dictionary)
signal battle_view_model_changed(view_model: Dictionary)
signal battle_command_finished(result: Variant)
signal battle_fatal(fatal: Dictionary)
