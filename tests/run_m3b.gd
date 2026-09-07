extends SceneTree

const TestHarnessScript = preload("res://tests/support/test_harness.gd")
const CardCatalogTestScript = preload("res://tests/card_catalog_test.gd")
const HandManagerTestScript = preload("res://tests/hand_manager_test.gd")
const CardPlayFlowTestScript = preload("res://tests/card_play_flow_test.gd")
const EnergyRuleTestScript = preload("res://tests/energy_rule_test.gd")
const UltimateCardTestScript = preload("res://tests/ultimate_card_test.gd")
const DeckAssemblyTestScript = preload("res://tests/deck_assembly_test.gd")
const BattleCardSessionTestScript = preload("res://tests/battle_card_session_test.gd")
const PieceAttackTestScript = preload("res://tests/piece_attack_test.gd")
const PieceReactionsTestScript = preload("res://tests/piece_reactions_test.gd")
const EnemySkillAdapterTestScript = preload("res://tests/enemy_skill_adapter_test.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarnessScript.new()
	# M3 focus intentionally uses the card runtime's deck determinism/isolation
	# coverage. The shared full RNG golden suite remains in regular regression.
	CardCatalogTestScript.new().run(harness)
	HandManagerTestScript.new().run(harness)
	CardPlayFlowTestScript.new().run(harness)
	EnergyRuleTestScript.new().run(harness)
	UltimateCardTestScript.new().run(harness)
	DeckAssemblyTestScript.new().run(harness)
	BattleCardSessionTestScript.new().run(harness)
	PieceAttackTestScript.new().run(harness)
	PieceReactionsTestScript.new().run(harness)
	EnemySkillAdapterTestScript.new().run(harness)
	harness.print_summary()
	quit(0 if harness.failures == 0 else 1)
