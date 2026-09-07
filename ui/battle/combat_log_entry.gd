class_name CombatLogEntry
extends PanelContainer

@onready var message_label: Label = %MessageLabel


func bind_entry(entry: Dictionary) -> void:
	message_label.text = str(entry.get("message", ""))
	var entry_class := str(entry.get("class", ""))
	match entry_class:
		"bad": message_label.modulate = Color("ff928a")
		"ok": message_label.modulate = Color("8ff0b1")
		_: message_label.modulate = Color("d7d9e5")
