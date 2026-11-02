class_name StatusUI
extends BasePanel
## Character status (C): the character picture, level and experience, every derived stat, gear and skill bar at a glance.

var head_line := Label.new()
var xp := Hud.Bar.new()
var xp_text := Label.new()
var res := HBoxContainer.new()
var stats := GridContainer.new()
var gear := GridContainer.new()
var skills := GridContainer.new()
var portrait := Portrait.new()


func _title() -> String:
	return "ステータス"


func _build() -> void:
	head_line.add_theme_font_size_override("font_size", 16)
	head_line.add_theme_color_override("font_color", Color("#f0dcb4"))
	body.add_child(head_line)
	xp.custom_minimum_size = Vector2(0, 9)
	xp.fill = Color("#e0b040")
	body.add_child(xp)
	xp_text.add_theme_font_size_override("font_size", 12)
	xp_text.add_theme_color_override("font_color", Color("#a89878"))
	body.add_child(xp_text)
	res.add_theme_constant_override("separation", 26)
	body.add_child(res)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	body.add_child(cols)
	cols.add_child(portrait)
	var left := VBoxContainer.new()
	cols.add_child(left)
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 24)
	left.add_child(stats)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	right.add_child(sub("装備"))
	gear.columns = 2
	gear.add_theme_constant_override("h_separation", 16)
	right.add_child(gear)
	right.add_child(sub("スキルバー"))
	skills.columns = 2
	skills.add_theme_constant_override("h_separation", 16)
	right.add_child(skills)


## [label, value] rows; the first seven are offense
static func stat_rows(s: Dictionary) -> Array:
	return [
		["ダメージ", "%d–%d" % [roundi(s.dmg_min), roundi(s.dmg_max)]], ["攻撃/秒", "%.2f" % s.attack_rate],
		["ダメージ増加", "%d%%" % s.inc_dmg], ["スキルダメージ", "%d%%" % s.spell_dmg],
		["クリティカル", "%.1f%% / %d%%" % [s.crit, s.crit_multi]], ["詠唱速度", "+%d%%" % s.cast_spd],
		["火炎/冷気/雷", "%d/%d/%d%%" % [s.fire_dmg, s.cold_dmg, s.light_dmg]], ["アーマー", "%d（軽減 %d%%）" % [s.armor, roundi(s.dr * 100)]],
		["移動速度", "+%d%%" % s.move_spd], ["クールダウン短縮", "%d%%" % s.cdr],
		["ライフ回復", "%.1f/秒" % s.life_regen], ["マナ回復", "%.1f/秒" % s.mana_regen],
	]


func _row(grid: GridContainer, k: String, v: String, vcol := Color("#f0dcb4")) -> void:
	grid.add_child(sub(k, 13, Color("#a89878")))
	grid.add_child(sub(v, 13, vcol))


func refresh() -> void:
	if not visible:
		return
	var m = hud.main
	var p: Player = m.player
	var s := p.s
	portrait.show_player(p)
	head_line.text = "レベル %d　・　踏破 %d/%d" % [p.level, m.atlas.cleared.size(), Data.ATLAS_NODES.size()]
	xp.value = float(p.xp) / Data.xp_need(p.level)
	xp.queue_redraw()
	xp_text.text = "経験値 %d / %d" % [p.xp, Data.xp_need(p.level)]
	clear(res)
	for pool in ["life", "mana"]:
		var line := "%s %d/%d" % ["ライフ" if pool == "life" else "マナ", ceili(p.life) if pool == "life" else floori(p.mana), roundi(p.cap(pool))]
		if p.reserved(pool) > 0.0:
			line += "（リザーブ %d）" % ceili(p.reserved(pool))
		res.add_child(sub(line, 15, Color("#ff7a6a") if pool == "life" else Color("#7aa8ff")))
	res.add_child(sub("灰燼の欠片 %d" % p.cur.ember, 15, Color("#ffb35a")))
	clear(stats)
	var rows := stat_rows(s)
	stats.add_child(sub("攻撃", 14, Color("#f0d8a0")))
	stats.add_child(Control.new())
	for i in rows.size():
		if i == 7:
			stats.add_child(sub("防御・その他", 14, Color("#f0d8a0")))
			stats.add_child(Control.new())
		_row(stats, rows[i][0], rows[i][1])
	_row(stats, "タレントポイント", str(p.talent_pts), Color("#ffe27a"))
	var a := Data.ascendancy(p.asc)
	_row(stats, "アセンダンシー", "%s（残り %d）" % [a.name, p.asc_free()] if not a.is_empty() else "未選択 [%s]" % Keybinds.text("ascendancy"), a.get("color", Color("#776a58")))
	_row(stats, "エネルギー", "%d / %d" % [p.energy_used(), p.energy_max()], Data.GEM_COLOR)
	clear(gear)
	for slot in Data.SLOTS:
		var it: Dictionary = p.equip.get(slot, {})
		_row(gear, Data.SLOT_INFO[slot].name, it.name if not it.is_empty() else "—", Data.RARITY[it.rarity].color if not it.is_empty() else Color("#554a3a"))
	clear(skills)
	for i in Data.SLOT_COUNT:
		var id: String = p.slots[i]
		var sk: Dictionary = Data.SKILLS[id]
		var r: int = p.talents.get(id, 0)
		if sk.has("aura"):
			_row(skills, "%s　%s %s" % [Keybinds.short(Keybinds.skill_action(i)), sk.icon, sk.name], "発動中" if id in p.auras else "停止中", sk.color)
			continue
		_row(skills, "%s　%s %s" % [Keybinds.short(Keybinds.skill_action(i)), sk.icon, sk.name], "ランク %d（+%d%%）" % [r, r * 15], sk.color)
