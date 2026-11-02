class_name StatusBar
extends HBoxContainer
## The row of small icons at the top left of the HUD (issue #54): one per kind of summoned ally (minions by skill,
## totems, traps) with a count badge "now/max", then one per aura that is on, buff skill running and stacking
## talent buff. Timed ones darken with a sweep as they run out. Hovering an icon shows what it is.
## The row is rebuilt only when something changes (Main.allies_changed, Player.status_changed), once per frame at
## most and deferred, so a death or toggle in the middle of a signal or an update loop never frees a node: icons
## are pooled and only hidden when not needed.

const SIZE := 34.0

var hud: Hud
var icons: Array[StatusIcon] = []   # the pool; the first `shown` are in use
var shown := 0
var rebuilds := 0                   # times the row was rebuilt (the smoke test checks a quiet frame costs none)
var _pending := false


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.main.allies_changed.connect(mark)
	hud.main.player.status_changed.connect(mark)
	mark()


## something changed: rebuild the row once, after the current frame's signals and loops are done
func mark() -> void:
	if _pending:
		return
	_pending = true
	_rebuild.call_deferred()


## what the row shows now, in order: allies, auras, buff skills, talent buffs
func entries() -> Array:
	var m = hud.main
	var p: Player = m.player
	var out := []
	var groups := {}   # key -> entry
	for a in m.minions + m.totems:
		if a.dead or a.life <= 0.0 or not Data.SKILLS.has(a.skill):
			continue
		var kind: String = a.kind if not a.trap else "trap"
		var key: String = a.skill if kind == "minion" else "%s:%s" % [kind, a.skill]
		if not groups.has(key):
			groups[key] = {"key": key, "kind": kind, "id": a.skill, "n": 0, "max": int(m.ally_caps.get(key, 0))}
			out.append(groups[key])
		groups[key].n += 1
	for e in out:
		e.max = maxi(e.max, e.n)
	for id in p.auras:
		out.append({"key": "aura:" + id, "kind": "aura", "id": id})
	for id in p.tbuffs:
		out.append({"key": "tbuff:" + id, "kind": "tbuff", "id": id})
	for k in p.buffs:
		out.append({"key": "buff:" + k, "kind": "buff", "id": k})
	return out


func _rebuild() -> void:
	_pending = false
	rebuilds += 1
	var list := entries()
	while icons.size() < list.size():
		var ic := StatusIcon.new()
		ic.bar = self
		add_child(ic)
		icons.append(ic)
	for i in icons.size():
		var ic := icons[i]
		var was: String = ic.entry.get("key", "")
		ic.entry = list[i] if i < list.size() else {}
		ic.visible = i < list.size()
		if ic.hovered and (not ic.visible or ic.entry.key != was):
			ic.hovered = false
			hud.hide_tip()
		ic.queue_redraw()
	shown = list.size()


## icons whose sweep moves: redraw them (from Hud.refresh, every frame)
func tick() -> void:
	for i in shown:
		if icons[i].timed():
			icons[i].queue_redraw()


## the keys shown, in order (for the smoke test)
func keys() -> Array:
	return icons.slice(0, shown).map(func(ic): return ic.entry.key)


## the entry shown for `key` ({} if none)
func entry(key: String) -> Dictionary:
	for i in shown:
		if icons[i].entry.key == key:
			return icons[i].entry
	return {}


## [seconds left, of how many] for a timed entry, or [] when it doesn't run out
func time_left(e: Dictionary) -> Array:
	var m = hud.main
	var p: Player = m.player
	match e.get("kind", ""):
		"tbuff":
			if p.tbuffs.has(e.id):
				return [p.tbuffs[e.id].t, p.tbuffs[e.id].get("dur", p.tbuffs[e.id].t)]
		"buff":
			if p.buffs.has(e.id):
				return [p.buffs[e.id].t, p.buffs[e.id].get("dur", p.buffs[e.id].t)]
		"minion", "trap":   # the one that runs out first
			var best := []
			for a in (m.minions if e.kind == "minion" else m.totems):
				if a.skill == e.id and a.max_t > 0.0 and a.life > 0.0 and (e.kind == "minion" or a.trap):
					var left: float = a.max_t - a.t
					if best.is_empty() or left < best[0]:
						best = [left, a.max_t]
			return best
		"totem":
			var best := []
			for a in m.totems:
				if a.skill == e.id and not a.trap and a.life > 0.0:
					var left: float = a.max_t - a.t
					if best.is_empty() or left < best[0]:
						best = [left, a.max_t]
			return best
	return []


## the talent a stacking buff comes from (its name, text and the ascendancy's color)
static func talent(k: String) -> Dictionary:
	for a in Data.ASCENDANCIES:
		var c := Data.asc_core(a, k)
		if not c.is_empty():
			return {"name": c.name, "desc": c.desc, "color": a.get("color", Color("#ffd080"))}
	return {"name": k, "desc": "", "color": Color("#ffd080")}


## tooltip lines for an entry: [text, color, size]
func tip_lines(e: Dictionary) -> Array:
	var p: Player = hud.main.player
	var dim := Color("#b8a888")
	var tl := time_left(e)
	var lines := []
	if e.kind == "buff":
		var t := talent(e.id)
		lines.append([t.name, t.color, 16])
		lines.append(["強化（タレント）　%d重" % p.buff(e.id), dim, 13])
		if not tl.is_empty():
			lines.append(["残り %.1f秒" % tl[0], dim, 13])
		lines.append([t.desc, Color("#e8dcc0"), 13])
		return lines
	var sk: Dictionary = Data.SKILLS[e.id]
	match e.kind:
		"minion":
			lines.append([sk.name, sk.color, 16])
			lines.append(["ミニオン　%d / %d 体" % [e.n, e.max], dim, 13])
		"totem", "trap":
			lines.append(["%s（%s）" % [sk.name, "トーテム" if e.kind == "totem" else "罠"], sk.color, 16])
			lines.append(["%s　%d / %d 基" % ["トーテム" if e.kind == "totem" else "罠", e.n, e.max], dim, 13])
		"aura":
			lines.append([sk.name, sk.color, 16])
			var pool: String = sk.aura.pool
			lines.append(["オーラ（発動中）　範囲 %.0fm　リザーブ %s %d" % [sk.aura.r, "ライフ" if pool == "life" else "マナ",
				p.aura_reserve(e.id, pool)], dim, 13])
		"tbuff":
			lines.append([sk.name, sk.color, 16])
			lines.append(["強化", dim, 13])
	if not tl.is_empty():
		lines.append([("残り %.1f秒" if e.kind == "tbuff" else "最短で残り %.1f秒") % maxf(0.0, tl[0]), dim, 13])
	lines.append([sk.desc, Color("#e8dcc0"), 13])
	return lines


class StatusIcon extends Control:
	var bar: StatusBar
	var entry := {}
	var hovered := false

	func _init() -> void:
		custom_minimum_size = Vector2(StatusBar.SIZE, StatusBar.SIZE)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _ready() -> void:
		mouse_entered.connect(func():
			if entry.is_empty():
				return
			hovered = true
			bar.hud.show_tip(bar.tip_lines(entry)))
		mouse_exited.connect(func():
			if hovered:
				hovered = false
				bar.hud.hide_tip())

	func timed() -> bool:
		return entry.get("kind", "") in ["tbuff", "buff", "totem", "trap"] or (entry.get("kind", "") == "minion" and not bar.time_left(entry).is_empty())

	func _draw() -> void:
		if entry.is_empty():
			return
		var rect := Rect2(Vector2.ZERO, size)
		var f := Data.ui_font
		if entry.kind == "buff":
			_glyph(rect, StatusBar.talent(entry.id).color)
		else:
			SkillIcon.draw(self, entry.id, rect)
		match entry.kind:
			"totem":   # a small carved post in the corner
				draw_rect(Rect2(3, size.y - 15, 12, 13), Color(0, 0, 0, 0.7))
				draw_rect(Rect2(7, size.y - 13, 4, 10), Color("#a87a48"))
				draw_rect(Rect2(5, size.y - 12, 8, 2), Color("#6a4628"))
			"trap":   # a little spiked ring
				draw_circle(Vector2(9, size.y - 9), 6.0, Color(0, 0, 0, 0.7))
				draw_arc(Vector2(9, size.y - 9), 3.5, 0.0, TAU, 12, Color("#c8a070"), 1.5)
				for i in 6:
					var a := TAU * i / 6.0
					draw_line(Vector2(9, size.y - 9) + Vector2.from_angle(a) * 3.5, Vector2(9, size.y - 9) + Vector2.from_angle(a) * 6.0, Color("#c8a070"), 1.0)
			"aura":   # framed in the aura's color, like the slot of an aura that is on
				draw_rect(rect.grow(-1.0), Color(Data.SKILLS[entry.id].color, 0.9), false, 2.0)
		var tl := bar.time_left(entry)
		if not tl.is_empty() and tl[1] > 0.0:
			var k := clampf(1.0 - tl[0] / tl[1], 0.0, 1.0)   # the part that has run out, darkened clockwise from the top
			if k > 0.0:
				var pts := PackedVector2Array([size / 2.0])
				for i in 25:
					var a := -PI / 2.0 + k * TAU * float(i) / 24.0
					pts.append((size / 2.0 + Vector2(cos(a), sin(a)) * size.x).clamp(Vector2.ZERO, size))
				draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
		var badge := ""
		match entry.kind:
			"minion", "totem", "trap":
				badge = "%d/%d" % [entry.n, entry.max]
			"buff":
				badge = str(bar.hud.main.player.buff(entry.id))
			"tbuff":
				if not tl.is_empty():
					badge = str(ceili(tl[0]))
		if badge != "":
			var at := Vector2(0, size.y - 2)
			draw_string_outline(f, at, badge, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 1, 11, 3, Color.BLACK)
			draw_string(f, at, badge, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 1, 11, Color("#fff0c8"))

	## a stacking talent buff has no skill icon: a dark tile rimmed in its ascendancy's color, rising chevrons
	## for the speed it gives (two for an attack, a spark between them for a spell)
	func _glyph(rect: Rect2, col: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.82)
		sb.border_color = col
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(5)
		draw_style_box(sb, rect)
		var c := rect.get_center()
		var w := rect.size.x * 0.28
		for dy in [4.0, -4.0]:
			draw_polyline(PackedVector2Array([c + Vector2(-w, dy + 4), c + Vector2(0, dy - 3), c + Vector2(w, dy + 4)]), col.lightened(0.3), 3.0)
		if entry.id == "spell_frenzy":
			draw_circle(c + Vector2(0, -10), 2.5, Color("#ffe0a0"))
