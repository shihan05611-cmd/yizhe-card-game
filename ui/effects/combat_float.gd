class_name CombatFloat
extends Control

@export var prefix := ""
@export var rise_distance := 42.0

@onready var value_label: Label = %ValueLabel

var _play_tween: Tween


func configure(event: Dictionary, anchor: Dictionary) -> void:
	set_meta("presentation_event", event.duplicate(true))
	var payload: Dictionary = event.get("payload", {})
	var amount := float(payload.get("amount", 0.0))
	value_label.text = "%s%d" % [prefix, roundi(amount)]
	if anchor.get("position") is Vector2:
		position = anchor["position"] - size * 0.5


func configure_marker(text: String, event: Dictionary, anchor: Dictionary) -> void:
	set_meta("presentation_event", event.duplicate(true))
	value_label.text = text
	if anchor.get("position") is Vector2:
		position = anchor["position"] - size * 0.5 + Vector2(0.0, -28.0)


func play(duration_seconds: float) -> void:
	if not is_inside_tree():
		return
	if _play_tween != null and _play_tween.is_valid():
		_play_tween.kill()
	var duration := maxf(0.05, duration_seconds)
	modulate.a = 1.0
	# Keep the value readable at impact, then let it rise and fade together.
	var hold := minf(0.12, duration * 0.30)
	var travel := maxf(0.03, duration - hold)
	_play_tween = create_tween()
	_play_tween.tween_interval(hold)
	_play_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_play_tween.tween_property(self, "position:y", position.y - rise_distance, travel)
	_play_tween.parallel()
	_play_tween.tween_property(self, "modulate:a", 0.0, travel)
	_play_tween.chain().tween_callback(queue_free)
