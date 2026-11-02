class_name DataDocs
extends RefCounted
## The game-data reference (docs/db): uniques, rare items and their affixes, base classes and ascendancies,
## the passive tree, and skill and support gems, built from the live tables so it never drifts from the game.
## Every page is a list of sections, each a table; `pages()` renders them as Markdown files and as one
## searchable HTML page. Written by `godot --headless --path . -s tools/gen_docs.gd`; tools/run_check.gd fails
## while the files on disk are out of date.

const DIR := "res://../docs/db/"
const RARE_LVLS := [1, 20, 40, 60]     # item levels the affix tables show
const UNIQUE_LVLS := [1, 40]
const CRAFT_CURRENCIES := ["transmute", "ascend", "chaos", "whet", "purify", "divine"]


## path (relative to DIR) -> file text
static func files() -> Dictionary:
	var ps := pages()
	var out := {"README.md": _index_md(ps), "index.html": _html(ps)}
	for p in ps:
		out[p.file] = _md(p)
	return out


## each page: {file, title, intro, sections: [{title, note, head, rows}]}
static func pages() -> Array:
	var ps := []
	for slot in Data.SLOTS:
		ps.append(_uniques(slot))
	ps.append(_rares())
	ps.append(_ascendancies())
	ps.append(_passives())
	ps.append(_gems())
	return ps


# =================== pages ===================
static func _uniques(slot: String) -> Dictionary:
	var secs := []
	var bases: Array = Data.BASES[slot]
	for bi in bases.size():
		var rows := []
		for l in Data.LEGENDARY:
			if l.slot != slot or mini(l.base, bases.size() - 1) != bi:
				continue
			var stats := []
			if l.has("mods"):
				for k in l.mods:
					stats.append(_unique_stat(k, l.mods[k]))
			else:
				stats.append("ランダムなオプション %d〜%d 個" % Data.RARITY[3].aff)
			rows.append([l.name, "<br>".join(PackedStringArray(stats)), l.get("desc", ""), l.get("flavor", "")])
		if rows.is_empty():
			continue
		var b: Dictionary = bases[bi]
		secs.append({"title": "%s（%d）" % [b.name, rows.size()], "note": "ベース：" + _base_text(slot, b, true),
			"head": ["名前", "能力値（iLv%d）" % UNIQUE_LVLS[0], "固有効果", "フレーバー"],
			"rows": rows})
	var n := Data.LEGENDARY.filter(func(l): return l.slot == slot).size()
	return {"file": "uniques-%s.md" % slot, "title": "ユニーク：%s（%d種）" % [Data.SLOT_INFO[slot].name, n],
		"intro": "レジェンド（ユニーク）は全%d種。レジェンドのドロップはこの一覧から等確率で1つ選ばれます。能力値は範囲内でランダムに決まり、アイテムレベル（iLv＝落ちたエリアのレベル）が高いほど大きくなります（マイナスは代償）。神秘の核で振り直せます。" % Data.LEGENDARY.size(),
		"sections": secs}


static func _rares() -> Dictionary:
	var secs := []
	var rr := []
	for i in Data.RARITY.size():
		var r: Dictionary = Data.RARITY[i]
		rr.append([r.name, "%d〜%d 個" % r.aff if r.aff[1] > 0 else "なし", "%.1f%%" % (100.0 * r.w / Data.RARITY.reduce(func(a, x): return a + x.w, 0.0)),
			["ベースの名前", "最初のオプションの語＋ベース名（例：猛き片手剣）", "ランダムな2語（例：%s%s）" % [Data.RARE_A[0], Data.RARE_B[0]], "ユニークの名前"][i]])
	secs.append({"title": "レア度", "note": "ドロップ率は補正なしの基本値。マップのレア度補正・エリート・ボスで上位のレア度が出やすくなります。",
		"head": ["レア度", "オプション数", "基本ドロップ率", "名前"], "rows": rr})
	var br := []
	for slot in Data.SLOTS:
		for b in Data.BASES[slot]:
			br.append([Data.SLOT_INFO[slot].name, b.name, _base_text(slot, b, false)])
	secs.append({"title": "ベースアイテム", "note": "武器ダメージは ×(1 + iLv×0.22)、アーマーは ×(1 + iLv×0.2) で伸びます（ユニーク武器はさらに ×1.25）。",
		"head": ["部位", "ベース", "基本性能・固有オプション"], "rows": br})
	var ar := []
	for a in Data.AFFIXES:
		if a.slots.is_empty():
			continue
		var row := [_fill(a.fmt, "#"), a.word]
		for lv in RARE_LVLS:
			row.append(_range_text(_grow(a.min, lv, a.sc), _grow(a.max, lv, a.sc)))
		row.append("・".join(PackedStringArray(Data.SLOTS.filter(func(s): return s in a.slots).map(func(s): return Data.SLOT_INFO[s].name))))
		ar.append(row)
	secs.append({"title": "オプション（接辞）", "note": "マジック・レアのオプションは、部位に付くものから重複なしで選ばれます。値は (最小〜最大) × (1 + iLv × 伸び率) で、ユニークに付くランダムオプションはさらに ×1.2。",
		"head": ["オプション", "マジックの語"] + RARE_LVLS.map(func(v): return "iLv%d" % v) + ["付く部位"], "rows": ar})
	var mr := []
	for slot in Data.SLOTS:
		var row := [Data.SLOT_INFO[slot].name]
		var ks := Data.AFFIXES.filter(func(a): return slot in a.slots).map(func(a): return _stat_name(a.fmt))
		row.append("%d 種" % ks.size())
		row.append("・".join(PackedStringArray(ks)))
		mr.append(row)
	secs.append({"title": "部位ごとのオプション", "note": "", "head": ["部位", "数", "付くオプション"], "rows": mr})
	var cr := []
	for c in Data.CURRENCIES.filter(func(x): return x.k in CRAFT_CURRENCIES):
		cr.append([c.icon + " " + c.name, c.desc])
	secs.append({"title": "クラフト用カレンシー", "note": "", "head": ["カレンシー", "効果"], "rows": cr})
	return {"file": "rare.md", "title": "レア装備とオプション",
		"intro": "ユニーク以外の装備は、ベースアイテムにランダムなオプションが付いたものです。レアは3〜4個のオプションを持ち、名前はランダムな2語から作られます。",
		"sections": secs}


static func _ascendancies() -> Dictionary:
	var secs := []
	for bc in Data.CLASSES:
		var kit := "%s／スキル：%s／サポートジェム：%s" % [bc.weapon, "・".join(PackedStringArray(bc.slots.map(func(id): return Data.SKILLS[id].name))),
			"・".join(PackedStringArray(bc.gems.map(func(g): return Data.support(g).name)))]
		var rows := [["ベースキャラ", bc.icon + " " + bc.name, bc.desc, bc.traits], ["初期装備", "", kit, ""]]
		for k in bc.ascs:
			var a := Data.ascendancy(k)
			rows.append(["アセンダンシー", a.icon + " " + a.name, a.desc, ""])
			for n in a.minors:
				var ranks := []
				for r in range(1, n.max + 1):
					ranks.append(n.fmt.replace("{v}", _num(n.stats.values()[0] * r)))
				# further stats the line doesn't name (a minor whose stats share one value is one line, like 冷気・雷)
				var first: float = n.stats.values()[0]
				var extra: Array = n.stats.keys().slice(1).filter(func(s): return n.stats[s] != first) 					.map(func(s): return "%s ×ランク" % _stat_text(s, n.stats[s]))
				rows.append(["　マイナー（最大%dランク）" % n.max, n.name, " → ".join(PackedStringArray(ranks)), "・".join(PackedStringArray(extra))])
			for t in a.cores.size():
				for c in a.cores[t]:
					rows.append(["　コア 第%d段（%d点）" % [t + 1, Data.ASC_CORE_REQ[t]], c.name, c.desc, "2つのうち1つ"])
		secs.append({"title": "%s %s" % [bc.icon, bc.name], "note": "", "head": ["種類", "名前", "内容", "補足"], "rows": rows})
	return {"file": "ascendancy.md", "title": "ベースキャラとアセンダンシー",
		"intro": "キャラクター作成時にベースキャラを3つから選び、そのベースキャラの3つのアセンダンシー（血統）から1つを選びます。アセンダンシーポイントは2レベルごとに1点（Lv2 で最初の1点）。マイナーノードに振った合計が %s に達するとコアの段が順に開放され、各段で2つのうち1つを選びます。" % "・".join(PackedStringArray(Data.ASC_CORE_REQ.map(func(v): return str(v)))),
		"sections": secs}


static func _passives() -> Dictionary:
	var nodes := PassiveTree.nodes()
	var kinds := [["start", "起点"], ["keystone", "キーストーン"], ["notable", "注目ノード"], ["small", "小ノード"]]
	var secs := []
	for kd in kinds:
		var rows := []
		for id in PassiveTree.order():
			var n: Dictionary = nodes[id]
			if n.kind != kd[0]:
				continue
			var near: Array = n.links.map(func(l): return nodes[l].name)
			rows.append([n.name, "・".join(PackedStringArray(PassiveTree.lines(n.stats))), "%s（%d°）" % [_area(n.step), n.step * 15],
				"、".join(PackedStringArray(near))])
		secs.append({"title": "%s（%d）" % [kd[1], rows.size()], "note": "", "head": ["名前", "効果", "位置", "つながるノード"], "rows": rows})
	return {"file": "passives.md", "title": "パッシブツリー（%dノード）" % nodes.size(),
		"intro": "レベルが上がるたびに1ポイント（Lv N で N−1 ポイント）。ベースキャラごとの起点から、取得済みのノードにつながったノードだけを取れます。位置は中心から見た角度（0°＝右、時計回り）で、近いベースキャラ向けの効果が並びます。",
		"sections": secs}


static func _gems() -> Dictionary:
	var sr := []
	for id in Data.SKILL_ORDER:
		var sk: Dictionary = Data.SKILLS[id]
		sr.append([sk.icon + " " + sk.name, str(sk.lvl), Data.tag_text(sk.tags), Data.cost_text(sk) + ("・CD %s秒" % sk.cd if sk.cd > 0.0 else ""), sk.desc])
	var gr := []
	for g in Data.SUPPORTS:
		var target := Data.tag_text(g.tags) + ("（%sを除く）" % Data.tag_text(g.not) if g.has("not") else "")
		if g.has("need"):
			target += "・%sスキルのみ" % "・".join(PackedStringArray(g.need.map(func(k): return Data.NEED_NAMES[k])))
		gr.append([g.name, str(g.lvl), str(g.energy), target, g.desc])
	return {"file": "gems.md", "title": "スキルジェムとサポートジェム",
		"intro": "初期スキルバー以外のスキルジェムとサポートジェムは、敵のドロップか商人で手に入ります。必要レベルに達するまではスロットに付けたりリンクしたりできません。",
		"sections": [{"title": "スキル（%d）" % sr.size(), "note": "", "head": ["スキル", "必要Lv", "タグ", "コスト", "説明"], "rows": sr},
			{"title": "サポートジェム（%d）" % gr.size(), "note": "リンクの合計エネルギーは 2＋キャラクターレベル＋装備 まで。1スロットにつき最大%d個。" % Data.LINK_MAX,
				"head": ["サポートジェム", "必要Lv", "エネルギー", "対象", "効果"], "rows": gr}]}


## which class's part of the tree an angle step is in, or the two it sits halfway between
static func _area(step: int) -> String:
	var near := []
	for k in PassiveTree.SECTORS:
		var d := absi(posmod(step - PassiveTree.SECTORS[k].step + PassiveTree.STEPS / 2, PassiveTree.STEPS) - PassiveTree.STEPS / 2)
		near.append([d, Data.base_class(k).name])
	near.sort_custom(func(x, y): return x[0] < y[0])
	return "%s・%sの間" % [near[0][1], near[1][1]] if near[0][0] == near[1][0] else near[0][1] + "寄り"


# =================== values ===================
static func _grow(v: float, ilvl: int, sc: float) -> int:
	return maxi(1, roundi(v * (1.0 + ilvl * sc)))


static func _num(v: float) -> String:
	return ("%.1f" % v).trim_suffix(".0")


static func _range_text(lo: int, hi: int) -> String:
	return str(lo) if lo == hi else "%d〜%d" % [lo, hi]


## a signed range: "6〜14", or "-7〜-17" for a drawback (smallest loss first)
static func _signed_range(lo: int, hi: int) -> String:
	if hi < 0:
		return ("-%d" % absi(hi)) if lo == hi else "-%d〜-%d" % [absi(hi), absi(lo)]
	return _range_text(lo, hi)


## an affix's line with a value range in place of the number ("ダメージ +6〜14%", "最大ライフ -7〜-17")
static func _fmt_range(fmt: String, lo: int, hi: int) -> String:
	return _fill(fmt, _signed_range(lo, hi))


## an affix line with `v` in place of its number
static func _fill(fmt: String, v: String) -> String:
	if v.begins_with("-"):
		fmt = fmt.replace("+%d", "%d")
	return fmt.replace("%d", v).replace("%%", "%")


## an affix's name without its number ("ダメージ", "ライフ回復/秒")
static func _stat_name(fmt: String) -> String:
	return fmt.replace(" +%d%%", "").replace(" +%d", "").replace("+%d", "").replace("%%", "%").strip_edges()


static func _stat_text(k: String, v: float) -> String:
	return _fill(Data.affix(k).fmt, _num(v))


## a unique's fixed stat at each shown item level, as Items.roll_fixed rolls it
static func _unique_stat(k: String, r: Array) -> String:
	var a := Data.affix(k)
	var at := func(lv: int) -> String: return _signed_range(roundi(r[0] * (1.0 + lv * a.sc)), roundi(r[1] * (1.0 + lv * a.sc)))
	var later := []
	for lv in UNIQUE_LVLS.slice(1):
		var v: String = at.call(lv)
		later.append("iLv%d で %s%s" % [lv, "" if v.begins_with("-") else "+", v + a.fmt.get_slice("%d", 1).replace("%%", "%")])
	return _fill(a.fmt, at.call(UNIQUE_LVLS[0])) + "（%s）" % "、".join(PackedStringArray(later))


static func _base_text(slot: String, b: Dictionary, unique: bool) -> String:
	var out := []
	if slot == "weapon":
		var m := 1.25 if unique else 1.0
		out.append("ダメージ %d–%d" % [roundi(b.min * 1.22 * m), roundi(b.max * 1.22 * m)] + "（iLv1）")
		out.append("攻撃/秒 %.2f" % b.aps)
	if b.has("armor"):
		out.append("アーマー %d（iLv1）" % roundi(b.armor * 1.2))
	for k in b.get("implicit", {}):
		out.append(_stat_text(k, b.implicit[k]))
	return "・".join(PackedStringArray(out))


# =================== rendering ===================
static func _cell_md(s: String) -> String:
	return s.replace("|", "\\|").replace("\n", "<br>")


static func _md(p: Dictionary) -> String:
	var t := "# %s\n\n%s\n\n%s\n" % [p.title, p.intro, _gen_note()]
	for s in p.sections:
		t += "\n## %s\n\n" % s.title
		if s.note != "":
			t += s.note + "\n\n"
		t += "| " + " | ".join(PackedStringArray(s.head)) + " |\n"
		t += "|" + "---|".repeat(s.head.size()) + "\n"
		for r in s.rows:
			t += "| " + " | ".join(PackedStringArray(r.map(func(c): return _cell_md(str(c))))) + " |\n"
	return t


static func _gen_note() -> String:
	return "> このファイルはゲームのデータから自動生成しています（`godot --headless --path godot -s tools/gen_docs.gd`）。手で編集しないでください。"


static func _index_md(ps: Array) -> String:
	var t := "# Emberfall データベース\n\nゲーム内のデータを人間が読める形にまとめたものです。[index.html](index.html) をブラウザで開くと、すべてのページを1つの画面で検索できます。\n\n%s\n\n" % _gen_note()
	for p in ps:
		var n: int = p.sections.reduce(func(a, s): return a + s.rows.size(), 0)
		t += "- [%s](%s) — %d 件\n" % [p.title, p.file, n]
	return t


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("&lt;br&gt;", "<br>")


static func _html(ps: Array) -> String:
	var tabs := ""
	var body := ""
	for i in ps.size():
		var p: Dictionary = ps[i]
		tabs += "<button data-p=\"%d\"%s>%s</button>" % [i, " class=\"on\"" if i == 0 else "", _esc(p.title)]
		body += "<section data-p=\"%d\"%s><h2>%s</h2><p>%s</p>" % [i, "" if i == 0 else " hidden", _esc(p.title), _esc(p.intro)]
		for s in p.sections:
			body += "<div class=\"tbl\"><h3>%s</h3>" % _esc(s.title)
			if s.note != "":
				body += "<p class=\"note\">%s</p>" % _esc(s.note)
			body += "<table><thead><tr>" + "".join(PackedStringArray(s.head.map(func(h): return "<th>%s</th>" % _esc(h)))) + "</tr></thead><tbody>"
			for r in s.rows:
				body += "<tr>" + "".join(PackedStringArray(r.map(func(c): return "<td>%s</td>" % _esc(str(c))))) + "</tr>"
			body += "</tbody></table></div>"
		body += "</section>\n"
	return """<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Emberfall データベース</title>
<style>
:root{--bg:#14100c;--panel:#1e1812;--line:#3a3024;--text:#e8dcc4;--sub:#a89878;--accent:#ffb347;--hit:#5a3a10}
body{margin:0;background:var(--bg);color:var(--text);font:14px/1.6 "Noto Sans JP","Yu Gothic UI",sans-serif}
header{position:sticky;top:0;background:var(--panel);border-bottom:1px solid var(--line);padding:10px 16px;z-index:1}
h1{margin:0 0 6px;font-size:18px;color:var(--accent)}
nav{display:flex;flex-wrap:wrap;gap:4px;margin-bottom:8px}
nav button{background:var(--bg);color:var(--sub);border:1px solid var(--line);border-radius:4px;padding:3px 8px;cursor:pointer;font:inherit}
nav button.on{color:var(--accent);border-color:var(--accent)}
input{width:100%;max-width:480px;box-sizing:border-box;background:var(--bg);color:var(--text);border:1px solid var(--line);border-radius:4px;padding:5px 8px;font:inherit}
main{padding:0 16px 40px}
h2{color:var(--accent);font-size:17px}h3{font-size:15px;margin:22px 0 4px}
p{color:var(--sub);margin:4px 0}.note{font-size:13px}
table{border-collapse:collapse;width:100%;margin-top:6px}
th,td{border:1px solid var(--line);padding:4px 7px;vertical-align:top;text-align:left}
th{background:var(--panel);color:var(--sub);font-weight:normal;position:sticky;top:0}
td:first-child{color:var(--accent);white-space:nowrap}
tr.hide{display:none}
@media (max-width:700px){td:first-child{white-space:normal}header{position:static}nav{flex-wrap:nowrap;overflow-x:auto}nav button{white-space:nowrap}th{position:static}}
</style></head><body>
<header><h1>Emberfall データベース</h1><nav>""" + tabs + """</nav>
<input id="q" type="search" placeholder="全ページを検索（名前・効果・オプション）"></header>
<main>""" + body + """</main>
<script>
const tabs=[...document.querySelectorAll('nav button')],secs=[...document.querySelectorAll('section')],q=document.getElementById('q');
let cur=0;
// with a search word, every page shows only its matching rows (pages and tables without a match hide)
function show(){const w=q.value.trim().toLowerCase(),any=w!=='';
 secs.forEach((s,i)=>{
  s.querySelectorAll('tbody tr').forEach(r=>r.classList.toggle('hide',any&&!r.textContent.toLowerCase().includes(w)));
  s.querySelectorAll('.tbl').forEach(d=>d.hidden=any&&!d.querySelector('tbody tr:not(.hide)'));
  s.hidden=any?!s.querySelector('tbody tr:not(.hide)'):i!==cur;});}
tabs.forEach((b,i)=>b.onclick=()=>{cur=i;tabs.forEach(x=>x.classList.toggle('on',x===b));q.value='';show();scrollTo(0,0);});
q.oninput=show;
</script></body></html>
"""
