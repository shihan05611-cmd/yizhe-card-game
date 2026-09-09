class_name RunSaveStore
extends RefCounted

## JSON checkpoint persistence for the Run composition root. Domain scripts own
## schema validation; this adapter owns durable, replace-on-success file I/O.

const DEFAULT_PATH := "user://run-save.json"

var _path: String
var _valid := false
var _dependency_error := ""


func _init(save_path: Variant = DEFAULT_PATH, errors: Array[String] = []) -> void:
	errors.clear()
	if typeof(save_path) != TYPE_STRING or save_path.strip_edges().is_empty():
		_dependency_error = "Run save path must be a non-empty String"
		errors.append(_dependency_error)
		return
	_path = save_path
	_valid = true


func is_valid() -> bool:
	return _valid


func has_save() -> bool:
	if not _valid:
		return false
	if FileAccess.file_exists(_path):
		return true
	var backup_errors: Array[String] = []
	return _load_file(_path + ".replace-backup", "Run save backup", backup_errors) != null


func save(checkpoint: Variant, errors: Array[String] = []) -> bool:
	errors.clear()
	if not _require_valid(errors):
		return false
	if typeof(checkpoint) != TYPE_DICTIONARY:
		errors.append("Run save checkpoint must be a Dictionary")
		return false
	if not _validate_json_safe(checkpoint, "checkpoint", errors):
		return false
	var absolute_path := ProjectSettings.globalize_path(_path)
	var directory_path := absolute_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(directory_path)
	if directory_error != OK:
		errors.append("could not create Run save directory: %s" % error_string(directory_error))
		return false
	var temporary_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".replace-backup"
	DirAccess.remove_absolute(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		errors.append("could not open Run save temporary file: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(checkpoint, "", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		errors.append("could not write Run save temporary file: %s" % error_string(write_error))
		return false
	var had_previous := FileAccess.file_exists(absolute_path)
	var had_backup := FileAccess.file_exists(backup_path)
	if had_previous and had_backup:
		var main_errors: Array[String] = []
		if _load_file(absolute_path, "Run save", main_errors) != null:
			var stale_cleanup_error := DirAccess.remove_absolute(backup_path)
			if stale_cleanup_error != OK:
				DirAccess.remove_absolute(temporary_path)
				errors.append(
					"could not clean a stale Run save backup: %s"
					% error_string(stale_cleanup_error)
				)
				return false
			had_backup = false
		else:
			var backup_errors: Array[String] = []
			if _load_file(backup_path, "Run save backup", backup_errors) == null:
				DirAccess.remove_absolute(temporary_path)
				errors.append(
					"Run save main and backup are both invalid; both were preserved: %s; %s"
					% ["; ".join(main_errors), "; ".join(backup_errors)]
				)
				return false
			var corrupt_path := _unique_corrupt_path(absolute_path)
			var preserve_error := DirAccess.rename_absolute(absolute_path, corrupt_path)
			if preserve_error != OK:
				DirAccess.remove_absolute(temporary_path)
				errors.append(
					"could not preserve corrupt Run save: %s" % error_string(preserve_error)
				)
				return false
			had_previous = false
	var created_backup := false
	if had_previous:
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_path)
			errors.append("could not prepare Run save replacement: %s" % error_string(backup_error))
			return false
		created_backup = true
	var replace_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if replace_error != OK:
		DirAccess.remove_absolute(temporary_path)
		if created_backup:
			var rollback_error := DirAccess.rename_absolute(backup_path, absolute_path)
			if rollback_error != OK:
				errors.append(
					"Run save replacement failed and backup recovery failed: %s; %s"
					% [error_string(replace_error), error_string(rollback_error)]
				)
				return false
		errors.append("could not replace Run save: %s" % error_string(replace_error))
		return false
	var verify_errors: Array[String] = []
	if _load_file(absolute_path, "new Run save", verify_errors) == null:
		if created_backup:
			var failed_path := absolute_path + ".failed-new"
			DirAccess.remove_absolute(failed_path)
			DirAccess.rename_absolute(absolute_path, failed_path)
			var rollback_error := DirAccess.rename_absolute(backup_path, absolute_path)
			if rollback_error != OK:
				errors.append(
					"new Run save verification failed and backup recovery failed: %s; %s"
					% ["; ".join(verify_errors), error_string(rollback_error)]
				)
				return false
		errors.append("new Run save verification failed: %s" % "; ".join(verify_errors))
		return false
	if created_backup or had_backup:
		var cleanup_error := DirAccess.remove_absolute(backup_path)
		if cleanup_error != OK:
			errors.append("Run save replaced but old backup cleanup failed: %s" % error_string(cleanup_error))
			return false
	return true


func load(errors: Array[String] = []) -> Variant:
	errors.clear()
	if not _require_valid(errors):
		return null
	var main_errors: Array[String] = []
	var checkpoint: Variant = _load_file(_path, "Run save", main_errors)
	if checkpoint != null:
		return checkpoint
	var backup_errors: Array[String] = []
	checkpoint = _load_file(_path + ".replace-backup", "Run save backup", backup_errors)
	if checkpoint != null:
		return checkpoint
	if not main_errors.is_empty():
		errors.append_array(main_errors)
	if not backup_errors.is_empty():
		errors.append_array(backup_errors)
	if errors.is_empty():
		errors.append("Run save does not exist")
	return null


static func _load_file(path: String, label: String, errors: Array[String]) -> Variant:
	errors.clear()
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("could not open %s: %s" % [label, error_string(FileAccess.get_open_error())])
		return null
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		errors.append("could not read %s: %s" % [label, error_string(read_error)])
		return null
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		errors.append(
			"%s JSON is invalid at line %d: %s"
			% [label, parser.get_error_line(), parser.get_error_message()]
		)
		return null
	var checkpoint: Variant = parser.data
	if typeof(checkpoint) != TYPE_DICTIONARY:
		errors.append("%s root must be a Dictionary" % label)
		return null
	if not _validate_json_safe(checkpoint, "checkpoint", errors):
		return null
	return checkpoint


static func _unique_corrupt_path(absolute_path: String) -> String:
	var timestamp := int(Time.get_unix_time_from_system())
	var candidate := "%s.corrupt.%d.json" % [absolute_path, timestamp]
	var suffix := 1
	while FileAccess.file_exists(candidate):
		candidate = "%s.corrupt.%d.%d.json" % [absolute_path, timestamp, suffix]
		suffix += 1
	return candidate


func _require_valid(errors: Array[String]) -> bool:
	if _valid:
		return true
	errors.append(_dependency_error if not _dependency_error.is_empty() else "Run save store is invalid")
	return false


static func _validate_json_safe(value: Variant, path: String, errors: Array[String]) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			if is_finite(value):
				return true
		TYPE_ARRAY:
			for index in value.size():
				if not _validate_json_safe(value[index], "%s[%d]" % [path, index], errors):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING:
					errors.append("%s contains a non-string JSON key" % path)
					return false
				if not _validate_json_safe(value[key], "%s.%s" % [path, key], errors):
					return false
			return true
	errors.append("%s contains a non-JSON-safe value" % path)
	return false
