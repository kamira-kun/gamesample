extends Node
## Static game data (autoload "Data"). Ported from the browser version's data.js.

var ui_font: SystemFont

# every skill, in the order the skill panel lists them; `lvl` is the character level a skill gem needs before it
# goes on the bar. beyond a base class's starting bar, skill gems are found (enemy drops) or bought (the merchant)
const SKILL_ORDER := ["slash", "fireball", "nova", "chain", "meteor", "dash", "throw_knives", "firebolt",
	"skeleton", "heavy_strike", "thrust", "frost_bolt", "sparks",
	"ice_spear", "wide_cleave", "double_slash", "flame_nova",
	"whirl", "flame_strike", "shield_bash", "ice_shards", "thunderbolt", "leap_slam",
	"ground_slam", "punch_wave", "ice_pillars", "hex_frail", "blink",
	"storm", "frost_blade", "flame_jet", "shock_nova", "war_cry",
	"thunder_strike", "void_bolt", "hex_mire", "spirit_wolves",
	"venom_strike", "frost_axe", "lightning_lance", "tailwind",
	"glacial_hammer", "ball_thunder", "miasma", "arcane_surge",
	"blade_tempest", "fire_rain", "stone_skin", "stone_golem",
	"fire_wheel", "frost_vortex", "earthquake", "soul_wisps", "blood_rage",
	"blade_rain", "blizzard", "phantom_host", "comet", "fissure", "doom",
	"hearth_ward", "ember_heart", "frost_veil", "gale_hymn", "crimson_pact"]
const SKILLS := {
	"slash": {"name": "斬撃", "icon": "⚔", "mana": 0, "cd": 0.0, "attack": true, "color": Color("#c9b48a"), "lvl": 1,
		"tags": ["attack", "melee"], "desc": "前方の敵を薙ぎ払う。攻撃速度の影響を受ける。"},
	"whirl": {"name": "旋風斬", "icon": "✲", "mana": 4, "cd": 0.0, "attack": true, "color": Color("#e0c070"), "lvl": 4,
		"tags": ["attack", "melee", "aoe"], "desc": "その場で回転し、周囲の敵すべてを斬りつける。攻撃速度の影響を受ける。"},
	"fireball": {"name": "ファイアボール", "icon": "✹", "mana": 6, "cd": 0.0, "cast": 0.42, "color": Color("#ff7a2a"), "lvl": 1,
		"tags": ["spell", "projectile", "aoe", "fire"], "desc": "着弾時に爆発する火球を放つ。"},
	"ice_spear": {"name": "アイススピア", "icon": "➶", "mana": 8, "cd": 0.0, "cast": 0.35, "color": Color("#9fe8ff"), "lvl": 3,
		"tags": ["spell", "projectile", "cold"], "desc": "敵を貫通する氷の槍を放ち、短時間凍結させる。"},
	"nova": {"name": "フロストノヴァ", "icon": "❄", "mana": 16, "cd": 0.0, "cast": 0.5, "color": Color("#7fd4ff"), "lvl": 1,
		"tags": ["spell", "aoe", "cold"], "desc": "周囲に冷気を放ち、敵を凍結させる。"},
	"chain": {"name": "チェインライトニング", "icon": "ϟ", "mana": 12, "cd": 0.0, "cast": 0.4, "color": Color("#c9a8ff"), "lvl": 1,
		"tags": ["spell", "chain", "lightning"], "desc": "カーソル付近の敵に雷を放ち、次々と連鎖する。"},
	"storm": {"name": "サンダーストーム", "icon": "☈", "mana": 24, "cd": 0.0, "cast": 0.75, "color": Color("#b0a0ff"), "lvl": 6,
		"tags": ["spell", "aoe", "lightning", "duration"], "desc": "カーソル位置に雷雲を呼び、範囲内の敵に落雷を降らせ続ける。"},
	"meteor": {"name": "メテオ", "icon": "☄", "mana": 30, "cd": 0.0, "cast": 0.9, "color": Color("#ff4d2a"), "lvl": 1,
		"tags": ["spell", "aoe", "fire", "duration"], "desc": "カーソル位置に隕石を落とし、地面を燃やす。"},
	"dash": {"name": "シャドウダッシュ", "icon": "➤", "mana": 8, "cd": 2.5, "color": Color("#9a8cff"), "lvl": 1,
		"tags": ["attack", "movement"], "kinds": ["move"], "desc": "カーソル方向へ駆け抜け、通過した敵を切り裂く。移動中は無敵。"},
	"skeleton": {"name": "骸骨召喚", "icon": "☠", "mana": 20, "cd": 0.0, "cast": 0.6, "color": Color("#e8e0c8"), "lvl": 1,
		"tags": ["spell", "minion"], "desc": "戦う骸骨の戦士を2体呼び出す（最大3体）。骸骨は近くの敵に斬りかかる。"},
	# ---- skills built from effect blocks (`fx`); main.gd resolves each block by its `k` ----
	# arc: swing in front / slam: circle in front / line: lane toward the cursor / nova: circle around the caster
	# area: telegraphed circles at the cursor / proj: projectiles / chain: jumping bolt / zone: ticking area
	# buff: timed self buff / curse: marks enemies / summon: minions / move: dash with an optional landing
	# `sup` on a skill adds built-in support modifiers (ailment chances, knockback)
	"heavy_strike": {"name": "重撃", "icon": "⚒", "mana": 3, "cd": 0.0, "attack": true, "color": Color("#d8b888"), "lvl": 1,
		"tags": ["attack", "melee"], "desc": "正面の狭い範囲に重い一撃を叩き込む。",
		"anim": ["2H_Melee_Attack_Chop", 1.8], "fx": [{"k": "arc", "reach": 3.0, "half": 0.6, "coef": 1.7, "type": "phys"}]},
	"wide_cleave": {"name": "大薙ぎ", "icon": "☾", "mana": 4, "cd": 0.0, "attack": true, "color": Color("#e0c890"), "lvl": 3,
		"tags": ["attack", "melee", "aoe"], "desc": "大きく武器を振るい、前方の広い範囲を薙ぎ払う。",
		"anim": ["2H_Melee_Attack_Slice", 1.8], "fx": [{"k": "arc", "reach": 4.2, "half": 1.7, "coef": 0.85, "type": "phys"}]},
	"thrust": {"name": "刺突", "icon": "↣", "mana": 3, "cd": 0.0, "attack": true, "color": Color("#e8d8b0"), "lvl": 2,
		"tags": ["attack", "melee"], "desc": "一直線に突き、貫いた敵すべてを傷つける。",
		"anim": ["1H_Melee_Attack_Stab", 2.2], "fx": [{"k": "line", "len": 5.5, "w": 1.2, "coef": 1.25, "type": "phys"}]},
	"ground_slam": {"name": "大地砕き", "icon": "⛰", "mana": 6, "cd": 0.0, "attack": true, "color": Color("#c8a070"), "lvl": 5,
		"tags": ["attack", "melee", "aoe"], "desc": "前方の地面を叩き割り、周囲の敵を巻き込む。",
		"anim": ["2H_Melee_Attack_Chop", 1.6], "fx": [{"k": "slam", "dist": 2.6, "r": 3.0, "coef": 1.25, "type": "phys"}]},
	"flame_strike": {"name": "炎刃", "icon": "✢", "mana": 5, "cd": 0.0, "attack": true, "color": Color("#ff8a40"), "lvl": 4,
		"tags": ["attack", "melee", "aoe", "fire"], "desc": "炎をまとった斬撃。切っ先で小さな爆発が起きる。",
		"anim": ["1H_Melee_Attack_Slice_Diagonal", 2.0], "fx": [{"k": "arc", "reach": 3.2, "half": 1.0, "coef": 0.9, "type": "fire"},
			{"k": "slam", "dist": 3.0, "r": 2.0, "coef": 0.6, "type": "fire"}]},
	"frost_blade": {"name": "霜の刃", "icon": "❅", "mana": 5, "cd": 0.0, "attack": true, "color": Color("#9fe0ff"), "lvl": 6,
		"tags": ["attack", "melee", "projectile", "cold"], "desc": "冷気の斬撃とともに、敵を貫く氷の刃を3本放つ。",
		"anim": ["1H_Melee_Attack_Slice_Horizontal", 2.2], "fx": [{"k": "arc", "reach": 3.0, "half": 0.9, "coef": 0.9, "type": "cold"},
			{"k": "proj", "n": 3, "spread": 0.22, "speed": 26.0, "life": 0.45, "coef": 0.4, "type": "cold", "pierce": true, "shape": "blade"}]},
	"thunder_strike": {"name": "雷打", "icon": "↯", "mana": 6, "cd": 0.0, "attack": true, "color": Color("#d0b8ff"), "lvl": 7,
		"tags": ["attack", "melee", "lightning", "chain"], "desc": "雷を帯びた一撃。カーソル付近の敵から雷が3回連鎖する。",
		"anim": ["1H_Melee_Attack_Chop", 2.0], "fx": [{"k": "arc", "reach": 3.0, "half": 0.8, "coef": 1.0, "type": "light"},
			{"k": "chain", "n": 3, "coef": 0.5, "type": "light"}]},
	"venom_strike": {"name": "毒牙", "icon": "☣", "mana": 5, "cd": 0.0, "attack": true, "color": Color("#8fd060"), "lvl": 8,
		"tags": ["attack", "melee", "chaos"], "desc": "毒を塗った刃で斬りつける混沌の攻撃。高確率で敵を毒に冒す。",
		"anim": ["Dualwield_Melee_Attack_Stab", 2.0], "sup": {"poison": 0.6},
		"fx": [{"k": "arc", "reach": 3.0, "half": 0.9, "coef": 1.1, "type": "chaos"}]},
	"double_slash": {"name": "双閃", "icon": "✕", "mana": 3, "cd": 0.0, "attack": true, "color": Color("#f0e0b8"), "lvl": 3,
		"tags": ["attack", "melee"], "desc": "素早く2回斬りつける。",
		"anim": ["Dualwield_Melee_Attack_Slice", 2.2], "fx": [{"k": "arc", "reach": 3.0, "half": 1.0, "coef": 0.65, "type": "phys"},
			{"k": "arc", "reach": 3.0, "half": 1.0, "coef": 0.65, "type": "phys", "wait": 0.15}]},
	"blade_tempest": {"name": "旋刃嵐", "icon": "✴", "mana": 10, "cd": 0.0, "attack": true, "color": Color("#e8d090"), "lvl": 10,
		"tags": ["attack", "melee", "aoe", "duration"], "desc": "2秒間、自分の周りを刃の嵐が回り続け、触れた敵を何度も切り刻む。",
		"anim": ["2H_Melee_Attack_Spinning", 1.6], "fx": [{"k": "zone", "at": "follow", "r": 3.6, "dur": 2.0, "every": 0.25, "coef": 0.32, "type": "phys"}]},
	"earthquake": {"name": "地鳴り", "icon": "≋", "mana": 9, "cd": 0.0, "attack": true, "color": Color("#b89060"), "lvl": 12,
		"tags": ["attack", "melee", "aoe"], "desc": "地面を叩き、1秒後に足元で大きな余震を起こす。",
		"anim": ["2H_Melee_Attack_Chop", 1.5], "fx": [{"k": "slam", "dist": 1.5, "r": 3.0, "coef": 0.8, "type": "phys"},
			{"k": "area", "at": "self", "r": 5.5, "delay": 1.0, "coef": 1.6, "type": "phys"}]},
	"shield_bash": {"name": "盾打ち", "icon": "⛨", "mana": 3, "cd": 0.0, "attack": true, "color": Color("#c0c8d0"), "lvl": 4,
		"tags": ["attack", "melee"], "desc": "盾で殴りつけて敵を吹き飛ばし、一瞬動きを止める。",
		"anim": ["Block_Attack", 2.0], "sup": {"knock": 2.5},
		"fx": [{"k": "arc", "reach": 2.8, "half": 0.8, "coef": 0.8, "type": "phys", "freeze": 0.5}]},
	"glacial_hammer": {"name": "氷槌", "icon": "❆", "mana": 6, "cd": 0.0, "attack": true, "color": Color("#a8e8ff"), "lvl": 9,
		"tags": ["attack", "melee", "aoe", "cold"], "desc": "冷気をまとった槌を振り下ろし、周囲の敵を凍結させる。",
		"anim": ["2H_Melee_Attack_Chop", 1.6], "fx": [{"k": "slam", "dist": 2.2, "r": 2.3, "coef": 1.4, "type": "cold", "freeze": 0.6}]},
	"throw_knives": {"name": "投げナイフ", "icon": "➹", "mana": 2, "cd": 0.0, "attack": true, "color": Color("#d0d0d8"), "lvl": 1,
		"tags": ["attack", "projectile"], "desc": "3本のナイフを扇状に投げる。命中した敵を出血させることがある。",
		"anim": ["Throw", 2.4], "sup": {"bleed": 0.25},
		"fx": [{"k": "proj", "n": 3, "spread": 0.14, "speed": 30.0, "life": 0.6, "coef": 0.55, "type": "phys", "shape": "blade"}]},
	"blade_rain": {"name": "刃の雨", "icon": "⇊", "mana": 8, "cd": 0.0, "attack": true, "color": Color("#c8c8d8"), "lvl": 13,
		"tags": ["attack", "aoe"], "desc": "カーソル付近に無数の刃を降らせる。",
		"anim": ["Throw", 2.0], "fx": [{"k": "area", "n": 5, "scatter": 2.6, "r": 1.6, "delay": 0.35, "coef": 0.5, "type": "phys"}]},
	"frost_axe": {"name": "氷斧投げ", "icon": "⟲", "mana": 6, "cd": 0.0, "attack": true, "color": Color("#9fd8ff"), "lvl": 8,
		"tags": ["attack", "projectile", "aoe", "cold"], "desc": "冷気の斧を投げつける。着弾点で砕けて周囲を凍らせる。",
		"anim": ["Throw", 2.0], "fx": [{"k": "proj", "speed": 22.0, "life": 0.9, "coef": 1.2, "type": "cold", "boom": 2.3, "freeze": 0.4, "size": 0.3}]},
	"punch_wave": {"name": "拳圧", "icon": "◎", "mana": 3, "cd": 0.0, "attack": true, "color": Color("#f0d8a8"), "lvl": 5,
		"tags": ["attack", "projectile"], "desc": "拳の風圧を飛ばし、直線上の敵すべてを打つ。",
		"anim": ["Unarmed_Melee_Attack_Punch_A", 2.2], "fx": [{"k": "proj", "speed": 30.0, "life": 0.5, "coef": 1.1, "type": "phys", "pierce": true, "shape": "wave"}]},
	"firebolt": {"name": "火矢", "icon": "➝", "mana": 4, "cd": 0.0, "cast": 0.3, "color": Color("#ff9a50"), "lvl": 1,
		"tags": ["spell", "projectile", "fire"], "desc": "素早く小さな火の矢を放つ。",
		"anim": ["Spellcast_Shoot", 2.4], "fx": [{"k": "proj", "speed": 32.0, "life": 0.8, "coef": 1.1, "type": "fire", "size": 0.2}]},
	"frost_bolt": {"name": "氷弾", "icon": "✳", "mana": 6, "cd": 0.0, "cast": 0.42, "color": Color("#9fe8ff"), "lvl": 2,
		"tags": ["spell", "projectile", "cold"], "desc": "ゆっくり進む氷の弾。敵を貫通し、わずかに凍結させる。",
		"anim": ["Spellcast_Shoot", 2.0], "fx": [{"k": "proj", "speed": 20.0, "life": 1.2, "coef": 1.35, "type": "cold", "pierce": true, "freeze": 0.3, "shape": "spear"}]},
	"sparks": {"name": "迸る火花", "icon": "✧", "mana": 6, "cd": 0.0, "cast": 0.4, "color": Color("#d8c8ff"), "lvl": 2,
		"tags": ["spell", "projectile", "lightning"], "desc": "不規則に揺れ動く雷の火花を4つ放つ。",
		"anim": ["Spellcast_Shoot", 2.0], "fx": [{"k": "proj", "n": 4, "spread": 0.4, "speed": 17.0, "life": 1.5, "coef": 0.45, "type": "light", "wander": 3.0, "size": 0.15}]},
	"ball_thunder": {"name": "雷球", "icon": "◉", "mana": 12, "cd": 0.0, "cast": 0.5, "color": Color("#c0a8ff"), "lvl": 9,
		"tags": ["spell", "projectile", "aoe", "lightning"], "desc": "ゆっくり進む雷の球。進路の周囲の敵に雷を落とし続ける。",
		"anim": ["Spellcast_Shoot", 1.8], "fx": [{"k": "proj", "speed": 7.0, "life": 2.6, "coef": 0.0, "type": "light", "pierce": true, "size": 0.45,
			"pulse": {"every": 0.3, "r": 3.5, "coef": 0.35}}]},
	"void_bolt": {"name": "虚無の矢", "icon": "✪", "mana": 9, "cd": 0.0, "cast": 0.45, "color": Color("#a070e0"), "lvl": 7,
		"tags": ["spell", "projectile", "chaos"], "desc": "敵を追いかける混沌の矢を放つ。",
		"anim": ["Spellcast_Shoot", 2.0], "fx": [{"k": "proj", "speed": 24.0, "life": 1.1, "coef": 1.6, "type": "chaos", "homing": 3.0}]},
	"flame_jet": {"name": "火炎放射", "icon": "≫", "mana": 6, "cd": 0.0, "cast": 0.3, "color": Color("#ff7a30"), "lvl": 6,
		"tags": ["spell", "fire"], "desc": "前方に炎を噴き出す。敵を燃焼させることがある。",
		"anim": ["Spellcast_Shoot", 2.4], "sup": {"burn": 0.3}, "fx": [{"k": "line", "len": 7.0, "w": 2.2, "coef": 0.85, "type": "fire"}]},
	"ice_shards": {"name": "氷片の扇", "icon": "⋔", "mana": 6, "cd": 0.0, "cast": 0.35, "color": Color("#bff0ff"), "lvl": 4,
		"tags": ["spell", "projectile", "cold"], "desc": "5本の氷片を扇状に放つ。",
		"anim": ["Spellcast_Shoot", 2.2], "fx": [{"k": "proj", "n": 5, "spread": 0.18, "speed": 28.0, "life": 0.5, "coef": 0.5, "type": "cold", "shape": "spear"}]},
	"lightning_lance": {"name": "雷光の槍", "icon": "⇶", "mana": 9, "cd": 0.0, "cast": 0.4, "color": Color("#e0d0ff"), "lvl": 8,
		"tags": ["spell", "lightning"], "desc": "長い直線上を雷光で一瞬にして貫く。",
		"anim": ["Spellcast_Shoot", 2.0], "fx": [{"k": "line", "len": 14.0, "w": 1.1, "coef": 1.45, "type": "light"}]},
	"soul_wisps": {"name": "彷徨う魂", "icon": "∴", "mana": 10, "cd": 0.0, "cast": 0.45, "color": Color("#b090f0"), "lvl": 12,
		"tags": ["spell", "projectile", "chaos"], "desc": "敵を追い続ける3つの魂を解き放つ。",
		"anim": ["Spellcast_Raise", 2.0], "fx": [{"k": "proj", "n": 3, "spread": 0.8, "speed": 11.0, "life": 2.6, "coef": 0.65, "type": "chaos", "homing": 4.0}]},
	"fire_wheel": {"name": "火輪", "icon": "✺", "mana": 10, "cd": 0.0, "cast": 0.5, "color": Color("#ffa050"), "lvl": 11,
		"tags": ["spell", "projectile", "fire"], "desc": "全方位に10発の火球を放つ。",
		"anim": ["Spellcast_Raise", 2.0], "fx": [{"k": "proj", "n": 10, "ring": true, "speed": 18.0, "life": 0.6, "coef": 0.5, "type": "fire"}]},
	"comet": {"name": "彗星", "icon": "✶", "mana": 22, "cd": 0.0, "cast": 0.8, "color": Color("#a0e8ff"), "lvl": 14,
		"tags": ["spell", "aoe", "cold"], "desc": "少し遅れてカーソル位置に氷の彗星が落ち、敵を凍結させる。",
		"anim": ["Spellcast_Long", 1.8], "fx": [{"k": "area", "r": 3.5, "delay": 0.9, "coef": 3.0, "type": "cold", "freeze": 0.8}]},
	"flame_nova": {"name": "炎環", "icon": "☀", "mana": 9, "cd": 0.0, "cast": 0.4, "color": Color("#ff8840"), "lvl": 3,
		"tags": ["spell", "aoe", "fire"], "desc": "自分を中心に炎の輪を放つ。",
		"anim": ["Spellcast_Raise", 2.2], "fx": [{"k": "nova", "r": 6.0, "coef": 1.15, "type": "fire"}]},
	"shock_nova": {"name": "雷環", "icon": "❂", "mana": 10, "cd": 0.0, "cast": 0.4, "color": Color("#c8b0ff"), "lvl": 6,
		"tags": ["spell", "aoe", "lightning"], "desc": "自分を中心に雷の輪を放ち、敵を感電させやすい。",
		"anim": ["Spellcast_Raise", 2.2], "sup": {"shock": 0.5}, "fx": [{"k": "nova", "r": 7.0, "coef": 1.0, "type": "light"}]},
	"ice_pillars": {"name": "氷柱", "icon": "▲", "mana": 9, "cd": 0.0, "cast": 0.5, "color": Color("#b0f0ff"), "lvl": 5,
		"tags": ["spell", "aoe", "cold"], "desc": "カーソル付近の地面から3本の氷柱を突き上げる。",
		"anim": ["Spellcast_Raise", 2.0], "fx": [{"k": "area", "n": 3, "scatter": 2.2, "r": 1.8, "delay": 0.5, "coef": 1.0, "type": "cold", "freeze": 0.4}]},
	"fire_rain": {"name": "火の雨", "icon": "⁂", "mana": 18, "cd": 0.0, "cast": 0.6, "color": Color("#ff6a2a"), "lvl": 10,
		"tags": ["spell", "aoe", "fire", "duration"], "desc": "3秒間、カーソル位置に火の雨を降らせる。",
		"anim": ["Spellcast_Long", 2.0], "fx": [{"k": "zone", "r": 5.0, "dur": 3.0, "every": 0.25, "coef": 0.65, "type": "fire", "strike": true}]},
	"blizzard": {"name": "吹雪", "icon": "❉", "mana": 18, "cd": 0.0, "cast": 0.6, "color": Color("#d0f4ff"), "lvl": 13,
		"tags": ["spell", "aoe", "cold", "duration"], "desc": "4秒間、カーソル位置に吹雪を起こし、範囲内の敵を減速させる。",
		"anim": ["Spellcast_Long", 2.0], "fx": [{"k": "zone", "r": 6.0, "dur": 4.0, "every": 0.4, "coef": 0.35, "type": "cold", "slow": 1.0}]},
	"thunderbolt": {"name": "落雷", "icon": "⌁", "mana": 7, "cd": 0.0, "cast": 0.45, "color": Color("#e0d0ff"), "lvl": 4,
		"tags": ["spell", "aoe", "lightning"], "desc": "カーソル位置に雷を落とす。",
		"anim": ["Spellcast_Raise", 2.2], "fx": [{"k": "area", "r": 2.2, "delay": 0.25, "coef": 2.0, "type": "light", "bolt": true}]},
	"miasma": {"name": "瘴気の雲", "icon": "☁", "mana": 14, "cd": 0.0, "cast": 0.5, "color": Color("#90c060"), "lvl": 9,
		"tags": ["spell", "aoe", "chaos", "duration"], "desc": "5秒間残る毒の雲を生み出す。中の敵は毒に冒されやすい。",
		"anim": ["Spellcast_Long", 2.0], "sup": {"poison": 0.5}, "fx": [{"k": "zone", "r": 4.0, "dur": 5.0, "every": 0.5, "coef": 0.25, "type": "chaos"}]},
	"fissure": {"name": "灼熱の地割れ", "icon": "≡", "mana": 14, "cd": 0.0, "cast": 0.55, "color": Color("#ff6a20"), "lvl": 15,
		"tags": ["spell", "fire"], "desc": "前方へ長い地割れを走らせ、溶岩で敵を焼く。燃焼させやすい。",
		"anim": ["Spellcast_Long", 2.0], "sup": {"burn": 0.4}, "fx": [{"k": "line", "len": 12.0, "w": 1.7, "coef": 1.35, "type": "fire"}]},
	"frost_vortex": {"name": "冷気の渦", "icon": "⊛", "mana": 14, "cd": 0.0, "cast": 0.5, "color": Color("#90d8ff"), "lvl": 11,
		"tags": ["spell", "aoe", "cold", "duration"], "desc": "周囲に冷気を放ち、その場に3秒間残る冷気の渦を作る。",
		"anim": ["Spellcast_Raise", 2.0], "fx": [{"k": "nova", "r": 4.0, "coef": 0.9, "type": "cold"},
			{"k": "zone", "at": "self", "r": 4.0, "dur": 3.0, "every": 0.4, "coef": 0.25, "type": "cold", "slow": 0.6}]},
	"doom": {"name": "破滅の宣告", "icon": "✠", "mana": 30, "cd": 0.0, "cast": 0.9, "color": Color("#9050d0"), "lvl": 18,
		"tags": ["spell", "aoe", "chaos"], "desc": "1.5秒後、カーソル位置に壊滅的な混沌の爆発を起こす。",
		"anim": ["Spellcast_Long", 1.6], "fx": [{"k": "area", "r": 4.0, "delay": 1.5, "coef": 5.0, "type": "chaos"}]},
	"hex_frail": {"name": "脆弱の呪い", "icon": "⌘", "mana": 10, "cd": 0.0, "cast": 0.4, "color": Color("#c070c0"), "lvl": 5,
		"tags": ["spell", "curse", "aoe", "duration"], "desc": "範囲内の敵を6秒間呪い、受けるダメージを25%増やす。",
		"anim": ["Spellcast_Shoot", 2.2], "fx": [{"k": "curse", "r": 5.0, "dur": 6.0, "vuln": 0.25}]},
	"hex_mire": {"name": "泥濘の呪い", "icon": "⌇", "mana": 10, "cd": 0.0, "cast": 0.4, "color": Color("#80a070"), "lvl": 7,
		"tags": ["spell", "curse", "aoe", "duration"], "desc": "範囲内の敵を6秒間呪って減速させ、受けるダメージを10%増やす。",
		"anim": ["Spellcast_Shoot", 2.2], "fx": [{"k": "curse", "r": 6.0, "dur": 6.0, "vuln": 0.1, "slow": true}]},
	"war_cry": {"name": "鬨の声", "icon": "❢", "mana": 12, "cd": 0.0, "cast": 0.35, "color": Color("#ffb060"), "lvl": 6,
		"tags": ["buff", "aoe", "duration"], "desc": "雄叫びで周囲の敵を押し返し、6秒間ダメージ +25%。",
		"anim": ["Cheer", 2.0], "sup": {"knock": 2.0},
		"fx": [{"k": "nova", "r": 5.0, "coef": 0.4, "type": "phys"}, {"k": "buff", "dur": 6.0, "stats": {"dmg": 25}}]},
	"tailwind": {"name": "疾風の加護", "icon": "»", "mana": 16, "cd": 0.0, "cast": 0.3, "color": Color("#a0f0c0"), "lvl": 8,
		"tags": ["buff", "duration"], "desc": "8秒間、攻撃速度・詠唱速度 +20%、移動速度 +15%。",
		"anim": ["Spellcast_Raise", 2.4], "fx": [{"k": "buff", "dur": 8.0, "stats": {"atk_spd": 20, "cast_spd": 20, "move": 15}}]},
	"stone_skin": {"name": "岩肌", "icon": "▣", "mana": 14, "cd": 0.0, "cast": 0.3, "color": Color("#b0a080"), "lvl": 10,
		"tags": ["buff", "duration"], "desc": "6秒間、受けるダメージ -25%、毎秒ライフの2%を回復。",
		"anim": ["Block", 2.0], "fx": [{"k": "buff", "dur": 6.0, "stats": {"dr": 25, "regen": 2}}]},
	"blood_rage": {"name": "血の狂乱", "icon": "♥", "mana": 10, "cd": 0.0, "cast": 0.3, "color": Color("#ff5050"), "lvl": 12,
		"tags": ["buff", "duration"], "desc": "8秒間、ダメージ +30%、攻撃速度 +15%。",
		"anim": ["Cheer", 2.2], "fx": [{"k": "buff", "dur": 8.0, "stats": {"dmg": 30, "atk_spd": 15}}]},
	"arcane_surge": {"name": "秘力の奔流", "icon": "❖", "mana": 12, "cd": 0.0, "cast": 0.3, "color": Color("#8fb0ff"), "lvl": 9,
		"tags": ["buff", "duration"], "desc": "6秒間、詠唱速度 +25%、ダメージ +15%。",
		"anim": ["Spellcast_Raise", 2.4], "fx": [{"k": "buff", "dur": 6.0, "stats": {"cast_spd": 25, "dmg": 15}}]},
	"stone_golem": {"name": "岩の巨兵", "icon": "⛫", "mana": 30, "cd": 0.0, "cast": 0.7, "color": Color("#b8a888"), "lvl": 10,
		"tags": ["spell", "minion"], "desc": "頑丈で一撃の重い巨兵を1体呼び出す（最大1体）。",
		"anim": ["Spellcast_Long", 1.8], "fx": [{"k": "summon", "n": 1, "max": 1, "life": 3.0, "coef": 1.6, "dur": 0.0, "scale": 1.5}]},
	"spirit_wolves": {"name": "霊狼", "icon": "♞", "mana": 18, "cd": 0.0, "cast": 0.5, "color": Color("#a0d0ff"), "lvl": 7,
		"tags": ["spell", "minion", "duration"], "desc": "20秒間戦う霊の戦士を2体呼び出す（最大4体）。",
		"anim": ["Spellcast_Raise", 2.0], "fx": [{"k": "summon", "n": 2, "max": 4, "life": 0.7, "coef": 0.6, "dur": 20.0, "scale": 0.8}]},
	"phantom_host": {"name": "亡霊の軍勢", "icon": "☗", "mana": 22, "cd": 0.0, "cast": 0.6, "color": Color("#c0b0e0"), "lvl": 13,
		"tags": ["spell", "minion", "duration"], "desc": "8秒間だけ戦う亡霊を3体呼び出す（最大6体）。",
		"anim": ["Spellcast_Long", 2.0], "fx": [{"k": "summon", "n": 3, "max": 6, "life": 0.4, "coef": 0.5, "dur": 8.0, "scale": 0.9}]},
	"blink": {"name": "瞬歩", "icon": "⇢", "mana": 8, "cd": 3.0, "color": Color("#c8b8ff"), "lvl": 5,
		"tags": ["spell", "movement", "lightning"], "desc": "カーソル方向へ一瞬で移動し、到着点で放電する。",
		"anim": ["Spellcast_Shoot", 3.0], "fx": [{"k": "move", "dist": 9.0, "speed": 220.0, "coef": 0.0, "land": {"r": 3.0, "coef": 0.6, "type": "light"}}]},
	# ---- auras: toggled on and off; while on they reserve part of max life or mana (`res`: pct of the pool
	# plus a flat amount) and give their `stats` to the player and to allies within `r` meters ----
	"hearth_ward": {"name": "炉辺の守り火", "icon": "☖", "mana": 0, "cd": 0.0, "cast": 0.3, "color": Color("#ffc878"), "lvl": 3,
		"tags": ["aura"], "desc": "オーラ。自分と周囲の味方は毎秒ライフの1.5%を回復し、受けるダメージ -4%。",
		"anim": ["Spellcast_Raise", 2.4], "aura": {"r": 9.0, "pool": "mana", "pct": 0, "flat": 30, "stats": {"regen": 1.5, "dr": 4}}},
	"ember_heart": {"name": "熾火の鼓動", "icon": "♨", "mana": 0, "cd": 0.0, "cast": 0.3, "color": Color("#ff8a4a"), "lvl": 5,
		"tags": ["aura"], "desc": "オーラ。自分と周囲の味方のダメージ +18%。",
		"anim": ["Spellcast_Raise", 2.4], "aura": {"r": 9.0, "pool": "mana", "pct": 30, "flat": 0, "stats": {"dmg": 18}}},
	"frost_veil": {"name": "霜紗の帳", "icon": "◈", "mana": 0, "cd": 0.0, "cast": 0.3, "color": Color("#a8e4ff"), "lvl": 8,
		"tags": ["aura"], "desc": "オーラ。自分と周囲の味方の受けるダメージ -10%、移動速度 +6%。",
		"anim": ["Spellcast_Raise", 2.4], "aura": {"r": 9.0, "pool": "mana", "pct": 25, "flat": 0, "stats": {"dr": 10, "move": 6}}},
	"gale_hymn": {"name": "風詠みの讃歌", "icon": "≈", "mana": 0, "cd": 0.0, "cast": 0.3, "color": Color("#b0f0c8"), "lvl": 11,
		"tags": ["aura"], "desc": "オーラ。自分と周囲の味方の攻撃速度・詠唱速度 +12%。",
		"anim": ["Spellcast_Raise", 2.4], "aura": {"r": 9.0, "pool": "mana", "pct": 25, "flat": 0, "stats": {"atk_spd": 12, "cast_spd": 12}}},
	"crimson_pact": {"name": "紅血の誓約", "icon": "♦", "mana": 0, "cd": 0.0, "cast": 0.3, "color": Color("#ff4a5a"), "lvl": 14,
		"tags": ["aura"], "desc": "オーラ。ライフを捧げ、自分と周囲の味方のダメージ +14%、攻撃速度 +6%。",
		"anim": ["Cheer", 2.2], "aura": {"r": 9.0, "pool": "life", "pct": 20, "flat": 0, "stats": {"dmg": 14, "atk_spd": 6}}},
	"leap_slam": {"name": "跳躍斬", "icon": "⤴", "mana": 8, "cd": 4.0, "color": Color("#e0b880"), "lvl": 4,
		"tags": ["attack", "movement", "aoe"], "desc": "カーソル方向へ跳び、着地点の周囲を叩き斬る。",
		"anim": ["Jump_Full_Short", 1.6], "fx": [{"k": "move", "dist": 8.0, "speed": 28.0, "coef": 0.0, "land": {"r": 3.5, "coef": 1.4, "type": "phys"}}]},
}
const TAG_NAMES := {"attack": "攻撃", "melee": "近接", "spell": "スペル", "projectile": "投射", "aoe": "範囲", "fire": "火炎",
	"cold": "冷気", "lightning": "雷", "chain": "連鎖", "movement": "移動", "minion": "ミニオン", "chaos": "混沌", "duration": "持続",
	"curse": "呪い", "buff": "強化", "aura": "オーラ"}

# the six skill bar slots and the skills they start with
const SLOT_COUNT := 6   # bound to the actions skill_1..skill_6 (see Keybinds)
const DEFAULT_SLOTS := ["slash", "fireball", "nova", "chain", "meteor", "dash"]

# support gems are linked to a skill slot and change how that skill behaves while it resolves.
# every linked gem costs `energy` out of the player's pool, so links are spread across the bar as the player likes.
# `tags`: the skill needs one of them; `not`: it must have none. `mul`/`add`/`max` adjust the support modifiers.
# `lvl`: the character level the gem needs before it can be linked
const SUPPORTS := [
	{"id": "power", "name": "威力増幅", "color": Color("#ff9a6a"), "energy": 3, "lvl": 1, "tags": ["attack", "spell"], "desc": "ダメージ +30%（ミニオンにも有効）／マナコスト +30%",
		"mul": {"dmg": 1.3, "mana": 1.3}},
	{"id": "haste", "name": "加速", "color": Color("#8fd18f"), "energy": 3, "lvl": 1, "tags": ["attack", "spell"], "desc": "攻撃・詠唱速度 +25%（トーテム・ミニオンにも有効）",
		"mul": {"speed": 1.25, "mana": 1.1}},
	{"id": "multi", "name": "多重投射", "color": Color("#9fd8ff"), "energy": 3, "lvl": 1, "tags": ["projectile"], "desc": "投射物 +2／ダメージ -20%",
		"add": {"proj": 2}, "mul": {"dmg": 0.8, "mana": 1.2}},
	{"id": "aoe", "name": "範囲拡大", "color": Color("#ffd36a"), "energy": 2, "lvl": 2, "tags": ["aoe"], "desc": "効果範囲 +35%",
		"mul": {"aoe": 1.35, "mana": 1.15}},
	{"id": "chain_s", "name": "連鎖増幅", "color": Color("#c9a8ff"), "energy": 3, "lvl": 4, "tags": ["chain"], "desc": "連鎖回数 +3",
		"add": {"chain": 3}, "mul": {"mana": 1.2}},
	{"id": "leech", "name": "生命吸収", "color": Color("#ff6a6a"), "energy": 1, "lvl": 1, "tags": ["attack", "spell"], "desc": "与えたダメージの3%をライフとして回復",
		"add": {"leech": 0.03}},
	{"id": "frostbite", "name": "凍結付与", "color": Color("#bff4ff"), "energy": 1, "lvl": 3, "tags": ["attack", "spell"], "desc": "命中した敵を0.4秒凍結させる",
		"max": {"freeze": 0.4}, "mul": {"mana": 1.1}},
	{"id": "totem", "name": "トーテム化", "color": Color("#d8a060"), "energy": 3, "lvl": 8, "tags": ["spell"], "not": ["minion", "movement", "buff"],
		"desc": "スキルの代わりにカーソル位置へトーテムを設置。トーテムが10秒間スキルを自動で放つ（最大2本）／ダメージ -15%",
		"add": {"totem": 1}, "mul": {"dmg": 0.85}},
	{"id": "minion_power", "name": "ミニオン強化", "color": Color("#e8e0c8"), "energy": 3, "lvl": 2, "tags": ["minion"], "desc": "ミニオンのライフ +50%、ダメージ +30%",
		"mul": {"mlife": 1.5, "dmg": 1.3}},
	{"id": "swarm", "name": "軍勢", "color": Color("#b8b0a0"), "energy": 3, "lvl": 6, "tags": ["minion"], "desc": "ミニオンの最大数 +2",
		"add": {"mcount": 2}, "mul": {"mana": 1.2}},
	# damage by type and conversion
	{"id": "brutal", "name": "残虐", "color": Color("#e8d8c0"), "energy": 2, "lvl": 3, "tags": ["attack", "spell", "buff"], "desc": "物理ダメージ +40%", "mul": {"m_phys": 1.4, "mana": 1.15}},
	{"id": "fire_amp", "name": "火炎増幅", "color": Color("#ff8a40"), "energy": 2, "lvl": 3, "tags": ["attack", "spell", "buff"], "desc": "火炎ダメージ +35%", "mul": {"m_fire": 1.35, "mana": 1.15}},
	{"id": "cold_amp", "name": "冷気増幅", "color": Color("#8fdcff"), "energy": 2, "lvl": 3, "tags": ["attack", "spell", "buff"], "desc": "冷気ダメージ +35%", "mul": {"m_cold": 1.35, "mana": 1.15}},
	{"id": "light_amp", "name": "雷撃増幅", "color": Color("#d9b8ff"), "energy": 2, "lvl": 3, "tags": ["attack", "spell", "buff"], "desc": "雷ダメージ +35%", "mul": {"m_light": 1.35, "mana": 1.15}},
	{"id": "chaos_amp", "name": "混沌増幅", "color": Color("#90d060"), "energy": 2, "lvl": 8, "tags": ["attack", "spell", "buff"], "desc": "混沌ダメージ +35%", "mul": {"m_chaos": 1.35, "mana": 1.15}},
	{"id": "conv_fire", "name": "灼熱変換", "color": Color("#ff7030"), "energy": 2, "lvl": 10, "tags": ["attack", "spell"], "desc": "物理ダメージを火炎ダメージに変換し、ダメージ +10%", "set": {"conv": "fire"}, "mul": {"dmg": 1.1}},
	{"id": "conv_cold", "name": "氷結変換", "color": Color("#80d0ff"), "energy": 2, "lvl": 10, "tags": ["attack", "spell"], "desc": "物理ダメージを冷気ダメージに変換し、ダメージ +10%", "set": {"conv": "cold"}, "mul": {"dmg": 1.1}},
	{"id": "conv_light", "name": "雷電変換", "color": Color("#c8a8ff"), "energy": 2, "lvl": 10, "tags": ["attack", "spell"], "desc": "物理ダメージを雷ダメージに変換し、ダメージ +10%", "set": {"conv": "light"}, "mul": {"dmg": 1.1}},
	{"id": "conv_chaos", "name": "虚無変換", "color": Color("#9060c0"), "energy": 3, "lvl": 16, "tags": ["attack", "spell"], "desc": "すべてのダメージを混沌ダメージに変換し、ダメージ +15%", "set": {"conv": "chaos"}, "mul": {"dmg": 1.15, "mana": 1.1}},
	# critical strikes
	{"id": "crit_chance", "name": "急所狙い", "color": Color("#ffe060"), "energy": 2, "lvl": 5, "tags": ["attack", "spell"], "desc": "クリティカル率 +8%", "add": {"crit": 8.0}, "mul": {"mana": 1.1}},
	{"id": "crit_dmg", "name": "会心増幅", "color": Color("#ffc040"), "energy": 3, "lvl": 12, "tags": ["attack", "spell"], "desc": "クリティカルダメージ +45%", "add": {"critm": 45.0}, "mul": {"mana": 1.1}},
	# projectiles (need a skill that fires projectiles from an effect block)
	{"id": "pspeed", "name": "高速投射", "color": Color("#a0e0ff"), "energy": 1, "lvl": 2, "tags": ["projectile"], "need": ["proj"], "desc": "投射物の速度 +60%、ダメージ +10%", "mul": {"pspeed": 1.6, "dmg": 1.1}},
	{"id": "pierce", "name": "貫通", "color": Color("#c0e8ff"), "energy": 1, "lvl": 4, "tags": ["projectile"], "need": ["proj"], "desc": "投射物が敵を貫通する／ダメージ -10%", "add": {"pierce": 1}, "mul": {"dmg": 0.9}},
	{"id": "homing", "name": "追尾", "color": Color("#b0c8ff"), "energy": 1, "lvl": 5, "tags": ["projectile"], "need": ["proj"], "desc": "投射物が近くの敵を追いかける", "add": {"homing": 4.0}, "mul": {"mana": 1.1}},
	{"id": "fork", "name": "分岐", "color": Color("#90e0d0"), "energy": 3, "lvl": 9, "tags": ["projectile"], "need": ["proj"], "desc": "投射物が最初に命中したとき、左右2つに分かれる", "add": {"fork": 1}, "mul": {"mana": 1.15}},
	{"id": "pchain", "name": "跳弾", "color": Color("#c0b0ff"), "energy": 3, "lvl": 10, "tags": ["projectile"], "need": ["proj"], "desc": "投射物が命中後、別の敵へ2回まで跳ね返る／ダメージ -10%", "add": {"pchain": 2}, "mul": {"dmg": 0.9, "mana": 1.15}},
	{"id": "volley", "name": "弾幕", "color": Color("#8fd8ff"), "energy": 3, "lvl": 14, "tags": ["projectile"], "desc": "投射物 +4／ダメージ -35%", "add": {"proj": 4}, "mul": {"dmg": 0.65, "mana": 1.3}},
	# area and duration
	{"id": "conc", "name": "集中", "color": Color("#ffc870"), "energy": 3, "lvl": 6, "tags": ["aoe"], "desc": "効果範囲 -25%、ダメージ +35%", "mul": {"aoe": 0.75, "dmg": 1.35, "mana": 1.15}},
	{"id": "wide", "name": "広域", "color": Color("#ffe090"), "energy": 3, "lvl": 9, "tags": ["aoe"], "desc": "効果範囲 +60%／ダメージ -15%", "mul": {"aoe": 1.6, "dmg": 0.85, "mana": 1.2}},
	{"id": "dur_long", "name": "持続延長", "color": Color("#a0d8a0"), "energy": 1, "lvl": 3, "tags": ["duration"], "desc": "効果時間 +50%", "mul": {"dur": 1.5, "mana": 1.15}},
	{"id": "dur_short", "name": "瞬間集中", "color": Color("#d8e0a0"), "energy": 2, "lvl": 7, "tags": ["duration"], "desc": "効果時間 -30%、ダメージ +30%", "mul": {"dur": 0.7, "dmg": 1.3, "mana": 1.1}},
	{"id": "aftershock", "name": "余波", "color": Color("#e8b070"), "energy": 3, "lvl": 11, "tags": ["aoe"], "need": ["area", "nova", "slam"], "desc": "範囲攻撃の0.5秒後、同じ場所に小さな余波（範囲70%・ダメージ50%）が起きる", "add": {"after": 1}, "mul": {"mana": 1.2}},
	{"id": "extra", "name": "増殖", "color": Color("#f0c880"), "energy": 3, "lvl": 13, "tags": ["aoe"], "need": ["area", "zone"], "desc": "設置・落下する範囲の数 +1／ダメージ -10%", "add": {"extra": 1}, "mul": {"dmg": 0.9, "mana": 1.25}},
	# ailments
	{"id": "ignite_s", "name": "燃焼付与", "color": Color("#ff9050"), "energy": 2, "lvl": 4, "tags": ["attack", "spell"], "desc": "命中時30%で燃焼させ、3秒かけてヒットの50%の火炎ダメージ", "add": {"burn": 0.3}, "mul": {"mana": 1.1}},
	{"id": "shock_s", "name": "感電付与", "color": Color("#d0b8ff"), "energy": 2, "lvl": 4, "tags": ["attack", "spell"], "desc": "命中時35%で4秒間感電させる（受けるダメージ +20%）", "add": {"shock": 0.35}, "mul": {"mana": 1.1}},
	{"id": "chill_s", "name": "冷気付与", "color": Color("#a8e0ff"), "energy": 1, "lvl": 1, "tags": ["attack", "spell"], "desc": "命中した敵を1.5秒間減速させる", "max": {"chill": 1.5}, "mul": {"mana": 1.05}},
	{"id": "bleed_s", "name": "出血付与", "color": Color("#d04040"), "energy": 2, "lvl": 4, "tags": ["attack"], "desc": "命中時35%で出血させ、4秒かけてヒットの60%の物理ダメージ", "add": {"bleed": 0.35}, "mul": {"mana": 1.1}},
	{"id": "poison_s", "name": "毒付与", "color": Color("#80c050"), "energy": 2, "lvl": 6, "tags": ["attack", "spell"], "desc": "命中時40%で毒を与え、3秒かけてヒットの30%の混沌ダメージ（重複する）", "add": {"poison": 0.4}, "mul": {"mana": 1.1}},
	{"id": "stun_s", "name": "衝撃", "color": Color("#e0d0a0"), "energy": 1, "lvl": 2, "tags": ["attack"], "desc": "命中時25%で敵を0.4秒行動不能にする", "add": {"stun": 0.25}},
	# on hit / on kill
	{"id": "cull", "name": "処刑", "color": Color("#c0a0a0"), "energy": 1, "lvl": 8, "tags": ["attack", "spell"], "desc": "ボス以外のライフ12%以下の敵を即座に倒す", "max": {"cull": 0.12}, "mul": {"mana": 1.1}},
	{"id": "knock", "name": "吹き飛ばし", "color": Color("#d8d0b0"), "energy": 1, "lvl": 1, "tags": ["attack", "spell", "buff"], "desc": "命中した敵（ボス以外）を押し返す", "add": {"knock": 2.0}},
	{"id": "kboom", "name": "誘爆", "color": Color("#ff7050"), "energy": 3, "lvl": 11, "tags": ["attack", "spell"], "desc": "このスキルで倒した敵が爆発し、周囲にダメージを与える", "add": {"kboom": 1}, "mul": {"mana": 1.2}},
	{"id": "mleech", "name": "魔力吸収", "color": Color("#7aa8ff"), "energy": 1, "lvl": 5, "tags": ["attack", "spell"], "desc": "与えたダメージの2%をマナとして回復", "add": {"mleech": 0.02}},
	{"id": "loh", "name": "生命の刻印", "color": Color("#ff8080"), "energy": 1, "lvl": 1, "tags": ["attack", "spell"], "desc": "敵に命中するたびライフを4回復", "add": {"loh": 4.0}},
	{"id": "hexhit", "name": "呪詛の刃", "color": Color("#c080c0"), "energy": 1, "lvl": 6, "tags": ["attack", "spell"], "desc": "命中した敵を3秒間呪い、受けるダメージ +15%", "max": {"hex": 0.15}, "mul": {"mana": 1.1}},
	# conditional damage
	{"id": "lowlife", "name": "背水", "color": Color("#ff6060"), "energy": 2, "lvl": 9, "tags": ["attack", "spell"], "desc": "ライフ50%以下の間、ダメージ +60%", "add": {"lowlife": 0.6}},
	{"id": "elite", "name": "狩人の印", "color": Color("#ffb070"), "energy": 2, "lvl": 7, "tags": ["attack", "spell"], "desc": "エリートとボスへのダメージ +40%", "add": {"elite": 0.4}},
	{"id": "close", "name": "肉薄", "color": Color("#f0b080"), "energy": 2, "lvl": 5, "tags": ["attack", "spell"], "desc": "4.5m以内の敵へのダメージ +35%", "add": {"close": 0.35}},
	{"id": "vsfrozen", "name": "砕氷", "color": Color("#b8f0ff"), "energy": 2, "lvl": 8, "tags": ["attack", "spell"], "desc": "凍結・減速中の敵へのダメージ +45%", "add": {"vsfrozen": 0.45}},
	# speed and cost
	{"id": "efficient", "name": "効率化", "color": Color("#90b8ff"), "energy": 1, "lvl": 2, "tags": ["attack", "spell", "buff", "aura"], "desc": "マナコスト・オーラのリザーブ -40%／ダメージ -10%", "mul": {"mana": 0.6, "dmg": 0.9}},
	{"id": "heavy", "name": "渾身", "color": Color("#e09060"), "energy": 3, "lvl": 9, "tags": ["attack", "spell"], "desc": "ダメージ +50%／攻撃・詠唱速度 -20%", "mul": {"dmg": 1.5, "speed": 0.8, "mana": 1.2}},
	{"id": "rapid", "name": "連打", "color": Color("#a0e0a0"), "energy": 2, "lvl": 7, "tags": ["attack", "spell"], "not": ["movement"], "desc": "攻撃・詠唱速度 +40%／ダメージ -20%", "mul": {"speed": 1.4, "dmg": 0.8, "mana": 1.1}},
	{"id": "echo", "name": "残響", "color": Color("#c0d0ff"), "energy": 3, "lvl": 10, "tags": ["attack", "spell"], "not": ["minion", "movement", "buff"], "desc": "0.25秒後にもう一度発動する（2回目のダメージ -30%）", "add": {"echo": 1}, "mul": {"mana": 1.4}},
	{"id": "trap", "name": "罠化", "color": Color("#c8a070"), "energy": 3, "lvl": 10, "tags": ["attack", "spell"], "not": ["minion", "movement", "buff"],
		"desc": "スキルの代わりにカーソル位置へ罠を設置。敵が近づくとスキルを1回発動する（最大3個、12秒）", "add": {"trap": 1}, "mul": {"dmg": 1.2}},
	# minions, curses, buffs, movement
	{"id": "minion_speed", "name": "迅速の僕", "color": Color("#d0e8c0"), "energy": 1, "lvl": 4, "tags": ["minion"], "desc": "ミニオンの攻撃速度 +30%", "mul": {"speed": 1.3, "mana": 1.1}},
	{"id": "minion_tough", "name": "鋼の僕", "color": Color("#c8c0b0"), "energy": 1, "lvl": 5, "tags": ["minion"], "desc": "ミニオンのライフ +100%／ダメージ -10%", "mul": {"mlife": 2.0, "dmg": 0.9}},
	{"id": "curse_eff", "name": "呪詛強化", "color": Color("#d070d0"), "energy": 1, "lvl": 7, "tags": ["curse"], "desc": "呪いの効果 +50%", "mul": {"ceff": 1.5, "mana": 1.2}},
	{"id": "buff_eff", "name": "鼓舞", "color": Color("#ffd080"), "energy": 1, "lvl": 5, "tags": ["buff", "aura"], "desc": "強化・オーラスキルの効果 +40%（オーラのリザーブ +20%）", "mul": {"beff": 1.4, "mana": 1.2}},
	{"id": "move_far", "name": "長駆", "color": Color("#b0b0ff"), "energy": 1, "lvl": 3, "tags": ["movement"], "desc": "移動距離 +40%", "mul": {"mdist": 1.4}},
	{"id": "move_land", "name": "着地衝撃", "color": Color("#e0c0a0"), "energy": 1, "lvl": 6, "tags": ["movement"], "desc": "移動の終点で衝撃波を起こし、周囲に物理ダメージ", "add": {"mland": 1}, "mul": {"mana": 1.2}},
]
const DEFAULT_GEMS := ["power", "haste"]
const LINK_MAX := 6
const GEM_COLOR := Color("#7fe0a0")


## the energy pool every linked support gem draws on: 2 + character level, plus gear
static func energy_base(level: int) -> int:
	return 2 + level


## skill gems and support gems a character doesn't own yet, needing at most level `max_lvl`
static func missing_gems(skills: Array, gems: Array, max_lvl := 999) -> Array:
	var out := []
	for id in SKILL_ORDER:
		if not id in skills and SKILLS[id].lvl <= max_lvl:
			out.append({"skill": true, "id": id})
	for g in SUPPORTS:
		if not g.id in gems and g.lvl <= max_lvl:
			out.append({"skill": false, "id": g.id})
	return out


## a skill gem's or support gem's name, color and level, for drops and the merchant
static func gem_info(skill: bool, id: String) -> Dictionary:
	if skill:
		var sk: Dictionary = SKILLS[id]
		return {"name": sk.name, "color": sk.color, "lvl": sk.lvl, "kind": "スキルジェム"}
	var g := support(id)
	return {"name": g.name, "color": g.color, "lvl": g.lvl, "kind": "サポートジェム"}


static func support(id: String) -> Dictionary:
	for g in SUPPORTS:
		if g.id == id:
			return g
	return {}


static func support_fits(g: Dictionary, skill_id: String) -> bool:
	var sk: Dictionary = SKILLS[skill_id]
	var tags: Array = sk.tags
	if g.has("need"):
		var kinds: Array = sk.get("kinds", []) + sk.get("fx", []).map(func(b): return b.k)
		if not g.need.any(func(k): return k in kinds):
			return false
	return g.tags.any(func(t): return t in tags) and not g.get("not", []).any(func(t): return t in tags)


# what a support's `need` asks for, for its tooltip
const NEED_NAMES := {"proj": "投射物を放つ", "area": "範囲を指定する", "nova": "周囲に放つ", "slam": "前方を叩く", "zone": "持続範囲を置く", "move": "移動する"}


## what using a skill costs, for tooltips and the skill list: mana per use, or what an aura reserves
static func cost_text(sk: Dictionary) -> String:
	if sk.has("aura"):
		var a: Dictionary = sk.aura
		var amt := ("%d%%" % a.pct) if a.pct > 0 else ""
		if a.flat > 0:
			amt += ("+%d" if amt != "" else "%d") % a.flat
		return "リザーブ：%s %s" % ["ライフ" if a.pool == "life" else "マナ", amt]
	return "マナ %d" % sk.mana


static func tag_text(tags: Array) -> String:
	return "・".join(tags.map(func(t): return TAG_NAMES[t]))


## the support modifiers a slot's linked gems give its skill (gems that don't fit are skipped)
static func build_sup(skill_id: String, ids: Array) -> Dictionary:
	var s := {"dmg": 1.0, "mana": 1.0, "speed": 1.0, "proj": 0, "aoe": 1.0, "chain": 0, "leech": 0.0, "freeze": 0.0,
		"totem": 0, "mlife": 1.0, "mcount": 0, "ids": [], "skill": skill_id,
		"m_phys": 1.0, "m_fire": 1.0, "m_cold": 1.0, "m_light": 1.0, "m_chaos": 1.0, "conv": "", "crit": 0.0, "critm": 0.0,
		"pspeed": 1.0, "pierce": 0, "homing": 0.0, "fork": 0, "pchain": 0, "dur": 1.0, "after": 0, "extra": 0,
		"burn": 0.0, "shock": 0.0, "chill": 0.0, "bleed": 0.0, "poison": 0.0, "stun": 0.0, "cull": 0.0, "knock": 0.0, "kboom": 0,
		"mleech": 0.0, "loh": 0.0, "hex": 0.0, "lowlife": 0.0, "elite": 0.0, "close": 0.0, "vsfrozen": 0.0,
		"echo": 0, "trap": 0, "ceff": 1.0, "beff": 1.0, "mdist": 1.0, "mland": 0}
	if skill_id == "":
		return s
	# a skill's own built-in modifiers (its ailment chances, knockback)
	var own: Dictionary = SKILLS[skill_id].get("sup", {})
	for k in own:
		s[k] += own[k]
	for id in ids:
		var g := support(id)
		if g.is_empty() or not support_fits(g, skill_id):
			continue
		for k in g.get("mul", {}):
			s[k] *= g.mul[k]
		for k in g.get("add", {}):
			s[k] += g.add[k]
		for k in g.get("max", {}):
			s[k] = maxf(s[k], g.max[k])
		for k in g.get("set", {}):
			s[k] = g.set[k]
		s.ids.append(id)
	return s

# radii and ranges are in meters (one dungeon tile = 2 m)
const ENEMY_TYPES := {
	"imp": {"name": "インプ", "r": 0.45, "life": 10, "dmg": 4, "speed": 6.8, "color": Color("#c4523a"), "atk_range": 0.6, "atk_cd": 0.9, "windup": 0.2, "xp": 4, "h": 1.0},
	"ghoul": {"name": "グール", "r": 0.55, "life": 18, "dmg": 7, "speed": 4.6, "color": Color("#7a9a5a"), "atk_range": 0.7, "atk_cd": 1.2, "windup": 0.3, "xp": 6, "h": 1.7},
	"archer": {"name": "骸骨弓兵", "r": 0.5, "life": 14, "dmg": 6, "speed": 4.2, "color": Color("#d8d0b8"), "ranged": true, "range": 15.0, "atk_cd": 1.9, "windup": 0.45, "xp": 7, "h": 1.8},
	"brute": {"name": "ブルート", "r": 0.9, "life": 60, "dmg": 16, "speed": 3.3, "color": Color("#8a5a9a"), "atk_range": 1.2, "atk_cd": 2.4, "windup": 0.75, "aoe": 3.2, "xp": 16, "h": 2.8},
	"shaman": {"name": "呪術師", "r": 0.5, "life": 16, "dmg": 11, "speed": 3.9, "color": Color("#4fb0c0"), "caster": true, "range": 15.0, "atk_cd": 3.2, "windup": 0.9, "xp": 10, "h": 1.9},
	"boss": {"name": "深淵の番人", "r": 1.5, "life": 650, "dmg": 20, "speed": 3.7, "color": Color("#b03030"), "boss": true, "atk_range": 1.6, "atk_cd": 1.6, "windup": 0.4, "xp": 220, "h": 4.1},
	"colossus": {"name": "灼熱の巨像", "r": 1.8, "life": 820, "dmg": 24, "speed": 3.2, "color": Color("#7a3a22"), "boss": true, "atk_range": 2.2, "atk_cd": 1.8, "windup": 0.5, "xp": 260, "h": 5.0},
	"witch": {"name": "凍嵐の魔女", "r": 1.0, "life": 600, "dmg": 18, "speed": 5.2, "color": Color("#3a6a9a"), "boss": true, "atk_range": 1.6, "atk_cd": 1.5, "windup": 0.4, "xp": 260, "h": 2.9},
}

# the boss of a map follows its theme
const BOSS_ROTATION := [
	{"type": "boss", "guards": ["ghoul", "ghoul", "ghoul", "ghoul"]},
	{"type": "colossus", "guards": ["imp", "imp", "imp", "brute"]},
	{"type": "witch", "guards": ["archer", "archer", "shaman", "shaman"]},
]

# ascendancy: pick one of the three lineages of the character's base class (CLASSES), spend the points levels
# give on its minor nodes; points spent there unlock its core tiers, and in each unlocked tier one of two core
# talents is chosen (and can be swapped freely). A core's `stats` are added like a minor node's; its id is
# also an effect key the game checks in player.effects
const ASC_CORE_REQ := [2, 5, 8]
const ASCENDANCIES := [
	{"k": "pyre", "name": "焔王", "icon": "♨", "color": Color("#ff8a3a"), "desc": "炎の呪文で戦場を焼き尽くす王。火炎スペルと詠唱速度に特化。",
		"minors": [
			{"id": "pyre_heat", "name": "焦熱", "fmt": "火炎ダメージ +{v}%", "max": 3, "stats": {"fire_dmg": 8}},
			{"id": "pyre_chant", "name": "速詠", "fmt": "詠唱速度 +{v}%", "max": 3, "stats": {"cast_spd": 5}},
			{"id": "pyre_furnace", "name": "魔力炉", "fmt": "最大マナ +{v}", "max": 3, "stats": {"mana": 15, "mana_regen": 0.6}},
			{"id": "pyre_mantle", "name": "灼熱の衣", "fmt": "最大ライフ +{v}", "max": 3, "stats": {"life": 18}},
		],
		"cores": [
			[{"id": "ignite", "name": "燃焼の刻印", "desc": "火炎ヒットが敵を燃焼させ、3秒かけてヒットの40%のダメージを与える"},
				{"id": "fire_cost", "name": "焔の循環", "desc": "火炎スキルのマナコスト -35%"}],
			[{"id": "kill_burst", "name": "紅蓮の余波", "desc": "火炎ダメージで倒した敵が爆発し、周囲に火炎ダメージを与える"},
				{"id": "spell_frenzy", "name": "熾火の高揚", "desc": "スペルで敵を倒すたび4秒間 詠唱速度 +5%（最大8重）"}],
			[{"id": "inferno", "name": "劫火", "desc": "火炎スキルの範囲 +30%、燃える地面の持続 2倍"},
				{"id": "chant_power", "name": "烈火の詠唱", "desc": "詠唱速度のボーナスと同じだけスペルダメージが増加する"}],
		]},
	{"k": "blade", "name": "剣聖", "icon": "⚔", "color": Color("#e8c870"), "desc": "鍛え抜いた剣技で敵を斬り伏せる達人。攻撃スキルと耐久に特化。",
		"minors": [
			{"id": "blade_art", "name": "剣技", "fmt": "攻撃ダメージ +{v}%", "max": 3, "stats": {"atk_dmg": 8}},
			{"id": "blade_gale", "name": "疾風", "fmt": "攻撃速度 +{v}%", "max": 3, "stats": {"atk_spd": 5}},
			{"id": "blade_body", "name": "鋼の肉体", "fmt": "最大ライフ +{v}", "max": 3, "stats": {"life": 20}},
			{"id": "blade_guard", "name": "堅守", "fmt": "アーマー +{v}", "max": 3, "stats": {"armor": 15}},
		],
		"cores": [
			[{"id": "blood_oath", "name": "血の誓い", "desc": "攻撃ダメージの3%をライフとして吸収する"},
				{"id": "third_strike", "name": "三連の型", "desc": "攻撃スキル3回目ごとに、その攻撃が必ずクリティカルになる"}],
			[{"id": "fervor", "name": "戦意高揚", "desc": "攻撃が命中するたび3秒間 攻撃速度 +2%（最大15重）"},
				{"id": "iron_stance", "name": "不動の構え", "desc": "受けるダメージ -15%"}],
			[{"id": "deathline", "name": "死線", "desc": "ライフ50%以下の間、ダメージ +40%・攻撃速度 +20%"},
				{"id": "executioner", "name": "処刑人", "desc": "ライフ35%以下の敵へのダメージ +80%"}],
		]},
	{"k": "storm", "name": "霜雷の巫女", "icon": "☈", "color": Color("#9fd8ff"), "desc": "氷と雷を操り、敵を縛り砕く巫女。冷気・雷とクリティカルに特化。",
		"minors": [
			{"id": "storm_elem", "name": "霜雷", "fmt": "冷気・雷ダメージ +{v}%", "max": 3, "stats": {"cold_dmg": 7, "light_dmg": 7}},
			{"id": "storm_sight", "name": "鋭眼", "fmt": "クリティカル率 +{v}%", "max": 3, "stats": {"crit": 1.5}},
			{"id": "storm_step", "name": "疾駆", "fmt": "移動速度 +{v}%", "max": 3, "stats": {"move_spd": 4}},
			{"id": "storm_well", "name": "魔力の泉", "fmt": "マナ回復 +{v}/秒", "max": 3, "stats": {"mana_regen": 1.0}},
		],
		"cores": [
			[{"id": "shock", "name": "感電", "desc": "雷ヒットが敵を4秒間感電させる。感電した敵が受けるダメージ +20%"},
				{"id": "frostbite", "name": "凍傷", "desc": "凍結・減速の持続 +50%、凍結中の敵へのダメージ +25%"}],
			[{"id": "crit_arc", "name": "雷鳴の連鎖", "desc": "クリティカル時、近くの別の敵に雷が走り、そのヒットの50%の雷ダメージを与える"},
				{"id": "crit_mana", "name": "静電の奔流", "desc": "クリティカル時にマナを4回復する"}],
			[{"id": "storm_eye", "name": "嵐の目", "desc": "サンダーストームの持続 2倍、落雷の間隔 -30%"},
				{"id": "shatter", "name": "絶対零度", "desc": "凍結した敵を倒すと砕け散り、周囲の敵に冷気ダメージを与えて凍結させる"}],
		]},
	{"k": "necro", "name": "冥導師", "icon": "☠", "color": Color("#c8b0f0"), "desc": "死者とトーテムを従えて戦う導師。ミニオンとトーテムに特化。",
		"minors": [
			{"id": "necro_bond", "name": "従属の絆", "fmt": "ミニオン・トーテムのダメージ +{v}%", "max": 3, "stats": {"ally_dmg": 12}},
			{"id": "necro_shell", "name": "堅牢な僕", "fmt": "ミニオン・トーテムのライフ +{v}%", "max": 3, "stats": {"ally_life": 15}},
			{"id": "necro_lore", "name": "死霊術", "fmt": "スペルダメージ +{v}%", "max": 3, "stats": {"spell_dmg": 6}},
			{"id": "necro_bone", "name": "骨の鎧", "fmt": "最大ライフ +{v}", "max": 3, "stats": {"life": 18}},
		],
		"cores": [
			[{"id": "bone_legion", "name": "骨の軍勢", "desc": "骸骨の最大数 +2"},
				{"id": "twin_totems", "name": "双塔の守護", "desc": "トーテムの最大数 +1"}],
			[{"id": "death_pact", "name": "死の契約", "desc": "ミニオンが倒れると爆発し、周囲の敵に物理ダメージを与える"},
				{"id": "soul_feed", "name": "魂の供物", "desc": "敵を倒すたび、すべてのミニオンとトーテムのライフを10%回復する"}],
			[{"id": "lich_lord", "name": "冥王の権能", "desc": "ミニオン・トーテムのダメージ +50%、攻撃・詠唱の頻度 +25%"},
				{"id": "bone_march", "name": "死者の行進", "desc": "骸骨召喚で呼ぶ骸骨 +1体、そのマナコスト -30%"}],
		]},
	{"k": "bulwark", "name": "鉄燼の城塞", "icon": "⛨", "color": Color("#b8c4d0"), "desc": "灰をかぶった鉄壁の守り手。アーマー・ライフ回復と被ダメージ軽減に特化。",
		"minors": [
			{"id": "bulwark_plate", "name": "鉄壁", "fmt": "アーマー +{v}", "max": 3, "stats": {"armor": 12}},
			{"id": "bulwark_heart", "name": "不屈", "fmt": "最大ライフ +{v}", "max": 3, "stats": {"life": 22}},
			{"id": "bulwark_mend", "name": "再起", "fmt": "ライフ回復 +{v}/秒", "max": 3, "stats": {"life_regen": 1.5}},
			{"id": "bulwark_weight", "name": "重圧", "fmt": "攻撃ダメージ +{v}%", "max": 3, "stats": {"atk_dmg": 6}},
		],
		"cores": [
			[{"id": "armor_life", "name": "燼鉄の血肉", "desc": "アーマーの20%を最大ライフに加える"},
				{"id": "fortress", "name": "砦の構え", "desc": "アーマー +40、移動速度 -5%", "stats": {"armor": 40, "move_spd": -5}}],
			[{"id": "nova_on_hit", "name": "霜の反撃", "desc": "被弾時20%の確率でフロストノヴァが発動する"},
				{"id": "hearth_pulse", "name": "炉の鼓動", "desc": "ライフ回復 +6/秒", "stats": {"life_regen": 6}}],
			[{"id": "unbroken", "name": "不壊の誓い", "desc": "受けるダメージ -12%、最大ライフ +40", "stats": {"dr_pct": 12, "life": 40}},
				{"id": "kill_heal", "name": "燼喰らい", "desc": "敵を倒すと最大ライフの3%を回復する"}],
		]},
	{"k": "bloodfire", "name": "血焔の闘士", "icon": "✢", "color": Color("#e0503a"), "desc": "血と炎を刃に宿して戦う闘士。火炎をまとう攻撃と撃破時の回復に特化。",
		"minors": [
			{"id": "bf_flame", "name": "焔刃", "fmt": "火炎ダメージ +{v}%", "max": 3, "stats": {"fire_dmg": 7}},
			{"id": "bf_fury", "name": "猛攻", "fmt": "攻撃ダメージ +{v}%", "max": 3, "stats": {"atk_dmg": 7}},
			{"id": "bf_blood", "name": "血潮", "fmt": "撃破時ライフ +{v}", "max": 3, "stats": {"life_on_kill": 2}},
			{"id": "bf_pace", "name": "闘志", "fmt": "攻撃速度 +{v}%", "max": 3, "stats": {"atk_spd": 4}},
		],
		"cores": [
			[{"id": "ember_edge", "name": "燼の刃", "desc": "攻撃のヒットが敵を燃焼させ、3秒かけてヒットの25%のダメージを与える"},
				{"id": "slash_wave", "name": "焔走り", "desc": "斬撃が貫通する衝撃波を放つ"}],
			[{"id": "rage_kill", "name": "闘争の熱", "desc": "攻撃で敵を倒すたび4秒間 攻撃速度 +4%（最大5重）"},
				{"id": "blood_hunger", "name": "血の渇き", "desc": "撃破時ライフ +8、最大ライフ +20", "stats": {"life_on_kill": 8, "life": 20}}],
			[{"id": "pyre_fist", "name": "灼熱の拳", "desc": "火炎ダメージ +15%（乗算）、攻撃ダメージ +15%", "stats": {"more_fire": 15, "atk_dmg": 15}},
				{"id": "ash_frenzy", "name": "燼の狂奔", "desc": "ダメージ +18%（乗算）、最大ライフ -25", "stats": {"more_dmg": 18, "life": -25}}],
		]},
	{"k": "astral", "name": "星砂の賢者", "icon": "✦", "color": Color("#f0e0a0"), "desc": "星の砂を読み、あらゆる呪文を極める賢者。スペル全般・マナ・リンクの余力に特化。",
		"minors": [
			{"id": "astral_lore", "name": "星詠", "fmt": "スペルダメージ +{v}%", "max": 3, "stats": {"spell_dmg": 7}},
			{"id": "astral_mind", "name": "叡智", "fmt": "最大マナ +{v}", "max": 3, "stats": {"mana": 15}},
			{"id": "astral_flow", "name": "律動", "fmt": "詠唱速度 +{v}%", "max": 3, "stats": {"cast_spd": 4}},
			{"id": "astral_well", "name": "余力", "fmt": "エネルギー上限 +{v}", "max": 3, "stats": {"energy": 1}},
		],
		"cores": [
			[{"id": "elem_unity", "name": "三相の調和", "desc": "火炎・冷気・雷ダメージのボーナスが、そのうち最も高い値に揃う"},
				{"id": "life_to_mana", "name": "魂の転写", "desc": "最大ライフの20%を最大マナに変換する"}],
			[{"id": "chain_plus", "name": "連鎖の星図", "desc": "チェインライトニングの連鎖数 +4"},
				{"id": "meteor_shower", "name": "流星群", "desc": "メテオが追加で2つ降り注ぐ"}],
			[{"id": "fireball_multi", "name": "三連星", "desc": "ファイアボールが3方向に放たれる"},
				{"id": "star_eater", "name": "星喰み", "desc": "スペルダメージ +25%（乗算）、最大ライフ -30", "stats": {"more_spell": 25, "life": -30}}],
		]},
	{"k": "shade", "name": "影走りの狩人", "icon": "☾", "color": Color("#8fa0c8"), "desc": "影から影へ渡り、刃を投げ放つ狩人。攻撃・移動とクリティカルに特化。",
		"minors": [
			{"id": "shade_edge", "name": "影刃", "fmt": "攻撃ダメージ +{v}%", "max": 3, "stats": {"atk_dmg": 6}},
			{"id": "shade_eye", "name": "鷹の目", "fmt": "クリティカル率 +{v}%", "max": 3, "stats": {"crit": 1.5}},
			{"id": "shade_light", "name": "軽身", "fmt": "移動速度 +{v}%", "max": 3, "stats": {"move_spd": 4}},
			{"id": "shade_fang", "name": "致命", "fmt": "クリティカルダメージ +{v}%", "max": 3, "stats": {"crit_multi": 10}},
		],
		"cores": [
			[{"id": "dash_nova", "name": "霜影", "desc": "シャドウダッシュの終点でフロストノヴァが発動する"},
				{"id": "shadow_step", "name": "影の歩み", "desc": "移動速度 +12%", "stats": {"move_spd": 12}}],
			[{"id": "swift_blade", "name": "疾影", "desc": "移動速度のボーナスと同じだけ攻撃速度が増加する"},
				{"id": "vital_point", "name": "急所穿ち", "desc": "クリティカル率 +5%、クリティカルダメージ +25%", "stats": {"crit": 5, "crit_multi": 25}}],
			[{"id": "shade_mark", "name": "影の刻印", "desc": "クリティカルを受けた敵は4秒間 受けるダメージ +15%"},
				{"id": "afterimage", "name": "残影", "desc": "攻撃速度 +15%、移動速度 +8%", "stats": {"atk_spd": 15, "move_spd": 8}}],
		]},
	{"k": "hex", "name": "蝕月の呪詠者", "icon": "☽", "color": Color("#a070c0"), "desc": "蝕む月の言葉で敵を呪い、命を吸い上げる詠み手。呪い・混沌と吸収に特化。",
		"minors": [
			{"id": "hex_void", "name": "蝕呪", "fmt": "混沌ダメージ +{v}%", "max": 3, "stats": {"chaos_dmg": 8}},
			{"id": "hex_word", "name": "呪言", "fmt": "スペルダメージ +{v}%", "max": 3, "stats": {"spell_dmg": 5}},
			{"id": "hex_moon", "name": "月光", "fmt": "マナ回復 +{v}/秒", "max": 3, "stats": {"mana_regen": 0.8}},
			{"id": "hex_veil", "name": "闇衣", "fmt": "最大ライフ +{v}", "max": 3, "stats": {"life": 16}},
		],
		"cores": [
			[{"id": "hex_touch", "name": "蝕みの手", "desc": "スペルのヒットが敵を4秒間蝕み、受けるダメージ +12%"},
				{"id": "soul_drain", "name": "魂喰い", "desc": "混沌ダメージの5%をライフとして吸収する"}],
			[{"id": "hex_deep", "name": "深き呪縛", "desc": "呪われた・蝕まれた敵へのダメージ +30%"},
				{"id": "moon_feast", "name": "月蝕の饗宴", "desc": "撃破時ライフ +6、マナ回復 +3/秒", "stats": {"life_on_kill": 6, "mana_regen": 3}}],
			[{"id": "void_tide", "name": "虚無の潮", "desc": "混沌ダメージ +25%（乗算）、最大マナ +30", "stats": {"more_chaos": 25, "mana": 30}},
				{"id": "eclipse", "name": "皆既", "desc": "スペルダメージ +30%、受けるダメージ -8%", "stats": {"spell_dmg": 30, "dr_pct": 8}}],
		]},
]


static func ascendancy(k: String) -> Dictionary:
	for a in ASCENDANCIES:
		if a.k == k:
			return a
	return {}


## a core talent of an ascendancy by id ({} if it has none)
static func asc_core(a: Dictionary, id: String) -> Dictionary:
	for tier in a.get("cores", []):
		for c in tier:
			if c.id == id:
				return c
	return {}

# base classes: chosen when a character is made; each sets a starting lean of the stats, the starting
# weapon, skill bar and gems, the heroine's colors, and which three ascendancies the character can take
const DEFAULT_CLASS := "ashblade"   # characters from before base classes that have no ascendancy to go by
const CLASSES := [
	{"k": "ashblade", "name": "灰刃の剣士", "icon": "⚔", "color": Color("#d8b070"),
		"desc": "鋼と灰をまとう前衛。厚いライフとアーマーで踏みとどまり、剣と盾で道を切り開く。",
		"traits": "最大ライフ +30・アーマー +10・攻撃ダメージ +10%／最大マナ -10",
		"stats": {"life": 30, "armor": 10, "atk_dmg": 10, "mana": -10},
		"weapon": "片手剣", "slots": ["slash", "heavy_strike", "throw_knives", "fireball", "nova", "dash"], "gems": ["power", "haste"],
		"ascs": ["blade", "bulwark", "bloodfire"],
		"look": {"armor": Color("#2f3f8c"), "dark": Color("#1d2656"), "trim": Color("#d3d8e2"), "cape": false}},
	{"k": "sigil", "name": "燼紋の術士", "icon": "✹", "color": Color("#ff9a50"),
		"desc": "身体に燼の紋を刻み、元素を呼ぶ術士。豊富なマナと詠唱速度で呪文を撃ち続ける。",
		"traits": "最大マナ +30・詠唱速度 +8%・スペルダメージ +10%／最大ライフ -10",
		"stats": {"mana": 30, "cast_spd": 8, "spell_dmg": 10, "life": -10},
		"weapon": "ルーンの杖", "slots": ["firebolt", "fireball", "nova", "chain", "meteor", "dash"], "gems": ["power", "multi"],
		"ascs": ["pyre", "storm", "astral"],
		"look": {"armor": Color("#8a2433"), "dark": Color("#47141c"), "trim": Color("#e8c36a"), "cape": true}},
	{"k": "lantern", "name": "灯影の導き手", "icon": "☼", "color": Color("#9fd0a0"),
		"desc": "灯り狐とともに影を渡る導き手。身軽さとクリティカル、従える霊やミニオンで戦う。",
		"traits": "移動速度 +6%・攻撃速度 +5%・クリティカル率 +2%・ミニオンのダメージ +15%",
		"stats": {"move_spd": 6, "atk_spd": 5, "crit": 2, "ally_dmg": 15},
		"weapon": "短剣", "slots": ["throw_knives", "slash", "skeleton", "chain", "nova", "dash"], "gems": ["power", "haste"],
		"ascs": ["necro", "shade", "hex"],
		"look": {"armor": Color("#2c5a3c"), "dark": Color("#173222"), "trim": Color("#c8a060"), "cape": true}},
]


static func base_class(k: String) -> Dictionary:
	for c in CLASSES:
		if c.k == k:
			return c
	return {}


## the base class an ascendancy belongs to ("" for none)
static func class_of_asc(asc: String) -> String:
	for c in CLASSES:
		if asc in c.ascs:
			return c.k
	return ""


## the ascendancies a base class can take, in its order
static func class_ascs(k: String) -> Array:
	return base_class(k).get("ascs", []).map(func(a): return ascendancy(a))


## points for the ascendancy: one every two character levels
static func asc_points(level: int) -> int:
	return floori(level / 2.0)

const ELITE_AFFIXES := [
	{"k": "swift", "name": "俊足"}, {"k": "armored", "name": "鉄壁"},
	{"k": "volatile", "name": "爆裂"}, {"k": "frenzied", "name": "狂乱"},
]

const THEMES := [
	{"name": "朽ちた地下墓所", "tint": Color.WHITE, "torch": Color("#ffbe78")},
	{"name": "溶岩の洞窟", "tint": Color("#ffb49a"), "torch": Color("#ff9a5a")},
	{"name": "凍てつく聖堂", "tint": Color("#b8d0ff"), "torch": Color("#c8dcff")},
]

const DMG_COLORS := {"phys": Color.WHITE, "fire": Color("#ff9a40"), "cold": Color("#8fdcff"), "light": Color("#d9b8ff"), "chaos": Color("#9fe070")}


func _ready() -> void:
	# Japanese UI text needs a CJK font; use whatever the OS provides
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "Hiragino Sans", "Noto Sans CJK JP", "sans-serif"])


static func xp_need(level: int) -> int:
	return roundi(25.0 * pow(level, 1.7) + 20.0)


# =================== items ===================
const RARITY := [
	{"name": "ノーマル", "color": Color("#cfcfcf"), "aff": [0, 0], "w": 60.0},
	{"name": "マジック", "color": Color("#5b9bff"), "aff": [1, 2], "w": 29.0},
	{"name": "レア", "color": Color("#ffd23f"), "aff": [3, 4], "w": 9.0},
	{"name": "レジェンド", "color": Color("#ff7b1c"), "aff": [3, 4], "w": 1.6},
]

## the hideout merchant (#59): one knob over what its gear and wares cost, and how much it carries
const SHOP_PRICE := 2.5           # × every gear, tablet, jewel and ember shell price (1.0 = the prices before #59)
const SHOP_GEAR_PER_SLOT := 6     # gear pieces of each slot (× 7 slots)
const SHOP_GEAR_RARITY := [12.0, 46.0, 34.0, 8.0]   # weights of normal / magic / rare / unique in the stock
const SHOP_TABLETS := 8
const SHOP_JEWELS := 5            # 燈晶
const SHOP_RINGS := 5             # 環晶
const SHOP_CHARMS := 12           # ember shells (燼殻), counted by piece

const SLOTS := ["weapon", "helm", "armor", "gloves", "boots", "ring", "amulet"]
const SLOT_INFO := {
	"weapon": {"name": "武器", "glyph": "剣"}, "helm": {"name": "兜", "glyph": "兜"}, "armor": {"name": "鎧", "glyph": "鎧"},
	"gloves": {"name": "手袋", "glyph": "甲"}, "boots": {"name": "靴", "glyph": "靴"}, "ring": {"name": "指輪", "glyph": "環"},
	"amulet": {"name": "首飾り", "glyph": "飾"},
}

const BASES := {
	"weapon": [
		{"name": "片手剣", "min": 4, "max": 8, "aps": 1.5},
		{"name": "戦斧", "min": 6, "max": 12, "aps": 1.2},
		{"name": "大槌", "min": 9, "max": 17, "aps": 0.95},
		{"name": "ルーンの杖", "min": 3, "max": 7, "aps": 1.3, "implicit": {"spell_dmg": 25}},
		{"name": "短剣", "min": 3, "max": 6, "aps": 1.8, "implicit": {"crit": 3}},
	],
	"helm": [{"name": "革の頭巾", "armor": 4, "implicit": {"mana": 8}}, {"name": "鉄兜", "armor": 9}],
	"armor": [{"name": "布のローブ", "armor": 6, "implicit": {"mana": 15}}, {"name": "鎖帷子", "armor": 14}, {"name": "板金鎧", "armor": 22}],
	"gloves": [{"name": "革手袋", "armor": 3, "implicit": {"atk_spd": 3}}, {"name": "鉄の篭手", "armor": 7}],
	"boots": [{"name": "革靴", "armor": 3, "implicit": {"move_spd": 4}}, {"name": "鉄靴", "armor": 7}],
	"ring": [{"name": "銅の指輪", "implicit": {"life": 12}}, {"name": "銀の指輪", "implicit": {"mana": 12}}, {"name": "金の指輪", "implicit": {"crit": 2}}],
	"amulet": [{"name": "牙の首飾り", "implicit": {"inc_dmg": 8}}, {"name": "琥珀の護符", "implicit": {"life_regen": 2}}],
}

const ELEM_SLOTS := ["weapon", "helm", "ring", "amulet"]
## `w` is how often the affix is picked among the ones its slot allows (rarer lines sell for more on the exchange)
const AFFIXES := [
	{"k": "inc_dmg", "fmt": "ダメージ +%d%%", "word": "猛き", "min": 6, "max": 14, "sc": 0.07, "w": 100, "slots": ["weapon", "ring", "amulet", "gloves"]},
	{"k": "flat_dmg", "fmt": "武器ダメージ +%d", "word": "鋭い", "min": 1, "max": 4, "sc": 0.2, "w": 90, "slots": ["weapon", "gloves", "ring"]},
	{"k": "life", "fmt": "最大ライフ +%d", "word": "頑強な", "min": 10, "max": 25, "sc": 0.12, "w": 110, "slots": ["helm", "armor", "gloves", "boots", "ring", "amulet"]},
	{"k": "mana", "fmt": "最大マナ +%d", "word": "賢明な", "min": 8, "max": 18, "sc": 0.08, "w": 110, "slots": ["helm", "armor", "ring", "amulet", "weapon"]},
	{"k": "armor", "fmt": "アーマー +%d", "word": "堅牢な", "min": 5, "max": 14, "sc": 0.15, "w": 110, "slots": ["helm", "armor", "gloves", "boots"]},
	{"k": "crit", "fmt": "クリティカル率 +%d%%", "word": "狙い澄ました", "min": 1, "max": 4, "sc": 0.02, "w": 70, "slots": ["weapon", "gloves", "ring", "amulet", "helm"]},
	{"k": "crit_multi", "fmt": "クリティカルダメージ +%d%%", "word": "残忍な", "min": 10, "max": 25, "sc": 0.04, "w": 55, "slots": ["weapon", "amulet", "gloves"]},
	{"k": "atk_spd", "fmt": "攻撃速度 +%d%%", "word": "迅速な", "min": 4, "max": 10, "sc": 0.02, "w": 60, "slots": ["weapon", "gloves", "ring"]},
	{"k": "cast_spd", "fmt": "詠唱速度 +%d%%", "word": "流麗な", "min": 4, "max": 10, "sc": 0.02, "w": 60, "slots": ["weapon", "helm", "ring", "amulet"]},
	{"k": "move_spd", "fmt": "移動速度 +%d%%", "word": "疾風の", "min": 4, "max": 10, "sc": 0.015, "w": 45, "slots": ["boots"]},
	{"k": "fire_dmg", "fmt": "火炎ダメージ +%d%%", "word": "燃え盛る", "min": 8, "max": 20, "sc": 0.07, "w": 90, "slots": ELEM_SLOTS},
	{"k": "cold_dmg", "fmt": "冷気ダメージ +%d%%", "word": "凍てつく", "min": 8, "max": 20, "sc": 0.07, "w": 90, "slots": ELEM_SLOTS},
	{"k": "light_dmg", "fmt": "雷ダメージ +%d%%", "word": "轟く", "min": 8, "max": 20, "sc": 0.07, "w": 90, "slots": ELEM_SLOTS},
	{"k": "spell_dmg", "fmt": "スキルダメージ +%d%%", "word": "神秘の", "min": 8, "max": 18, "sc": 0.07, "w": 80, "slots": ["weapon", "helm", "amulet", "armor"]},
	{"k": "life_regen", "fmt": "ライフ回復 +%d/秒", "word": "再生の", "min": 1, "max": 3, "sc": 0.1, "w": 100, "slots": ["armor", "helm", "amulet", "boots"]},
	{"k": "mana_regen", "fmt": "マナ回復 +%d/秒", "word": "瞑想の", "min": 1, "max": 3, "sc": 0.05, "w": 100, "slots": ["helm", "ring", "amulet", "armor"]},
	{"k": "life_on_kill", "fmt": "撃破時ライフ +%d", "word": "貪欲な", "min": 2, "max": 5, "sc": 0.12, "w": 90, "slots": ["weapon", "gloves", "ring"]},
	{"k": "cdr", "fmt": "移動スキルのクールダウン短縮 +%d%%", "word": "時を刻む", "min": 3, "max": 7, "sc": 0.0, "w": 35, "slots": ["helm", "amulet"]},
	{"k": "energy", "fmt": "エネルギー上限 +%d", "word": "共鳴する", "min": 1, "max": 2, "sc": 0.05, "w": 25, "slots": ["helm", "amulet", "ring"]},
	# never rolled as affixes (no slots); only uniques carry these
	{"k": "atk_dmg", "fmt": "攻撃ダメージ +%d%%", "word": "武闘の", "min": 8, "max": 16, "sc": 0.07, "w": 0, "slots": []},
	{"k": "ally_dmg", "fmt": "ミニオン・トーテムのダメージ +%d%%", "word": "従える", "min": 10, "max": 20, "sc": 0.07, "w": 0, "slots": []},
	{"k": "ally_life", "fmt": "ミニオン・トーテムのライフ +%d%%", "word": "護る", "min": 10, "max": 20, "sc": 0.05, "w": 0, "slots": []},
]

# the 1000 uniques live in uniques.gd; legendary rarity drops one of them
const LEGENDARY := Uniques.LIST
static var _legend_by_name := {}


static func legend(name: String) -> Dictionary:
	if _legend_by_name.is_empty():
		for l in LEGENDARY:
			_legend_by_name[l.name] = l
	return _legend_by_name.get(name, {})

## how rare each unique is, fixed by its name: `share` of the 1000 fall in the tier, `w` is each one's drop weight,
## `pow` scales its positive stat lines (and a unique weapon's damage), `base` is what buyers pay for it (c)
const UNIQUE_TIERS := [
	{"name": "並", "share": 0.60, "w": 100.0, "pow": 0.85, "base": [0.3, 1.0], "color": Color("#b8a890")},
	{"name": "稀少", "share": 0.28, "w": 30.0, "pow": 1.0, "base": [1.5, 4.0], "color": Color("#7ec8ff")},
	{"name": "秘宝", "share": 0.10, "w": 8.0, "pow": 1.2, "base": [6.0, 15.0], "color": Color("#d48cff")},
	{"name": "至宝", "share": 0.02, "w": 3.0, "pow": 1.4, "base": [25.0, 60.0], "color": Color("#ffe06a")},
]
static var _tier_by_name := {}


## the unique's tier index into UNIQUE_TIERS (0 for anything that isn't a unique)
static func unique_tier(name: String) -> int:
	if not _tier_by_name.has(name):
		var r := RandomNumberGenerator.new()
		r.seed = ("unique/" + name).hash()
		var roll := r.randf()
		var t := 0
		for i in range(UNIQUE_TIERS.size() - 1, 0, -1):
			roll -= UNIQUE_TIERS[i].share
			if roll < 0.0:
				t = i
				break
		_tier_by_name[name] = t if not legend(name).is_empty() else 0
	return _tier_by_name[name]


static func unique_pow(name: String) -> float:
	return UNIQUE_TIERS[unique_tier(name)].pow


static func unique_weight(name: String) -> float:
	return UNIQUE_TIERS[unique_tier(name)].w

const RARE_A := ["災厄", "黄昏", "血染め", "嵐", "亡霊", "灰", "深淵", "黒鉄", "緋色", "月影", "残光", "骸"]
const RARE_B := ["の牙", "の囁き", "の誓約", "の棘", "の鎖", "の祈り", "の咆哮", "の残響", "の印", "の爪"]

# =================== currencies ===================
# ember shards are spent with the merchant; the rest craft items
const CURRENCIES := [
	{"k": "ember", "name": "灰燼の欠片", "icon": "◆", "color": Color("#ffb35a"), "w": 0.0, "desc": "商人との取引に使う基本通貨。"},
	{"k": "transmute", "name": "変容の結晶", "icon": "✦", "color": Color("#6aa8ff"), "w": 40.0, "value": 5, "desc": "ノーマルアイテムをマジックに変える。"},
	{"k": "ascend", "name": "昇華の焔", "icon": "▲", "color": Color("#ffd23f"), "w": 12.0, "value": 20, "desc": "マジックアイテムをレアに変える。"},
	{"k": "chaos", "name": "混沌の残光", "icon": "✺", "color": Color("#c070ff"), "w": 14.0, "value": 25, "desc": "マジック・レアのオプションをすべて作り直す。"},
	{"k": "whet", "name": "鍛錬の砥石", "icon": "◈", "color": Color("#9ad0a0"), "w": 16.0, "value": 15, "desc": "マジック・レアにオプションを1つ追加する。"},
	{"k": "purify", "name": "浄化の雫", "icon": "◯", "color": Color("#d8e8f0"), "w": 12.0, "value": 8, "desc": "オプションをすべて消してノーマルに戻す。"},
	{"k": "divine", "name": "神秘の核", "icon": "✷", "color": Color("#ff8a2c"), "w": 3.0, "value": 80, "desc": "オプションの数値だけを振り直す。レジェンドにも使える。"},
	{"k": "compass", "name": "羅針の欠片", "icon": "✧", "color": Color("#7fd4ff"), "w": 10.0, "value": 12, "desc": "遠征図でマップ効果を振り直す。"},
	# never dropped at random: only the sealed monoliths (Seal) give these
	{"k": "brand", "name": "刻紋の熾石", "icon": "✠", "color": Color("#5ff0c0"), "w": 0.0, "value": 60, "desc": "レアアイテムに特殊修飾子を1つ刻む（すでにあれば刻み直す）。刻紋の封碑から得られる。"},
]

# special modifiers (特殊修飾子): a rare item carries at most one, carved with 刻紋の熾石. They sit apart from the
# affixes (they don't count toward the affix limit and 混沌の残光 leaves them), `sc` is how fast the line grows with item level
# and `stats` says what a point of the line gives
const SPECIAL_MODS := [
	{"k": "s_life", "name": "灯心の紋", "fmt": "最大ライフ +%d%%", "min": 6, "max": 12, "sc": 0.012, "stats": {"life_pct": 1}},
	{"k": "s_mana", "name": "深泉の紋", "fmt": "最大マナ +%d%%", "min": 8, "max": 16, "sc": 0.012, "stats": {"mana_pct": 1}},
	{"k": "s_elem", "name": "三界の紋", "fmt": "火炎・冷気・雷ダメージ +%d%%", "min": 10, "max": 20, "sc": 0.015, "stats": {"fire_dmg": 1, "cold_dmg": 1, "light_dmg": 1}},
	{"k": "s_haste", "name": "疾駆の紋", "fmt": "攻撃速度・詠唱速度 +%d%%", "min": 5, "max": 10, "sc": 0.01, "stats": {"atk_spd": 1, "cast_spd": 1}},
	{"k": "s_guard", "name": "堅守の紋", "fmt": "受けるダメージ -%d%%", "min": 3, "max": 7, "sc": 0.0, "stats": {"dr_pct": 1}},
	{"k": "s_attack", "name": "武闘の紋", "fmt": "攻撃ダメージ +%d%%", "min": 14, "max": 26, "sc": 0.015, "stats": {"atk_dmg": 1}},
	{"k": "s_ally", "name": "従者の紋", "fmt": "ミニオン・トーテムのダメージとライフ +%d%%", "min": 15, "max": 30, "sc": 0.015, "stats": {"ally_dmg": 1, "ally_life": 1}},
	{"k": "s_void", "name": "蝕紋", "fmt": "混沌ダメージ +%d%%", "min": 15, "max": 30, "sc": 0.015, "stats": {"chaos_dmg": 1}},
	{"k": "s_energy", "name": "共鳴の紋", "fmt": "エネルギー上限 +%d", "min": 2, "max": 3, "sc": 0.0, "stats": {"energy": 1}},
	{"k": "s_fury", "name": "猛威の紋", "fmt": "ダメージ +%d%%（乗算）", "min": 4, "max": 8, "sc": 0.006, "stats": {"more_dmg": 1}},
]


## add `v` of stat `k` into a summed stat dictionary, `times` over. The "increased" stats add up; the "more" stats
## (more_*) multiply with each other, and a dictionary keeps their product as one combined % (20 and 25 make 50)
static func add_stat(st: Dictionary, k: String, v: float, times := 1) -> void:
	if k.begins_with("more_"):
		st[k] = ((1.0 + st.get(k, 0.0) / 100.0) * pow(1.0 + v / 100.0, times) - 1.0) * 100.0
	else:
		st[k] = st.get(k, 0) + v * times


## the factor a "more" stat multiplies by (more_dmg 30 -> 1.3)
static func more(st: Dictionary, k: String) -> float:
	return maxf(0.0, 1.0 + st.get(k, 0.0) / 100.0)


static func special_mod(k: String) -> Dictionary:
	for m in SPECIAL_MODS:
		if m.k == k:
			return m
	return {}


static func affix(k: String) -> Dictionary:
	for a in AFFIXES:
		if a.k == k:
			return a
	return {}


static func currency(k: String) -> Dictionary:
	for c in CURRENCIES:
		if c.k == k:
			return c
	return {}


# =================== expedition atlas ===================
const ATLAS_NODES := [
	{"id": "ash", "name": "灰の入口", "theme": 0, "level": 1, "x": 0.07, "y": 0.55, "links": ["bone", "wail"], "desc": "深淵へ続く最初の階段。灯火を掲げて進め。"},
	{"id": "bone", "name": "骨の回廊", "theme": 0, "level": 2, "x": 0.2, "y": 0.3, "links": ["ember"], "desc": "無数の骨が積み上げられた細い通路。"},
	{"id": "wail", "name": "嘆きの納骨堂", "theme": 0, "level": 3, "x": 0.24, "y": 0.75, "links": ["ember", "obsidian"], "desc": "夜な夜な泣き声が響くという古い納骨堂。"},
	{"id": "ember", "name": "燻る坑道", "theme": 1, "level": 4, "x": 0.38, "y": 0.42, "links": ["forge"], "desc": "地熱で焼けた岩が赤く光る廃坑。"},
	{"id": "obsidian", "name": "黒曜の裂け目", "theme": 1, "level": 5, "x": 0.43, "y": 0.8, "links": ["forge", "frost"], "desc": "溶岩が冷えて固まった鋭い岩の谷。"},
	{"id": "forge", "name": "溶鉄の炉心", "theme": 1, "level": 6, "x": 0.55, "y": 0.52, "links": ["cathedral"], "desc": "巨像が生まれたと伝わる灼熱の炉。"},
	{"id": "frost", "name": "凍てつく参道", "theme": 2, "level": 7, "x": 0.62, "y": 0.82, "links": ["cathedral", "grave"], "desc": "氷に閉ざされた巡礼者の道。"},
	{"id": "cathedral", "name": "霜の大聖堂", "theme": 2, "level": 8, "x": 0.72, "y": 0.35, "links": ["abyss"], "desc": "魔女が祈りを捧げる凍った聖堂。"},
	{"id": "grave", "name": "氷霧の墓標", "theme": 2, "level": 9, "x": 0.8, "y": 0.72, "links": ["abyss"], "desc": "霧の中に墓標が並ぶ静寂の丘。"},
	{"id": "abyss", "name": "残り火の深淵", "theme": -1, "level": 10, "x": 0.92, "y": 0.5, "links": [], "endless": true, "desc": "終わりなき深淵。踏破するたびに、さらに深く強大になる。"},
]
const THEME_COLORS := [Color("#c9b89a"), Color("#ff7a3a"), Color("#7fd4ff"), Color("#b48cff")]

const MAP_MODS := [
	{"k": "life", "name": "敵のライフ +40%", "life": 1.4},
	{"k": "dmg", "name": "敵のダメージ +30%", "dmg": 1.3},
	{"k": "swarm", "name": "敵の数 +40%", "swarm": 1.4},
	{"k": "fast", "name": "敵の移動速度 +25%", "speed": 1.25},
	{"k": "elite", "name": "エリートの出現率 2倍", "elite": 2.0},
]

# atlas passives: one point per first clear and per Ember Abyss clear; each node needs the one above it
const ATLAS_PASSIVES := [
	{"branch": "財宝", "color": Color("#ffcf3a"), "nodes": [
		{"id": "gold", "name": "黄金の嗅覚", "max": 3, "per": 10, "fmt": "カレンシー獲得量 +{v}%"},
		{"id": "find", "name": "目利き", "max": 3, "per": 8, "fmt": "アイテムレア度 +{v}%"},
		{"id": "plenty", "name": "豊穣", "max": 3, "per": 6, "fmt": "アイテム数量 +{v}%"},
		{"id": "relic", "name": "秘宝の導き", "max": 2, "per": 10, "fmt": "ボスのレジェンド確定ドロップ率 +{v}%"},
	]},
	{"branch": "征服", "color": Color("#ff7a5a"), "nodes": [
		{"id": "horde", "name": "群れの呼び声", "max": 3, "per": 8, "fmt": "マップの敵の数 +{v}%"},
		{"id": "hunt", "name": "精鋭狩り", "max": 3, "per": 15, "fmt": "エリートの出現率 +{v}%"},
		{"id": "train", "name": "修練", "max": 3, "per": 8, "fmt": "獲得経験値 +{v}%"},
		{"id": "prowess", "name": "強者の証", "max": 2, "per": 10, "fmt": "マップ効果1つにつきアイテムレア度 +{v}%"},
	]},
	{"branch": "探索", "color": Color("#7fd4ff"), "nodes": [
		{"id": "flask", "name": "携行袋", "max": 2, "per": 1, "fmt": "回復薬の最大所持数 +{v}"},
		{"id": "ward", "name": "灯火の加護", "max": 3, "per": 2, "fmt": "ライフ回復 +{v}/秒"},
		{"id": "haggle", "name": "商人の縁", "max": 3, "per": 8, "fmt": "ショップの購入価格 -{v}%"},
		{"id": "fox", "name": "狐の嗅覚", "max": 2, "per": 25, "fmt": "ペットの回収範囲 +{v}%"},
	]},
]


## an atlas passive node plus its branch and its place in that branch
static func passive(id: String) -> Dictionary:
	for b in ATLAS_PASSIVES:
		for i in b.nodes.size():
			if b.nodes[i].id == id:
				var n: Dictionary = b.nodes[i].duplicate()
				n.branch = b
				n.tier = i
				return n
	return {}


const HIDEOUT := {"id": "hideout", "name": "隠れ家", "hideout": true}
const HIDEOUT_THEME := {"name": "隠れ家", "tint": Color("#ffe6c8"), "torch": Color("#ffc88c")}


static func atlas_node(id: String) -> Dictionary:
	for n in ATLAS_NODES:
		if n.id == id:
			return n
	return {}


static func map_mod(k: String) -> Dictionary:
	for m in MAP_MODS:
		if m.k == k:
			return m
	return {}


# =================== seasons ===================
## each season runs from `start` up to (not including) `end`, as UTC dates; characters made in it
## play in their own league with its own stash, and move to standard when it ends
const SEASONS := [
	{"id": "s1", "name": "灰の目覚め", "start": "2026-11-01", "end": "2027-02-01", "color": Color("#ff9a5a")},
]

static var date_override := ""   # dev runs: `--date=YYYY-MM-DD` pretends it is that day


static func today() -> String:
	if date_override != "":
		return date_override
	return Time.get_datetime_string_from_system(true).substr(0, 10)


static func season(id: String) -> Dictionary:
	for s in SEASONS:
		if s.id == id:
			return s
	return {}


static func season_running(id: String, day := today()) -> bool:
	var s := season(id)
	return not s.is_empty() and day >= s.start and day < s.end


## the season open for new characters today, or {}
static func current_season(day := today()) -> Dictionary:
	for s in SEASONS:
		if day >= s.start and day < s.end:
			return s
	return {}


## whole days left in a running season
static func season_days_left(s: Dictionary, day := today()) -> int:
	var now := Time.get_unix_time_from_datetime_string(day)
	return ceili((Time.get_unix_time_from_datetime_string(s.end) - now) / 86400.0)
