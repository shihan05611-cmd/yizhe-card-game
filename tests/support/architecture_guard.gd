class_name ArchitectureGuard
extends RefCounted

const PRODUCTION_LAYERS := {
	"data": 0,
	"core": 1,
	"systems": 2,
	"app": 3,
	"autoload": 3,
	"ui": 4,
	"scenes": 4,
}
## These are the required source roots in M0. `scenes` remains a UI target
## layer, but it is not a required source root before that directory exists.
const PRODUCTION_ROOTS: Array[String] = [
	"data",
	"core",
	"systems",
	"app",
	"autoload",
	"ui",
]

const PURE_LAYER_RULES := [
	{
		"id": "PURE_GET_TREE",
		"pattern": "\\bget_tree\\s*\\(",
		"message": "pure logic scripts must not access SceneTree",
	},
	{
		"id": "PURE_RANDOM_SOURCE",
		"pattern": "\\bRandomNumberGenerator\\b",
		"message": "randomness must use an injected deterministic pure-logic source",
	},
	{
		"id": "PURE_GLOBAL_RANDOM",
		"pattern": "\\b(?:randi_range|randf_range|randi|randf|randfn)\\s*\\(",
		"message": "global random functions are forbidden in pure logic",
	},
	{
		"id": "PURE_FILE_IO",
		"pattern": "\\b(?:FileAccess|DirAccess)\\b",
		"message": "file-system access belongs to the app layer",
	},
]

const EXTENDS_PATTERN := "\\bextends\\s+([A-Za-z_][A-Za-z0-9_]*)\\b"
const STATIC_DEPENDENCY_PATTERN := (
	"\\b(?:preload|load)\\s*\\(\\s*[\"'](res://[^\"']+)[\"']"
)


func scan_production(
	project_root: String = "res://",
	required_roots: Array = PRODUCTION_ROOTS,
) -> Array[Dictionary]:
	var violations: Array[Dictionary] = []
	for root_value in required_roots:
		var root_name := str(root_value)
		var root_path := project_root.path_join(root_name)
		var script_paths := _collect_gd_files(root_path, project_root, violations)
		for script_path in script_paths:
			var relative_path := script_path.trim_prefix(project_root).trim_prefix("/")
			violations.append_array(scan_file(script_path, relative_path, root_name))
	_sort_violations(violations)
	return violations


func scan_file(
	script_path: String,
	relative_path: String,
	assumed_layer: String,
) -> Array[Dictionary]:
	var source_file := FileAccess.open(script_path, FileAccess.READ)
	if source_file == null:
		var failures: Array[Dictionary] = []
		_add_violation(
			failures,
			relative_path,
			1,
			"SCAN_FILE_UNREADABLE",
			"unable to read production script: %s" % script_path
		)
		return failures
	return scan_source(source_file.get_as_text(), relative_path, assumed_layer)


func scan_fixture(fixture_path: String, assumed_layer: String) -> Array[Dictionary]:
	return scan_file(
		fixture_path,
		fixture_path.trim_prefix("res://"),
		assumed_layer
	)


func scan_source(
	source: String,
	relative_path: String,
	assumed_layer: String = "",
) -> Array[Dictionary]:
	var source_layer_name := assumed_layer
	if source_layer_name.is_empty():
		source_layer_name = relative_path.get_slice("/", 0)
	if not PRODUCTION_LAYERS.has(source_layer_name):
		return []

	var violations: Array[Dictionary] = []
	var cleaned_source := _mask_non_code(source)
	var cleaned_lines := cleaned_source.split("\n", true)
	var source_layer: int = PRODUCTION_LAYERS[source_layer_name]
	var is_pure_layer := source_layer_name in ["core", "systems"]

	for line_index in range(cleaned_lines.size()):
		if is_pure_layer:
			_scan_pure_rules(
				cleaned_lines[line_index],
				relative_path,
				line_index + 1,
				violations
			)

	for dependency in _static_dependencies(source, cleaned_source):
		var dependency_path: String = dependency["path"]
		var line_number: int = dependency["line"]
		var target_layer_name := dependency_path.trim_prefix("res://").get_slice("/", 0)
		if PRODUCTION_LAYERS.has(target_layer_name):
			var target_layer: int = PRODUCTION_LAYERS[target_layer_name]
			if target_layer > source_layer:
				_add_violation(
					violations,
					relative_path,
					line_number,
					"LAYER_UPWARD_DEPENDENCY",
					"%s layer must not depend on higher %s layer: %s" % [
						source_layer_name,
						target_layer_name,
						dependency_path,
					]
				)
		var is_scene_path := (
			dependency_path == "res://scenes"
			or dependency_path.begins_with("res://scenes/")
		)
		if is_pure_layer and is_scene_path:
			_add_violation(
				violations,
				relative_path,
				line_number,
				"PURE_SCENE_DEPENDENCY",
				"pure logic scripts must not load scene resources: %s" % dependency_path
			)

	_sort_violations(violations)
	return violations


func _scan_pure_rules(
	cleaned_line: String,
	relative_path: String,
	line_number: int,
	violations: Array[Dictionary],
) -> void:
	var extends_expression := RegEx.create_from_string(EXTENDS_PATTERN)
	var extends_match := extends_expression.search(cleaned_line)
	if extends_match != null:
		var base_class: String = extends_match.get_string(1)
		if (
			ClassDB.class_exists(base_class)
			and (base_class == "Node" or ClassDB.is_parent_class(base_class, "Node"))
		):
			_add_violation(
				violations,
				relative_path,
				line_number,
				"PURE_NODE_BASE",
				"pure logic scripts must not extend built-in Node class: %s" % base_class
			)

	for rule in PURE_LAYER_RULES:
		var expression := RegEx.create_from_string(rule["pattern"])
		if expression.search(cleaned_line) != null:
			_add_violation(
				violations,
				relative_path,
				line_number,
				rule["id"],
				rule["message"]
			)


func _static_dependencies(original_source: String, cleaned_source: String) -> Array[Dictionary]:
	var dependencies: Array[Dictionary] = []
	var expression := RegEx.create_from_string(STATIC_DEPENDENCY_PATTERN)
	for dependency_match in expression.search_all(original_source):
		var call_start := dependency_match.get_start()
		if call_start >= cleaned_source.length():
			continue
		if cleaned_source.substr(call_start, 1) == " ":
			continue
		dependencies.append({
			"path": dependency_match.get_string(1),
			"line": original_source.substr(0, call_start).count("\n") + 1,
		})
	return dependencies


func _collect_gd_files(
	directory_path: String,
	project_root: String,
	violations: Array[Dictionary],
) -> Array[String]:
	var files: Array[String] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		var relative_path := directory_path.trim_prefix(project_root).trim_prefix("/")
		_add_violation(
			violations,
			relative_path,
			1,
			"SCAN_ROOT_UNREADABLE",
			"required production directory is missing or unreadable: %s" % directory_path
		)
		return files

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var entry_path := directory_path.path_join(entry)
			if directory.current_is_dir():
				files.append_array(_collect_gd_files(entry_path, project_root, violations))
			elif entry.ends_with(".gd"):
				files.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()
	files.sort()
	return files


## This is intentionally a small lexer, not a complete GDScript parser. It
## masks comments, quoted strings, and multiline triple-quoted strings while
## preserving every character position and newline. Static preload/load paths
## are then matched across the original full source only when the call token is
## still executable code in the mask. Built-in Node bases are complete through
## ClassDB; inheritance through project-defined custom base classes is not
## recursively resolved by this lexical guard.
func _mask_non_code(source: String) -> String:
	var cleaned := ""
	var triple_delimiter := ""
	var index := 0
	while index < source.length():
		if not triple_delimiter.is_empty():
			if source.substr(index, 3) == triple_delimiter:
				cleaned += "   "
				index += 3
				triple_delimiter = ""
			else:
				var triple_character := source.substr(index, 1)
				cleaned += "\n" if triple_character == "\n" else " "
				index += 1
			continue

		var character := source.substr(index, 1)
		if character == "#":
			while index < source.length() and source.substr(index, 1) != "\n":
				cleaned += " "
				index += 1
			continue
		if character in ["\"", "'"]:
			var candidate_delimiter := character.repeat(3)
			if source.substr(index, 3) == candidate_delimiter:
				triple_delimiter = candidate_delimiter
				cleaned += "   "
				index += 3
				continue

			cleaned += " "
			index += 1
			var escaped := false
			while index < source.length():
				var string_character := source.substr(index, 1)
				cleaned += "\n" if string_character == "\n" else " "
				index += 1
				if escaped:
					escaped = false
				elif string_character == "\\":
					escaped = true
				elif string_character == character:
					break
			continue

		cleaned += character
		index += 1
	return cleaned


func _add_violation(
	violations: Array[Dictionary],
	file_path: String,
	line_number: int,
	rule_id: String,
	message: String,
) -> void:
	violations.append({
		"path": file_path.replace("\\", "/"),
		"line": line_number,
		"rule_id": rule_id,
		"message": message,
	})


func _sort_violations(violations: Array[Dictionary]) -> void:
	violations.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_key := "%s|%09d|%s|%s" % [
			left["path"], left["line"], left["rule_id"], left["message"]
		]
		var right_key := "%s|%09d|%s|%s" % [
			right["path"], right["line"], right["rule_id"], right["message"]
		]
		return left_key < right_key
	)
