extends Logger
## Collects engine and script errors so a test can fail on them. Use: OS.add_logger(catcher); read catcher.errors.

var errors: Array[String] = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
	errors.append("%s:%d %s %s (in %s)" % [file, line, code, rationale, function])
