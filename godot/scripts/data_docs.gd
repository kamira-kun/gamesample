class_name DataDocs
extends RefCounted
## The game-data reference (docs/db): uniques, rare items and their affixes, base classes and ascendancies,
## the passive tree and its jewels, and skill and support gems, built from the live tables so it never drifts from the game.
## Every page is a list of sections, each a table; `pages()` renders them as Markdown files and as one
## searchable HTML page. Written by `godot --headless --path . -s tools/gen_docs.gd`; tools/run_check.gd fails
## while the files on disk are out of date.

const DIR := "res://../docs/db/"
const RARE_LVLS := [1, 20, 40, 60]     # item levels the affix tables show
const UNIQUE_LVLS := [1, 40]
const CRAFT_CURRENCIES := ["transmute", "ascend", "chaos", "whet", "purify", "divine", "brand"]
const TABLET_LVLS := [1, 20, 40]
const LINE_CRAFT_LVLS := [1, 4, 8, 9, 13, 16, 17, 23, 29, 40]


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
	ps.append(_tablets())
	ps.append(_charms())
	ps.append(_ascendancies())
	ps.append(_passives())
	ps.append(_jewels())
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
					stats.append(_unique_stat(k, l.mods[k], Data.unique_pow(l.name)))
			else:
				stats.append("ランダムなオプション %d〜%d 個" % Data.RARITY[3].aff)
			rows.append([l.name, Data.UNIQUE_TIERS[Data.unique_tier(l.name)].name, "<br>".join(PackedStringArray(stats)), l.get("desc", ""), l.get("flavor", "")])
		if rows.is_empty():
			continue
		var b: Dictionary = bases[bi]
		secs.append({"title": "%s（%d）" % [b.name, rows.size()], "note": "ベース：" + _base_text(slot, b, true),
			"head": ["名前", "希少度", "能力値（iLv%d）" % UNIQUE_LVLS[0], "固有効果", "フレーバー"],
			"rows": rows})
	var n := Data.LEGENDARY.filter(func(l): return l.slot == slot).size()
	return {"file": "uniques-%s.md" % slot, "title": "ユニーク：%s（%d種）" % [Data.SLOT_INFO[slot].name, n],
		"intro": "レジェンド（ユニーク）は全%d種。レジェンドのドロップはこの一覧から希少度の比重に応じて1つ選ばれます（%s）。希少度が高いほど能力値（プラスの行）と武器ダメージが大きく、相場も高くなります。能力値は範囲内でランダムに決まり、アイテムレベル（iLv＝落ちたエリアのレベル）が高いほど大きくなります（マイナスは代償）。神秘の核で振り直せます。" % [Data.LEGENDARY.size(), _tier_text()],
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
		row.append(str(a.w))
		ar.append(row)
	secs.append({"title": "オプション（接辞）", "note": "マジック・レアのオプションは、部位に付くものから重複なしで、出やすさの重みに比例して選ばれます（出にくいオプションほど取引所の検索で高くなります）。値は (最小〜最大) × (1 + iLv × 伸び率) で、ユニークに付くランダムオプションはさらに ×1.2。",
		"head": ["オプション", "マジックの語"] + RARE_LVLS.map(func(v): return "iLv%d" % v) + ["付く部位", "出やすさ"], "rows": ar})
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
	secs.append(_line_craft("マジック・レアの装備に使えます（インベントリの「一行クラフト」でアイテムを選ぶ）。"))
	return {"file": "rare.md", "title": "レア装備とオプション",
		"intro": "ユニーク以外の装備は、ベースアイテムにランダムなオプションが付いたものです。レアは3〜4個のオプションを持ち、名前はランダムな2語から作られます。",
		"sections": secs}


static func _tablets() -> Dictionary:
	var secs := []
	var sr := []
	for sh in Tablets.SHAPES:
		var t := {"shape": sh.id, "mods": {}}
		var rows := []
		for y in sh.cells.map(func(c): return c[1]).max() + 1:
			var line := ""
			for x in sh.cells.map(func(c): return c[0]).max() + 1:
				line += "■" if sh.cells.any(func(c): return c[0] == x and c[1] == y) else "□"
			rows.append(line)
		sr.append([sh.name, "%d マス" % sh.cells.size(), "%d 行" % Tablets.max_mods(t), "<br>".join(PackedStringArray(rows))])
	secs.append({"title": "石板の形", "note": "盤には90度ずつ回して置けます。刻める行数はマス数で決まります（1〜2マスは1行、3〜4マスは2行、5〜6マスは3行）。",
		"head": ["名前", "大きさ", "刻める行数", "形"], "rows": sr})
	var mr := []
	for m in Tablets.MODS:
		var row := [_fill(Data.affix(m.k).fmt, "#")]
		for lv in TABLET_LVLS:
			for cells in [1, 6]:
				var v: float = m.per * cells * (1.0 + lv * 0.06)
				row.append(_range_text(maxi(1, roundi(v * 0.8)), maxi(1, roundi(v * 1.2))))
		mr.append(row)
	var mh := ["能力"]
	for lv in TABLET_LVLS:
		mh.append_array(["iLv%d 1マス" % lv, "iLv%d 6マス" % lv])
	secs.append({"title": "石板の能力", "note": "値は 1マスあたりの値 × マス数 × (1 + iLv × 0.06) × 0.8〜1.2。大きい石板ほど1行が強くなります。",
		"head": mh, "rows": mr})
	var cr := []
	for c in [["whet", "能力を1行刻む（刻める行数まで）"], ["chaos", "刻んだ能力をすべて刻み直す（行数はそのまま）"], ["divine", "能力の数値だけを振り直す"]]:
		var cd := Data.currency(c[0])
		cr.append([cd.icon + " " + cd.name, c[1]])
	cr.append(["（砕く）", "盤に置いていない石板を灰燼の欠片に変える"])
	secs.append({"title": "石板のクラフト", "note": "石板盤で選んだ石板に使います。", "head": ["カレンシー", "効果"], "rows": cr})
	secs.append(_line_craft("石板盤で選んだ石板の行ごとに使えます。"))
	var xr := []
	for m in Data.SPECIAL_MODS:
		var row := [m.name, _fill(m.fmt, "#")]
		for lv in UNIQUE_LVLS:
			row.append(_range_text(maxi(1, roundi(m.min * (1.0 + lv * m.sc))), maxi(1, roundi(m.max * (1.0 + lv * m.sc)))))
		xr.append(row)
	var b := Data.currency("brand")
	secs.append({"title": "特殊修飾子", "note": "%s %sでレアアイテムに1つだけ刻めます。オプションの数には数えず、混沌の残光でも消えません（浄化の雫で消えます）。もう一度使うと別の特殊修飾子に刻み直します。" % [b.icon, b.name],
		"head": ["名前", "効果"] + UNIQUE_LVLS.map(func(v): return "iLv%d" % v), "rows": xr})
	return {"file": "tablets.md", "title": "石板と特殊修飾子",
		"intro": "石板はボスが必ず1つ落とします（半分は能力を1行刻んだ状態、残りは無地）。6×6の石板盤に回して置き、盤に置いた石板の能力だけが効きます。%sは刻紋の封碑（マップの約%d%%に1つ。封印を解いて番人をすべて倒す）からだけ得られます。" % [b.name, roundi(Seal.CHANCE * 100)],
		"sections": secs}


static func _charms() -> Dictionary:
	var rows := []
	for f in Charms.FAMILIES:
		for t in f.tiers.size():
			var id := Charms.id_of(f.k, t)
			rows.append([Charms.name_of(id), f.name, str(t + 1), Charms.effect_text(id), "◆ %d" % Charms.value(id)])
	return {"file": "charms.md", "title": "燼殻",
		"intro": "燼殻は燼火の甲虫の殻を灯した護符です。遠征図で出撃前に %d つまで（同じ系統は1つまで）はめると、そのマップ1回にだけ効果が加わり、マップに入ると燃え尽きます。マップの敵が落とし（ボス %d%%・エリート %d%%・通常 %s%%）、所持品とスタッシュで重ねて持てます。エリアレベルが高いほど上の階位が出やすくなります。" % [Charms.SLOTS,
			roundi(Charms.drop_chance(true, false) * 100), roundi(Charms.drop_chance(false, true) * 100), _num(Charms.drop_chance(false, false) * 100)],
		"sections": [{"title": "燼殻の一覧", "note": "価値は商人の値付けの基準（灰燼の欠片）です。",
			"head": ["名前", "系統", "階位", "効果", "価値"], "rows": rows}]}


## one-line crafting: what each action does and what it costs by item level
static func _line_craft(where: String) -> Dictionary:
	var rows := []
	for lv in LINE_CRAFT_LVLS:
		var row := ["iLv%d" % lv, LineCraft.tier(lv).name]
		for a in LineCraft.ACTIONS:
			var c := LineCraft.cost(lv, a.k)
			row.append("%s %s ×%d" % [Data.currency(c.k).icon, Data.currency(c.k).name, c.n])
		rows.append(row)
	var acts := "、".join(PackedStringArray(LineCraft.ACTIONS.map(func(a): return "%s（%s）" % [a.name, a.desc])))
	return {"title": "一行クラフト", "note": "%s ほかの行はそのままに、1行だけを %s。アイテムレベルが上がるほど必要数が増え、iLv%d・iLv%d で使うカレンシーが変わります（最大 %d 個）。" % [where, acts, LineCraft.TIERS[1].from, LineCraft.TIERS[2].from, LineCraft.MAX_COST],
		"head": ["アイテムレベル", "帯"] + LineCraft.ACTIONS.map(func(a): return a.name), "rows": rows}


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
	var kinds := [["start", "起点"], ["keystone", "キーストーン"], ["ring_socket", "環晶の大台座"], ["socket", "燈晶の台座"],
		["notable", "注目ノード"], ["small", "小ノード"]]
	var secs := []
	for kd in kinds:
		var rows := []
		for id in PassiveTree.order().slice(0, PassiveTree.base_count()):
			var n: Dictionary = nodes[id]
			if n.kind != kd[0]:
				continue
			var near: Array = n.links.map(func(l): return nodes[l].name)
			rows.append([n.name, "・".join(PackedStringArray(PassiveTree.lines(n.stats))), "%s・第%d層（%d°）" % [PassiveTree.ZONES[n.zone].name, n.layer, roundi(n.ang)],
				"、".join(PackedStringArray(near))])
		secs.append({"title": "%s（%d）" % [kd[1], rows.size()], "note": "", "head": ["名前", "効果", "位置", "つながるノード"], "rows": rows})
	return {"file": "passives.md", "title": "パッシブツリー（%dノード）" % PassiveTree.base_count(),
		"intro": "レベルが上がるたびに1ポイント（Lv N で N−1 ポイント）。ベースキャラごとの起点から、取得済みのノードにつながったノードだけを取れます。ツリーは固定のシードから作られ、中心の環から%d層のクラスター（小ノードの環と、その中の注目ノードか燈晶の台座）が外へ広がり、最外周にキーストーンと環晶の大台座が並びます。位置は 60° ずつ6つの区域（各ベースキャラの区域と、その間の混ざる区域）と層（0＝中心や橋渡し、外ほど大きい）で、注目ノードは外の層ほど強くなります。0°＝右、時計回り。" % PassiveTree.LAYERS,
		"sections": secs, "tree": _tree_data(nodes)}


## the fixed web for the HTML page's map: nodes [x, y, kind, sector, name, effect lines, place, link count] and links as index pairs
static func _tree_data(nodes: Dictionary) -> Dictionary:
	var ids: Array = PassiveTree.order().slice(0, PassiveTree.base_count())
	var idx := {}
	for i in ids.size():
		idx[ids[i]] = i
	var tn := []
	var tl := []
	for i in ids.size():
		var n: Dictionary = nodes[ids[i]]
		tn.append([snappedf(n.pos.x, 0.01), snappedf(n.pos.y, 0.01), n.kind, n.sector, n.name, PassiveTree.lines(n.stats),
			"%s・第%d層（%d°）" % [PassiveTree.ZONES[n.zone].name, n.layer, roundi(n.ang)], n.links.size()])
		for l in n.links:
			if idx[l] > i:
				tl.append([i, idx[l]])
	var cols := {}
	for k in PassiveTree.SECTORS:
		cols[k] = "#" + PassiveTree.SECTORS[k].color.to_html(false)
	return {"nodes": tn, "links": tl, "colors": cols, "kinds": PassiveTree.KIND_NAMES}


static func _jewels() -> Dictionary:
	var secs := []
	var br := []
	for b in Jewels.BASES:
		br.append([b.name, "・".join(PackedStringArray(PassiveTree.lines(b.implicit)))])
	secs.append({"title": "燈晶のベース", "note": "燈晶は燈晶の台座に入れ、その台座ノードを取得している間だけ効きます。レア度はノーマル・マジック・レア（オプション数は装備と同じ）。",
		"head": ["ベース", "固定の能力"], "rows": br})
	var ar := []
	for a in Jewels.AFFIXES:
		var row := [a.word, PassiveTree.FMT[a.k].replace("{v}", "+N")]
		for lv in TABLET_LVLS:
			row.append(_range_text(_grow(a.min, lv, a.sc), _grow(a.max, lv, a.sc)))
		ar.append(row)
	secs.append({"title": "燈晶のオプション（%d）" % ar.size(), "note": "",
		"head": ["語", "能力"] + TABLET_LVLS.map(func(lv): return "iLv%d" % lv), "rows": ar})
	var sr := []
	for sd in Jewels.SIZES:
		sr.append([sd.name, str(sd.smalls), "1" if sd.socket else "なし", "マジック 1・レア %d〜%d" % [mini(2, sd.notables), sd.notables]])
	secs.append({"title": "環晶の大きさ", "note": "環晶は最外周の環晶の大台座に入れると、その先に小ノード・注目ノード・（大環晶なら）燈晶の小台座の環が伸びます。外すと環のノードに振ったポイントは戻ります。",
		"head": ["大きさ", "小ノード", "燈晶の小台座", "注目ノード"], "rows": sr})
	var tr := []
	for th in Jewels.THEMES:
		var ns: Array = th.notables.map(func(n): return "%s（%s）" % [n.name, "・".join(PackedStringArray(PassiveTree.lines(n.stats)))])
		tr.append([th.name, "・".join(PackedStringArray(PassiveTree.lines(th.small.stats))), "<br>".join(PackedStringArray(ns))])
	secs.append({"title": "環晶の主題（%d）" % tr.size(), "note": "小ノードの値は環の強さ（+0〜20%＋iLv×0.6%）だけ大きくなります。",
		"head": ["主題", "小ノード（強さ+0%）", "注目ノード"], "rows": tr})
	var cr := []
	for k in ["transmute", "ascend", "chaos", "whet", "purify", "divine"]:
		cr.append([Data.currency(k).name, {"transmute": "ノーマル→マジック（燈晶はオプション1〜2、環晶は注目ノード1）",
			"ascend": "マジック→レア（燈晶はオプション3〜4まで、環晶は注目ノードを上限まで）", "chaos": "オプションを作り直す（環晶は主題と注目ノード）",
			"whet": "オプション（環晶は注目ノード）を1つ追加", "purify": "ノーマルに戻す", "divine": "数値（環晶は環の強さ）を振り直す"}[k]])
	secs.append({"title": "クラフト", "note": "台座に入れたままでは使えません。", "head": ["カレンシー", "効果"], "rows": cr})
	return {"file": "jewels.md", "title": "ジュエル（燈晶と環晶）",
		"intro": "ジュエルは敵が落とします（ボス60%%、エリート12%%、通常0.6%%。そのうち環晶はボス40%%・ほか15%%）。1キャラクターにつき%d個まで持て、パッシブツリーの画面（%s）で台座に出し入れし、クラフトします。" % [Jewels.MAX_OWNED, "T"],
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


## the unique tiers: how many of the 1000, the drop weight, and the stat scale
static func _tier_text() -> String:
	var counts := {}
	for l in Data.LEGENDARY:
		var t := Data.unique_tier(l.name)
		counts[t] = counts.get(t, 0) + 1
	var out := []
	for i in Data.UNIQUE_TIERS.size():
		var t: Dictionary = Data.UNIQUE_TIERS[i]
		out.append("%s：%d種・比重%s・能力値×%s" % [t.name, counts.get(i, 0), _num(t.w), ("%.2f" % t.pow).trim_suffix("0").trim_suffix(".0")])
	return "、".join(PackedStringArray(out))


## a unique's fixed stat at each shown item level, as Items.roll_fixed rolls it (positive lines scaled by its tier)
static func _unique_stat(k: String, r: Array, power := 1.0) -> String:
	var a := Data.affix(k)
	var m: float = power if r[0] > 0 else 1.0
	var at := func(lv: int) -> String: return _signed_range(roundi(r[0] * (1.0 + lv * a.sc) * m), roundi(r[1] * (1.0 + lv * a.sc) * m))
	var later := []
	for lv in UNIQUE_LVLS.slice(1):
		var v: String = at.call(lv)
		later.append("iLv%d で %s%s" % [lv, "" if v.begins_with("-") else "+", v + a.fmt.get_slice("%d", 1).replace("%%", "%")])
	return _fill(a.fmt, at.call(UNIQUE_LVLS[0])) + "（%s）" % "、".join(PackedStringArray(later))


static func _base_text(slot: String, b: Dictionary, unique: bool) -> String:
	var out := []
	if slot == "weapon":
		var m := 1.25 if unique else 1.0
		out.append("ダメージ %d–%d" % [roundi(b.min * 1.22 * m), roundi(b.max * 1.22 * m)] + ("（iLv1・稀少、希少度で増減）" if unique else "（iLv1）"))
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
		if p.has("tree"):
			body += "<div class=\"tree\"><canvas id=\"tree\"></canvas><div id=\"tip\" hidden></div><button id=\"fit\">全体表示</button></div>"
			body += "<p class=\"note\">ドラッグで移動・ホイール（タッチは2本指）で拡大縮小・ノードにマウスを重ねると効果を表示。検索語に合うノードは光ります。</p>"
			body += "<script id=\"tree-data\" type=\"application/json\">%s</script>" % JSON.stringify(p.tree).replace("</", "<\\/")
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
.tree{position:relative;height:72vh;min-height:360px;margin:12px 0 4px;background:#0a0806;border:1px solid var(--line);border-radius:4px;overflow:hidden}
.tree canvas{display:block;width:100%;height:100%;touch-action:none;cursor:grab}
.tree canvas.drag{cursor:grabbing}
#fit{position:absolute;top:8px;right:8px;background:var(--panel);color:var(--sub);border:1px solid var(--line);border-radius:4px;padding:3px 8px;cursor:pointer;font:inherit}
#tip{position:absolute;pointer-events:none;max-width:280px;background:rgba(20,16,12,.96);border:1px solid var(--line);border-radius:4px;padding:6px 9px;font-size:13px;line-height:1.5}
#tip b{display:block;font-size:14px}#tip .k{color:var(--sub);font-size:12px}#tip .l{color:#e8d8b0}
@media (max-width:700px){td:first-child{white-space:normal}header{position:static}nav{flex-wrap:nowrap;overflow-x:auto}nav button{white-space:nowrap}th{position:static}}
</style></head><body>
<header><h1>Emberfall データベース</h1><nav>""" + tabs + """</nav>
<input id="q" type="search" placeholder="全ページを検索（名前・効果・オプション）"></header>
<main>""" + body + """</main>
<script>
const tabs=[...document.querySelectorAll('nav button')],secs=[...document.querySelectorAll('section')],q=document.getElementById('q');
let cur=0;
// with a search word, every page shows only its matching rows (pages and tables without a match hide;
// the passive page stays while its map lights a node)
function show(){const w=q.value.trim().toLowerCase(),any=w!=='',lit=window.treeFind?treeFind(w):0;
 secs.forEach((s,i)=>{
  s.querySelectorAll('tbody tr').forEach(r=>r.classList.toggle('hide',any&&!r.textContent.toLowerCase().includes(w)));
  s.querySelectorAll('.tbl').forEach(d=>d.hidden=any&&!d.querySelector('tbody tr:not(.hide)'));
  s.hidden=any?!(s.querySelector('tbody tr:not(.hide)')||(lit&&s.querySelector('.tree'))):i!==cur;});}
tabs.forEach((b,i)=>b.onclick=()=>{cur=i;tabs.forEach(x=>x.classList.toggle('on',x===b));q.value='';show();scrollTo(0,0);});
q.oninput=show;
""" + _tree_js() + """</script></body></html>
"""


## the passive page's map: the whole web on a canvas, dragged and zoomed, with the hovered node's effects in a tooltip
static func _tree_js() -> String:
	return """const TD=document.getElementById('tree-data');
if(TD){const T=JSON.parse(TD.textContent),N=T.nodes,cv=document.getElementById('tree'),cx=cv.getContext('2d'),tip=document.getElementById('tip'),box=cv.parentNode;
const R={small:6.5,notable:11,keystone:15,start:13,socket:10,ring_socket:15},U=28;
const EXT=Math.max(...N.map(n=>Math.hypot(n[0],n[1])))+3;
let W=0,H=0,zoom=1,fitZ=1,px=0,py=0,hov=-1,found=null,drag=null;const pts=new Map();
const sx=n=>W/2+px+n[0]*U*zoom,sy=n=>H/2+py+n[1]*U*zoom;
function fit(){fitZ=Math.min(W,H)/(EXT*2*U);zoom=fitZ;px=py=0;}
function size(){const w=cv.clientWidth,h=cv.clientHeight;if(!w||!h)return;const d=devicePixelRatio||1,first=!W;
 W=w;H=h;cv.width=w*d;cv.height=h*d;cx.setTransform(d,0,0,d,0,0);if(first)fit();draw();}
function poly(x,y,r,k,rot){cx.beginPath();for(let i=0;i<k;i++){const a=rot+Math.PI*2*i/k;cx.lineTo(x+Math.cos(a)*r,y+Math.sin(a)*r);}cx.closePath();}
function draw(){if(!W)return;cx.fillStyle='#0a0806';cx.fillRect(0,0,W,H);
 cx.strokeStyle='#3a3024';cx.lineWidth=Math.max(1,2.5*zoom);cx.beginPath();
 for(const[a,b]of T.links){cx.moveTo(sx(N[a]),sy(N[a]));cx.lineTo(sx(N[b]),sy(N[b]));}cx.stroke();
 const lab=[];
 N.forEach((n,i)=>{const x=sx(n),y=sy(n),r=Math.max(1.5,R[n[2]]*zoom);if(x<-r||y<-r||x>W+r||y>H+r)return;
  const sc=T.colors[n[3]]||'#a89878',on=found&&found.has(i);cx.globalAlpha=found&&!on?0.3:1;
  if(on){cx.fillStyle='rgba(255,230,77,.45)';cx.beginPath();cx.arc(x,y,r+6*Math.max(zoom,0.5),0,7);cx.fill();}
  cx.fillStyle=n[2]==='small'?'#15110c':'#2a2016';cx.strokeStyle=i===hov?'#fff':sc;cx.lineWidth=Math.max(1,(n[2]==='small'?1.6:2.5)*zoom);
  if(n[2]==='keystone')poly(x,y,r,8,Math.PI/8);else if(n[2]==='ring_socket')poly(x,y,r,6,Math.PI/6);else if(n[2]==='socket')poly(x,y,r,4,0);
  else{cx.beginPath();cx.arc(x,y,r,0,7);}
  cx.fill();cx.stroke();
  if(n[2]==='notable'&&zoom>=0.5){cx.beginPath();cx.arc(x,y,r*0.6,0,7);cx.lineWidth=Math.max(1,1.2*zoom);cx.stroke();}
  if(n[2]==='start'){cx.beginPath();cx.arc(x,y,r*0.55,0,7);cx.fillStyle=sc;cx.fill();}
  if((['notable','keystone','ring_socket','start'].includes(n[2])&&zoom>=0.8)||(n[2]==='keystone'&&zoom>=0.4)||(on&&zoom>=0.4))lab.push([n[4],x,y+r+4,on]);});
 cx.globalAlpha=1;const fs=Math.max(10,Math.round(12*zoom));cx.font=fs+'px sans-serif';cx.textAlign='center';cx.textBaseline='top';cx.lineWidth=4;cx.lineJoin='round';
 for(const[t,x,y,on]of lab){cx.strokeStyle='rgba(0,0,0,.9)';cx.strokeText(t,x,y);cx.fillStyle=on?'#ffe8b0':'#b8a888';cx.fillText(t,x,y);}}
function hit(mx,my){let best=-1,bd=1e9;N.forEach((n,i)=>{const d=Math.hypot(sx(n)-mx,sy(n)-my);if(d<(R[n[2]]+4)*Math.max(zoom,0.8)&&d<bd){bd=d;best=i;}});return best;}
function el(tag,cls,text,color){const e=document.createElement(tag);if(cls)e.className=cls;e.textContent=text;if(color)e.style.color=color;return e;}
function hover(mx,my){const i=hit(mx,my);if(i!==hov){hov=i;draw();}
 if(i<0){tip.hidden=true;return;}const n=N[i],k=T.kinds[n[2]]||'';tip.replaceChildren(el('b','',n[4],T.colors[n[3]]));
 if(k&&k!==n[4])tip.append(el('div','k',k));n[5].forEach(l=>tip.append(el('div','l',l)));if(!n[5].length&&n[2]!=='start')tip.append(el('div','k','効果なし'));
 tip.append(el('div','k',n[6]+'・つながり '+n[7]));tip.hidden=false;
 const tw=tip.offsetWidth,th=tip.offsetHeight;tip.style.left=Math.min(mx+14,W-tw-4)+'px';tip.style.top=(my+14+th>H?my-th-10:my+14)+'px';}
function zoomAt(mx,my,f){const z=Math.min(Math.max(zoom*f,fitZ*0.6),fitZ*12);const k=z/zoom;px=(px-mx+W/2)*k+mx-W/2;py=(py-my+H/2)*k+my-H/2;zoom=z;draw();}
const pos=e=>{const r=cv.getBoundingClientRect();return[e.clientX-r.left,e.clientY-r.top];};
cv.addEventListener('wheel',e=>{e.preventDefault();const[x,y]=pos(e);zoomAt(x,y,Math.exp(-e.deltaY*0.0015));hover(x,y);},{passive:false});
cv.addEventListener('pointerdown',e=>{cv.setPointerCapture(e.pointerId);pts.set(e.pointerId,pos(e));if(pts.size===1)drag={x:e.clientX,y:e.clientY,moved:false};});
cv.addEventListener('pointermove',e=>{const p=pos(e);
 if(pts.size===2&&pts.has(e.pointerId)){const o=[...pts.entries()].find(([id])=>id!==e.pointerId)[1],q0=pts.get(e.pointerId);
  const d0=Math.hypot(q0[0]-o[0],q0[1]-o[1]),d1=Math.hypot(p[0]-o[0],p[1]-o[1]);pts.set(e.pointerId,p);if(d0>0)zoomAt((p[0]+o[0])/2,(p[1]+o[1])/2,d1/d0);if(drag)drag.moved=true;return;}
 if(pts.has(e.pointerId))pts.set(e.pointerId,p);
 if(drag&&pts.size===1){const dx=e.clientX-drag.x,dy=e.clientY-drag.y;if(drag.moved||Math.hypot(dx,dy)>3){drag.moved=true;cv.classList.add('drag');px+=dx;py+=dy;drag.x=e.clientX;drag.y=e.clientY;tip.hidden=true;draw();return;}}
 if(e.pointerType==='mouse'&&!drag)hover(p[0],p[1]);});
function up(e){const p=pos(e);pts.delete(e.pointerId);if(pts.size)return;if(drag&&!drag.moved)hover(p[0],p[1]);drag=null;cv.classList.remove('drag');}
cv.addEventListener('pointerup',up);cv.addEventListener('pointercancel',up);
cv.addEventListener('pointerleave',e=>{if(e.pointerType==='mouse'&&!drag){hov=-1;tip.hidden=true;draw();}});
document.getElementById('fit').onclick=()=>{fit();draw();};
window.treeFind=w=>{found=w?new Set(N.flatMap((n,i)=>(n[4]+' '+n[5].join(' ')+' '+(T.kinds[n[2]]||'')).toLowerCase().includes(w)?[i]:[])):null;draw();return found?found.size:0;};
new ResizeObserver(size).observe(cv);}
"""
