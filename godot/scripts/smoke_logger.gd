class_name SmokeLogger
extends Logger
## `--smoke`: catches engine and script errors that print but do not stop the run, so a check can fail on them.
## Only "locked object" frees are kept (a node freed while its own signal is still being emitted, issue #47).

var locked: Array[String] = []
var _lock := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		_error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var text := "%s %s %s:%d %s" % [code, rationale, file, line, function]
	if "locked" in text:
		_lock.lock()
		locked.append(text)
		_lock.unlock()


func count() -> int:
	_lock.lock()
	var n := locked.size()
	_lock.unlock()
	return n
