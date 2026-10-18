extends SceneTree
## Run: godot --headless --path . --script res://tests/terrain_stroke_sampling_checks.gd
const Sampler = preload("res://addons/terrainy/src/terrain/brush/terrain_stroke_sampler.gd")

var failures: int = 0


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _initialize() -> void:
	var radius: float = 12.0
	var from := Vector3(0.0, 9.0, 0.0)
	var to := Vector3(35.0, 11.0, 0.0)
	var result: Dictionary = Sampler.segment(from, to, radius, 0.0)
	var dots: Array[Vector3] = result["points"]
	_check(dots.size() >= 12 and dots.size() <= Sampler.MAX_DABS_PER_EVENT, "Long drag lost most samples")
	var previous: Vector3 = from
	for dot in dots:
		_check(dot.x > previous.x, "Samples must follow the pointer")
		_check(dot.distance_to(previous) <= Sampler.spacing(radius) + 0.5, "Stroke left a large gap")
		previous = dot
	_check(result["carry"] < Sampler.spacing(radius), "Invalid carry after movement")
	var stationary: Dictionary = Sampler.segment(to, to, radius, float(result["carry"]))
	_check(stationary["points"].is_empty(), "Stationary timer must own held stamps")
	var extreme: Dictionary = Sampler.segment(from, Vector3(100000, 10, 0), radius, 0.0)
	_check((extreme["points"] as Array).size() <= Sampler.MAX_DABS_PER_EVENT, "Unbounded work per input event")
	# Combined short event path should roughly match one long event in point count.
	var count: int = 0
	var carry: float = 0.0
	var previous_point := from
	for i in range(1, 101):
		var p := from.lerp(to, float(i) / 100.0)
		var segment: Dictionary = Sampler.segment(previous_point, p, radius, carry)
		count += (segment["points"] as Array).size()
		carry = float(segment["carry"])
		previous_point = p
	_check(absi(count - dots.size()) <= 1, "Mouse event rate changed brush density")
	print("Terrainy stroke sampling checks: %d failures" % failures)
	quit(1 if failures > 0 else 0)
