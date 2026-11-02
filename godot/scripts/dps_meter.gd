class_name DpsMeter
extends RefCounted
## Damage measured on the hideout training dummy: a rolling DPS over the last few seconds, totals since the first hit,
## the best rolling DPS seen, and a split by damage type and by source (skill, damage over time).
## Times are the game clock (main.time), so a paused game or an open panel doesn't count.

const WINDOW := 5.0      # seconds the current DPS looks back over
const IDLE := 6.0        # no damage for this long and the meter starts over

var hits: Array = []     # [time, damage] within the window
var total := 0.0
var start := -1.0        # time of the first hit, -1 while idle
var last := 0.0          # time of the latest hit
var peak := 0.0
var by_type := {}        # "fire" -> damage
var by_src := {}         # source name -> damage


func active() -> bool:
	return start >= 0.0


func reset() -> void:
	hits.clear()
	total = 0.0
	start = -1.0
	last = 0.0
	peak = 0.0
	by_type.clear()
	by_src.clear()


func add(now: float, dmg: float, type: String, src: String) -> void:
	if dmg <= 0.0:
		return
	if active() and now - last > IDLE:
		reset()
	if not active():
		start = now
	last = now
	hits.append([now, dmg])
	total += dmg
	by_type[type] = by_type.get(type, 0.0) + dmg
	by_src[src] = by_src.get(src, 0.0) + dmg


## drop hits that left the window, keep the peak, and start over after a quiet spell
func tick(now: float) -> void:
	if not active():
		return
	if now - last > IDLE:
		reset()
		return
	while not hits.is_empty() and hits[0][0] < now - WINDOW:
		hits.pop_front()
	peak = maxf(peak, dps(now))


func elapsed(now: float) -> float:
	return now - start if active() else 0.0


## damage in the window over the window's length; the first seconds divide by the time measured so far
## (at least one second, so a single opening hit doesn't read as a huge number)
func dps(now: float) -> float:
	if not active():
		return 0.0
	var sum := 0.0
	for h in hits:
		if h[0] >= now - WINDOW:
			sum += h[1]
	return sum / clampf(now - start, 1.0, WINDOW)


func average(now: float) -> float:
	return total / maxf(1.0, elapsed(now)) if active() else 0.0


## [[key, damage, share]] biggest first
static func split(d: Dictionary) -> Array:
	var sum := 0.0
	for k in d:
		sum += d[k]
	var out := []
	for k in d:
		out.append([k, d[k], d[k] / maxf(sum, 1.0)])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out


static func fmt(v: float) -> String:
	var s := str(roundi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
