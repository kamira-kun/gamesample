class_name ModRange
## The range a stat line could have rolled, for the detailed tooltip shown while Alt is held (#57).
## Ranges are worked out from the line's definition (the affix, the unique's own line, the special modifier, the
## tablet or jewel line) and what the thing keeps anyway (its affix key, item level and unique name), through the same
## functions that roll it, so they always match the roll. Crafting that rerolls a line (神秘の核, one-line crafting)
## rolls it from the same definition, so the range holds after it.
## A tooltip line is [text, color, size] or [text, color, size, detail text]; Hud.show_tip shows the detail text
## while `detail` is on.

static var detail := false    # Alt held: tooltips show the ranges


## {lo, hi, name} for line `k` of an item, or {} when it has no rolled range
static func item(it: Dictionary, k: String) -> Dictionary:
	var a := Data.affix(k)
	if a.is_empty():
		return {}
	if int(it.get("rarity", 0)) == 3:
		var fixed: Dictionary = Data.legend(str(it.get("name", ""))).get("mods", {})
		if fixed.has(k):
			var r: Array = fixed[k]
			return _pair(Items.fixed_at(it, k, r, 0.0), Items.fixed_at(it, k, r, 1.0), "固有")
	return _pair(Items.value_at(it, a, 0.0), Items.value_at(it, a, 1.0), a.word)


## the item's special modifier (刻紋)
static func special(it: Dictionary) -> Dictionary:
	var m := Data.special_mod(str(it.get("special", {}).get("k", "")))
	if m.is_empty():
		return {}
	return _pair(Items.special_at(it, m, 0.0), Items.special_at(it, m, 1.0), "")


## line `k` of a 燈晶
static func jewel(j: Dictionary, k: String) -> Dictionary:
	var a := Jewels.affix(k)
	if a.is_empty():
		return {}
	return _pair(Jewels.value_at(j, a, 0.0), Jewels.value_at(j, a, 1.0), a.word)


## a 環晶's strength line
static func ring_power(j: Dictionary) -> Dictionary:
	return _pair(Jewels.power_at(j, 0.0), Jewels.power_at(j, 20.0), "")


## line `k` of a rune tablet
static func tablet(t: Dictionary, k: String) -> Dictionary:
	if Tablets.mod_def(k).is_empty() or Tablets.shape(str(t.get("shape", ""))).is_empty():
		return {}
	return _pair(Tablets.value_at(t, k, 0.8), Tablets.value_at(t, k, 1.2), "")


## line `k` of anything with mods: an item, a 燈晶 or a tablet
static func of(x: Dictionary, k: String) -> Dictionary:
	if x.has("shape"):
		return tablet(x, k)
	if x.has("kind"):
		return jewel(x, k)
	return item(x, k)


static func _pair(a: int, b: int, name: String) -> Dictionary:
	return {"lo": mini(a, b), "hi": maxi(a, b), "name": name}


## what the detailed tooltip adds after a line: "  [15–30]「頑強な」", or that a fixed line can't change
static func tag(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	var out := "  （固定）" if r.lo == r.hi else "  [%s]" % span(r)
	if r.name != "":
		out += "「%s」" % r.name
	return out


## "15–30" ("-17 – -7" when it reaches below zero, so the dash can't pass for a minus)
static func span(r: Dictionary) -> String:
	return ("%d – %d" if r.lo < 0 else "%d–%d") % [r.lo, r.hi]


## a tooltip line with its detailed text
static func line(text: String, color: Color, size: int, r: Dictionary) -> Array:
	return [text, color, size, text + tag(r)]


## a line that never rolls (a base's implicit): the detailed text says so
static func fixed(text: String, color: Color, size: int, what := "基礎") -> Array:
	return [text, color, size, text + "  （%s・固定）" % what]
