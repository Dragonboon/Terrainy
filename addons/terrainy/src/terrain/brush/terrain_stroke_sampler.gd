@tool
extends RefCounted
## Cursor path sampling for Paint/Sculpt. Emits evenly spaced world-local XZ
## dabs, independent of mouse-motion event frequency. Held stamping is separate.
## Work is capped during extreme pointer jumps, preserving UI responsiveness.
const MAX_DABS_PER_EVENT: int = 48
const MIN_SPACING: float = 0.25
const SPACING_RADIUS_FRACTION: float = 0.18


static func spacing(radius: float) -> float:
	return maxf(MIN_SPACING, radius * SPACING_RADIUS_FRACTION)


static func segment(
	from_point: Vector3, to_point: Vector3,
	radius: float, traveled_since_dab: float
) -> Dictionary:
	var delta := Vector2(to_point.x - from_point.x, to_point.z - from_point.z)
	var distance: float = delta.length()
	var base_spacing: float = spacing(radius)
	var previous: float = clampf(traveled_since_dab, 0.0, base_spacing)
	var points: Array[Vector3] = []
	if distance < 0.00001:
		return {"points": points, "carry": previous}
	# Fast cursor motion remains continuous, but bounded: resample the whole
	# jump with a slightly larger spacing rather than skipping its middle.
	var effective_spacing: float = maxf(base_spacing, (distance + previous) / float(MAX_DABS_PER_EVENT))
	var advanced: float = maxf(effective_spacing - previous, 0.00001)
	while advanced <= distance + 0.00001 and points.size() < MAX_DABS_PER_EVENT:
		var t: float = clampf(advanced / distance, 0.0, 1.0)
		points.append(from_point.lerp(to_point, t))
		advanced += effective_spacing
	var carry: float = fposmod(previous + distance, effective_spacing)
	return {"points": points, "carry": carry}
