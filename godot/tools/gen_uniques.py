# Helper that wrote scripts/uniques.gd (the game reads that file, not this one).
# Each unique is built from a theme: the theme picks its name words, the effect it may grant,
# the stats it raises and the stats it gives up. Run: python tools/gen_uniques.py
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOTAL = 1000
SEED = 7

# the seven hand-made legendaries stay first and keep rolling random affixes
ORIGINALS = [
    {"name": "灰燼の王冠", "slot": "helm", "base": 1, "effect": "fireball_multi", "desc": "ファイアボールが3方向に放たれる"},
    {"name": "霜纏いの足跡", "slot": "boots", "base": 0, "effect": "dash_nova", "desc": "シャドウダッシュの終点でフロストノヴァが発動する"},
    {"name": "嵐呼びの指輪", "slot": "ring", "base": 2, "effect": "chain_plus", "desc": "チェインライトニングの連鎖数 +4"},
    {"name": "処刑人の大剣", "slot": "weapon", "base": 1, "effect": "slash_wave", "desc": "斬撃が貫通する衝撃波を放つ"},
    {"name": "血盟の首飾り", "slot": "amulet", "base": 0, "effect": "kill_heal", "desc": "敵を倒すと最大ライフの3%を回復する"},
    {"name": "流星の籠手", "slot": "gloves", "base": 1, "effect": "meteor_shower", "desc": "メテオが追加で2つ降り注ぐ"},
    {"name": "不屈の胸当て", "slot": "armor", "base": 2, "effect": "nova_on_hit", "desc": "被弾時20%の確率でフロストノヴァが発動する"},
]

EFFECT_DESC = {o["effect"]: o["desc"] for o in ORIGINALS}
EFFECT_DESC.update({
    "swift_blade": "移動速度のボーナスと同じだけ攻撃速度が増加する",
    "spell_blade": "スペルダメージのボーナスが攻撃ダメージにも適用される",
    "elem_unity": "火炎・冷気・雷ダメージのボーナスが、そのうち最も高い値に揃う",
    "armor_life": "アーマーの20%を最大ライフに加える",
    "life_to_mana": "最大ライフの20%を最大マナに変換する",
    "no_crit": "通常のクリティカルが発生しない。ダメージ +45%",
})
# ascendancy core talents can also come from gear; take their wording from data.gd
_data = (ROOT / "scripts" / "data.gd").read_text(encoding="utf-8")
for m in re.finditer(r'\{"id": "(\w+)", "name": "[^"]*", "desc": "([^"]*)"\}', _data):
    EFFECT_DESC.setdefault(m.group(1), m.group(2))

# base [min, max] of every stat, as the affix table rolls it at item level 0
STAT = {
    "inc_dmg": (6, 14), "flat_dmg": (1, 4), "life": (10, 25), "mana": (8, 18), "armor": (5, 14), "crit": (1, 4),
    "crit_multi": (10, 25), "atk_spd": (4, 10), "cast_spd": (4, 10), "move_spd": (4, 10), "fire_dmg": (8, 20),
    "cold_dmg": (8, 20), "light_dmg": (8, 20), "spell_dmg": (8, 18), "life_regen": (1, 3), "mana_regen": (1, 3),
    "life_on_kill": (2, 5), "cdr": (3, 7), "energy": (1, 2), "atk_dmg": (8, 16), "ally_dmg": (10, 20), "ally_life": (10, 20),
}
# drawbacks never touch these: armor and energy can't go below zero safely, regen would turn into decay
NO_DRAWBACK = {"armor", "energy", "life_regen", "cdr", "life_on_kill", "flat_dmg"}

THEMES = {
    "fire": {
        "words": "焦土 業火 熾火 紅蓮 炎帝 火葬 烈焔 篝火 火輪 灼熱 炎舌 焼印 燎原 煉獄 火竜 狐火 陽炎 火種 鬼火 炎環 焚書 噴炎 炉心 赤熱 炎冠 火祭り",
        "effects": ["fireball_multi", "meteor_shower", "ignite", "fire_cost", "kill_burst", "inferno"],
        "up": ["fire_dmg", "spell_dmg", "cast_spd", "mana", "inc_dmg"], "down": ["cold_dmg", "life", "atk_spd"],
        "flavor": ["燃え尽きるまで、止まる理由はない。", "炎は選ばない。ただ等しく焼く。", "灯した者もまた、いつか薪になる。",
                   "熱を恐れる者に、この柄は握れない。", "火の粉の一つ一つが、かつての祈りだった。", "煙の向こうで、誰かが笑っている。",
                   "冷えた灰に触れるな。まだ息がある。", "炉の神は、捧げ物の重さを量らない。", "夜を焼けば、朝は早く来る。",
                   "焦げた地図だけが、帰り道を知っていた。"]},
    "frost": {
        "words": "霜夜 氷河 凍土 白魔 氷柱 吹雪 冬至 凍原 霧氷 氷晶 雪華 凍月 寒椿 氷牢 冬枯れ 霜柱 氷鏡 樹氷 銀嶺 凍星 雪狼 氷棺 凍風 白夜 冬妃 薄氷",
        "effects": ["dash_nova", "nova_on_hit", "frostbite", "shatter"],
        "up": ["cold_dmg", "armor", "life", "crit", "mana_regen"], "down": ["fire_dmg", "move_spd", "atk_spd", "cast_spd"],
        "flavor": ["息を止めろ。冬が通り過ぎるまで。", "凍った湖の底で、王国はまだ眠っている。", "冷たさは、最も静かな刃だ。",
                   "春を知らぬ者だけが、これを美しいと言う。", "雪はすべてを覆い、すべてを赦す。", "砕けた氷にも、映る顔がある。",
                   "温もりは借り物。いずれ返さねばならぬ。", "白い沈黙が、叫びより遠くまで届く。", "凍てつく夜ほど、星はよく見える。",
                   "溶けるまでが、約束の期限だ。"]},
    "storm": {
        "words": "雷鳴 迅雷 稲妻 雷霆 紫電 雷獣 嵐雲 天鼓 鳴神 雷火 疾雷 落雷 電光 雷鎖 霹靂 雷雲 遠雷 雷光 雷帝 放電 雷轟 青雷 嵐眼 雷針 驟雨 天雷",
        "effects": ["chain_plus", "shock", "crit_arc", "storm_eye", "crit_mana"],
        "up": ["light_dmg", "crit", "cast_spd", "mana_regen", "crit_multi"], "down": ["life", "cold_dmg", "fire_dmg"],
        "flavor": ["雷は二度、同じ場所に落ちる。三度目もある。", "空が怒るとき、地上の者は耳を塞ぐ。", "閃光の後には、必ず静寂が来る。",
                   "鎖のように、怒りは次の者へ渡る。", "嵐を呼ぶ者は、嵐に名を呼ばれる。", "天の太鼓が鳴る。踊れ、踊れ。",
                   "雨雲の腹の中で、獣が目を覚ます。", "指先が痺れるなら、まだ生きている証だ。", "光より速く走れぬなら、光になれ。",
                   "雷鳴は遅れて届く。いつも手遅れに。"]},
    "blade": {
        "words": "剣聖 一閃 居合 斬鉄 剣舞 修羅 剣鬼 断罪 鍔鳴り 抜刀 剣客 武辺 千刃 刃風 逆刃 十字 斬撃 鋼牙 刀匠 剣塚 研ぎ師 果たし状 武者 双刃 刃鳴 介錯",
        "effects": ["slash_wave", "third_strike", "fervor", "executioner"],
        "up": ["atk_dmg", "flat_dmg", "atk_spd", "crit_multi", "life_on_kill"], "down": ["mana", "cast_spd", "spell_dmg", "mana_regen"],
        "flavor": ["鞘に収まる剣は、まだ何も斬っていない。", "一太刀で足りぬなら、百を振るえ。", "刃こぼれは、誇りの数だ。",
                   "抜くは一瞬、悔いるは一生。", "鋼は嘘をつかない。腕の未熟を映すだけだ。", "斬った数を数えるのは、もうやめた。",
                   "剣の道に、帰り道はない。", "研ぎ澄ませ。心も、刃も。", "名もなき刀匠の銘が、柄の奥に刻まれている。",
                   "最後に立っていた者が、正しかったことになる。"]},
    "blood": {
        "words": "血潮 鮮血 血涙 吸血 紅月 血族 血染花 生贄 心臓 脈動 血雨 狂血 赤錆 血契 臓腑 血晶 血河 鉄錆 血宴 血統 流血 血鬼 傷痕 渇き 緋滴 赤心",
        "effects": ["kill_heal", "blood_oath", "deathline", "soul_feed"],
        "up": ["life", "life_on_kill", "life_regen", "inc_dmg", "atk_dmg"], "down": ["mana", "mana_regen", "crit"],
        "flavor": ["流れた血は、いずれ誰かの力になる。", "痛みは代価。勝利は釣り銭。", "心臓が鳴る限り、戦いは終わらない。",
                   "赤は乾けば黒になる。忘れるな。", "渇きを満たすものは、いつも他人の中にある。", "傷が多いほど、この鎧はよく馴染む。",
                   "血の契りは、死をもってしか解けぬ。", "生きるために奪う。それの何が悪い。", "鼓動が速まるほど、刃は軽くなる。",
                   "一滴が百を呼び、百が河となる。"]},
    "bulwark": {
        "words": "鉄壁 城塞 不落 守護 盾陣 堅城 磐石 石垣 防人 鉄門 衛兵 番人 堡塁 大盾 金剛 不動 岩肌 鎧袖 城門 砦 甲羅 巌 外壁 錨 楯突き 防塁",
        "effects": ["iron_stance", "armor_life", "nova_on_hit"],
        "up": ["armor", "life", "life_regen", "atk_dmg"], "down": ["move_spd", "atk_spd", "cast_spd", "crit"],
        "flavor": ["倒れぬことが、最大の反撃である。", "門は開かれなかった。千年のあいだ。", "壁の後ろには、守るべき寝顔がある。",
                   "傷は鎧が引き受ける。心は自分で守れ。", "山は動かない。動く必要がないからだ。", "最後の砦が落ちる日を、誰も見ていない。",
                   "重さは、守るものの数に比例する。", "退かぬ足が、そのまま国境になった。", "叩けば叩くほど、鉄は硬くなる。",
                   "盾の傷は、仲間が生きた回数だ。"]},
    "gale": {
        "words": "疾風 旋風 韋駄天 飛燕 迅速 風切り 追風 隼 飛脚 早駆け 風神 天馬 流れ星 燕返し 突風 駿馬 風見 渡り鳥 木枯らし 野分 春一番 颯 風雅 翔破 一陣 迅影",
        "effects": ["swift_blade", "dash_nova", "fervor"],
        "up": ["move_spd", "atk_spd", "cdr", "crit", "cast_spd"], "down": ["life", "mana"],
        "flavor": ["追いつかれる前に、もう次の場所にいる。", "風は形を持たない。だから捕まらない。", "足跡を探しても無駄だ。風は残さない。",
                   "速さは、ためらいを置き去りにする。", "渡り鳥は、帰る場所を一度も疑わない。", "止まった瞬間が、死ぬ瞬間だ。",
                   "背中を押したのは、風か、恐れか。", "誰よりも先に着いて、誰よりも先に去る。", "峠を越える風は、いつも冷たく、いつも自由だ。",
                   "一歩目で決まる。二歩目はもう遅い。"]},
    "arcane": {
        "words": "秘儀 魔導 星詠み 呪文 賢者 神秘 魔書 碩学 秘文 魔方陣 叡智 符術 月読み 禁書 錬金 幻術 魔眼 星図 詠唱 秘蹟 術式 魔紋 奥義 筆写 識者 天文",
        "effects": ["chant_power", "spell_frenzy", "life_to_mana", "spell_blade"],
        "up": ["spell_dmg", "cast_spd", "mana", "mana_regen", "energy"], "down": ["life", "atk_spd", "atk_dmg"],
        "flavor": ["知ることは、代償を払うことだ。", "頁をめくるたび、指先が少し冷たくなる。", "星の並びが変わる前に、詠唱を終えよ。",
                   "読んではならぬ行が、一行だけある。", "賢者は答えを持たない。問いを持つ。", "インクは乾いても、言葉は乾かない。",
                   "世界の仕組みは、案外簡単な式で書ける。", "魔力は器を選ぶ。器もまた魔力を選ぶ。", "禁じられた知識ほど、よく燃える。",
                   "唱え終えたとき、術者はもう別人だ。"]},
    "grave": {
        "words": "冥府 屍 骨塚 墓守 死霊 黄泉 葬列 亡者 髑髏 冥王 鎮魂 墓標 送り火 骨笛 屍蝋 屍山 霊廟 喪服 遺骨 招魂 幽鬼 死神 骸骨 慰霊 無縁 骨壺",
        "effects": ["bone_legion", "twin_totems", "death_pact", "soul_feed", "lich_lord", "bone_march"],
        "up": ["ally_dmg", "ally_life", "spell_dmg", "energy", "mana"], "down": ["inc_dmg", "life", "move_spd", "atk_dmg"],
        "flavor": ["死者は文句を言わない。だから良い兵になる。", "土の下にも、秩序はある。", "骨は覚えている。かつて歩いた道を。",
                   "弔いの鐘は、目覚めの鐘でもある。", "名を呼べば、彼らは応える。何度でも。", "冥府の門番は、賄賂を受け取らない。たぶん。",
                   "眠りを妨げた責任は、取ってもらう。", "生者の軍は疲れる。死者の軍は疲れない。", "墓標の数だけ、味方がいる。",
                   "還る場所のない魂が、袖を引く。"]},
    "precision": {
        "words": "必中 狙撃 鷹目 照準 急所 射手 刺客 暗殺 一点 星読み 針穴 狩人 弱点 見切り 精密 測量 刹那 千里眼 一撃 的中 秘針 毒針 鋭眼 凝視 寸分 静寂",
        "effects": ["third_strike", "crit_arc", "crit_mana", "executioner"],
        "up": ["crit", "crit_multi", "atk_spd", "flat_dmg", "inc_dmg"], "down": ["life", "mana_regen"],
        "flavor": ["狙いは一点。迷いはゼロ。", "瞬きの間に、勝負はついている。", "急所は誰にでもある。神にさえ。",
                   "見えたなら、もう当たっている。", "息を吐き切ったところで、引け。", "百の矢より、一本の正しい矢。",
                   "静かな者ほど、よく見ている。", "影の中で、針が光った。", "獲物は、撃たれたことに気づかない。",
                   "外したことは一度もない。数えていないだけだ。"]},
    "brute": {
        "words": "剛腕 破壊 粉砕 蛮勇 鬼神 怪力 暴君 巨人 猛牛 破城 豪傑 獣王 激震 地割れ 崩落 大喝 野獣 闘牛 剛力 荒くれ 拳骨 山崩し 力士 轟音 暴走 屈強",
        "effects": ["no_crit", "iron_stance", "executioner", "slash_wave"],
        "up": ["inc_dmg", "flat_dmg", "atk_dmg", "armor", "life"], "down": ["crit", "cast_spd", "move_spd", "mana"],
        "flavor": ["考えるな。叩け。", "技などいらぬ。重さがすべてだ。", "壊したものの数だけ、道が開ける。",
                   "大地が割れたのは、偶然ではない。", "細かいことは、生き残った者が考えればいい。", "振り下ろせば、だいたい片付く。",
                   "鉄も骨も、同じ音で砕ける。", "吠え声ひとつで、群れは道を空けた。", "繊細さは、持たざる者の言い訳だ。",
                   "山を崩した腕は、今も少し震えている。"]},
    "prism": {
        "words": "虹彩 七色 極光 万華鏡 三相 輝石 晶光 調和 均衡 天秤 三位 混成 合一 虹橋 光彩 多面 玻璃 宝珠 彩雲 共鳴 和音 分光 星辰 天球 瑠璃 翡翠",
        "effects": ["elem_unity", "chain_plus", "fireball_multi", "shatter"],
        "up": ["fire_dmg", "cold_dmg", "light_dmg", "spell_dmg", "energy"], "down": ["life", "atk_dmg", "crit_multi"],
        "flavor": ["三つの色は、混ざれば白になる。", "光を割れば、隠れていた色が見える。", "均衡は、最も壊れやすい力だ。",
                   "どの属性も、同じ空から生まれた。", "宝玉の中で、小さな虹が回り続けている。", "天秤が傾いた日、世界は少し歪んだ。",
                   "多くを知る者は、一つに偏らない。", "極光の下では、敵も味方も同じ色に染まる。", "和音は、ひとつの音では奏でられない。",
                   "透き通っているから、すべてを映す。"]},
    "ember": {
        "words": "灰燼 残り火 燃えさし 灰被り 火の粉 埋み火 灰塵 熾き 煤 灰色 灰王 消し炭 焼け跡 灰雪 灰狼 灰風 余燼 灰巫 灰街 焚き付け 燠火 灰石 灰羽 火消し 灰月 灰海",
        "effects": ["kill_heal", "kill_burst", "meteor_shower", "inferno"],
        "up": ["inc_dmg", "fire_dmg", "life_on_kill", "life", "move_spd"], "down": ["mana", "mana_regen", "cold_dmg"],
        "flavor": ["灰の中から拾い上げた。まだ温かかった。", "燃え落ちた街の名を、誰も覚えていない。", "残り火は、次の炎を待っている。",
                   "灰になっても、熱は消えない。", "降る灰は、空からの手紙だ。", "焼け跡に立つ者だけが、次を始められる。",
                   "煤けた紋章に、かすかに家名が読める。", "消えかけた火ほど、強く息を吹き込め。", "エンバーフォールの夜は、いつも赤い。",
                   "灰を被った者は、もう何も恐れない。"]},
}

# per slot: name nouns for each base (index matches Data.BASES), and how many uniques the slot gets
SLOTS = {
    "weapon": {"count": 300, "nouns": [["剣", "長剣", "刃", "細剣"], ["斧", "戦斧", "大斧", "鉞"], ["槌", "大槌", "鉄槌", "戦槌"],
                                       ["杖", "錫杖", "魔杖", "笏"], ["短剣", "匕首", "小刀", "牙刃"]]},
    "helm": {"count": 110, "nouns": [["頭巾", "覆面", "額帯", "フード"], ["兜", "冑", "王冠", "面頬"]]},
    "armor": {"count": 120, "nouns": [["ローブ", "法衣", "外套", "聖衣"], ["鎖帷子", "鎖衣", "胴衣", "帷子"], ["鎧", "胸当て", "甲冑", "大鎧"]]},
    "gloves": {"count": 110, "nouns": [["手袋", "手甲", "指抜き", "腕巻き"], ["篭手", "鉄拳", "腕甲", "掌甲"]]},
    "boots": {"count": 110, "nouns": [["靴", "足袋", "長靴", "脚絆"], ["鉄靴", "具足", "脛当て", "軍靴"]]},
    "ring": {"count": 130, "nouns": [["指輪", "環", "輪", "印環"], ["銀環", "指環", "契り", "輪舞"], ["金環", "印章", "円環", "紋章"]]},
    "amulet": {"count": 120, "nouns": [["首飾り", "牙飾り", "数珠", "胸飾り"], ["護符", "呪符", "垂飾", "お守り"]]},
}
# weapon bases lean toward themes that suit them; other slots draw every theme evenly
WEAPON_THEMES = [
    ["blade", "blood", "gale", "precision", "ember", "frost", "storm"],
    ["blade", "brute", "blood", "ember", "bulwark", "fire"],
    ["brute", "bulwark", "ember", "frost", "blood"],
    ["fire", "frost", "storm", "arcane", "grave", "prism", "ember"],
    ["precision", "gale", "storm", "blood", "grave", "blade"],
]
# armour pieces with no armour-related line get a little armour on top
ARMOR_SLOTS = {"helm", "armor", "gloves", "boots"}


def stat_range(k, m, neg=False):
    lo, hi = STAT[k]
    a, b = max(1, round(lo * m)), max(1, round(hi * m))
    if b <= a:
        b = a + 1
    return [-b, -a] if neg else [a, b]


def build():
    rng = random.Random(SEED)
    names = {o["name"] for o in ORIGINALS}
    word_use = {}
    flavor_use = {}
    out = list(ORIGINALS)
    per_slot = {s: sum(1 for o in ORIGINALS if o["slot"] == s) for s in SLOTS}
    for slot, sd in SLOTS.items():
        n_bases = len(sd["nouns"])
        for i in range(sd["count"] - per_slot[slot]):
            base = i % n_bases
            pool = WEAPON_THEMES[base] if slot == "weapon" else list(THEMES)
            theme_k = pool[(i // n_bases + rng.randrange(len(pool))) % len(pool)]
            th = THEMES[theme_k]
            # name: a theme word nobody has used much yet + one of the base's nouns
            words = th["words"].split()
            rng.shuffle(words)
            words.sort(key=lambda w: word_use.get(w, 0))
            name = None
            for w in words:
                nouns = sd["nouns"][base][:]
                rng.shuffle(nouns)
                for nn in nouns:
                    cand = f"{w}の{nn}"
                    if cand not in names and w not in nn and nn not in w:
                        name = cand
                        break
                if name:
                    word_use[w] = word_use.get(w, 0) + 1
                    break
            assert name, (slot, theme_k)
            names.add(name)
            u = {"name": name, "slot": slot, "base": base}
            effect = rng.random() < 0.65
            if effect:
                fx = rng.choice(th["effects"])
                u["effect"] = fx
                u["desc"] = EFFECT_DESC[fx]
            # stats: effect uniques get two or three solid lines, plain ones three or four big ones
            drawback = rng.random() < (0.4 if effect else 0.75)
            n_up = rng.choice([2, 2, 3]) if effect else rng.choice([3, 3, 4])
            ups = rng.sample(th["up"], min(n_up, len(th["up"])))
            if slot in ARMOR_SLOTS and "armor" not in ups and rng.random() < 0.5:
                ups.append("armor")
            m_base = (1.0, 1.6) if effect else (1.5, 2.2)
            mods = {}
            for k in ups:
                m = rng.uniform(*m_base) + (0.3 if drawback else 0.0)
                if k == "move_spd" and slot != "boots":
                    m *= 0.6
                mods[k] = stat_range(k, m)
            if drawback:
                downs = [k for k in th["down"] if k not in mods and k not in NO_DRAWBACK]
                if downs:
                    k = rng.choice(downs)
                    mods[k] = stat_range(k, rng.uniform(0.6, 1.2), neg=True)
            u["mods"] = mods
            fl = [f for f in th["flavor"] if flavor_use.get(f, 0) < 3]
            if fl and rng.random() < 0.45:
                f = rng.choice(fl)
                flavor_use[f] = flavor_use.get(f, 0) + 1
                u["flavor"] = f
            out.append(u)
    assert len(out) == TOTAL and len(names) == TOTAL
    return out

# #77: hand-made uniques, added after the random ones so the rng stream above never shifts. `tier` fixes the
# drop tier (Data.UNIQUE_TIERS) instead of the hash of the name.
# one per ascendancy lineage: each pays off with that lineage's unique ascendancy through Data.COMBOS
COMBO_UNIQUES = [
    {"name": "王焔の錫杖", "slot": "weapon", "base": 3, "tier": 2, "effect": "kill_burst", "desc": "火炎ダメージで倒した敵が爆発し、周囲に火炎ダメージを与える",
     "mods": {"fire_dmg": [14, 26], "cast_spd": [6, 10], "mana": [10, 20]}, "flavor": "王の名を継ぐ者の手でのみ、焔は頭を垂れる。"},
    {"name": "無銘の極光", "slot": "weapon", "base": 0, "tier": 2, "effect": "third_strike", "desc": "攻撃スキル3回目ごとに、その攻撃が必ずクリティカルになる",
     "mods": {"inc_dmg": [14, 24], "atk_spd": [6, 10], "life": [15, 30]}, "flavor": "銘を刻む暇もなく、斬るべきものが多すぎた。"},
    {"name": "凍雷の額冠", "slot": "helm", "base": 0, "tier": 2, "effect": "crit_arc", "desc": "クリティカル時、近くの別の敵に雷が走り、そのヒットの50%の雷ダメージを与える",
     "mods": {"cold_dmg": [12, 22], "light_dmg": [12, 22], "crit": [2, 4]}, "flavor": "氷が鳴り、雷が凍る。巫女はその狭間で詠う。"},
    {"name": "骸王の首飾り", "slot": "amulet", "base": 0, "tier": 2, "effect": "soul_feed", "desc": "敵を倒すたび、すべてのミニオンとトーテムのライフを10%回復する",
     "mods": {"ally_dmg": [16, 28], "ally_life": [14, 24], "life": [15, 30]}, "flavor": "王の骨は、まだ軍勢を数えている。"},
    {"name": "城塞の鉄心", "slot": "armor", "base": 2, "tier": 2, "effect": "armor_life", "desc": "アーマーの20%を最大ライフに加える",
     "mods": {"armor": [20, 34], "life": [24, 40], "life_regen": [2, 4]}, "flavor": "落ちなかった砦の、最後の一枚。"},
    {"name": "血焔の篭手", "slot": "gloves", "base": 1, "tier": 2, "effect": "ember_edge", "desc": "攻撃のヒットが敵を燃焼させ、3秒かけてヒットの25%のダメージを与える",
     "mods": {"fire_dmg": [12, 22], "atk_spd": [6, 10], "life_on_kill": [3, 6]}, "flavor": "握るたび、血が火に変わる。"},
    {"name": "星詠みの法衣", "slot": "armor", "base": 0, "tier": 2, "effect": "chant_power", "desc": "詠唱速度のボーナスと同じだけスペルダメージが増加する",
     "mods": {"spell_dmg": [14, 24], "cast_spd": [6, 10], "mana": [20, 36]}, "flavor": "裾の星図は、今夜の空と同じに動く。"},
    {"name": "影渡りの靴", "slot": "boots", "base": 0, "tier": 2, "effect": "swift_blade", "desc": "移動速度のボーナスと同じだけ攻撃速度が増加する",
     "mods": {"move_spd": [8, 12], "crit": [2, 4], "life": [15, 28]}, "flavor": "足音は、いつも一歩あとから追いつく。"},
    {"name": "蝕月の環", "slot": "ring", "base": 1, "tier": 2, "effect": "soul_drain", "desc": "混沌ダメージの5%をライフとして吸収する",
     "mods": {"chaos_dmg": [14, 24], "mana": [12, 22], "life_on_kill": [3, 6]}, "flavor": "欠けた月の裏側を、指に嵌めている。"},
]
# 神話: drop only from monsters (Items.generate `myth`), far stronger than any other unique
MYTHIC_UNIQUES = [
    {"name": "終焉の灰剣", "slot": "weapon", "base": 0, "tier": 4, "effect": "executioner", "desc": "ライフ35%以下の敵へのダメージ +80%",
     "mods": {"more_dmg": [35, 55], "crit_multi": [30, 50], "atk_spd": [8, 14]}, "flavor": "世界が燃え尽きたあとに残るのは、灰とこの一振りだけだという。"},
    {"name": "星墜としの宝珠", "slot": "amulet", "base": 0, "tier": 4, "effect": "chant_power", "desc": "詠唱速度のボーナスと同じだけスペルダメージが増加する",
     "mods": {"more_spell": [40, 60], "cast_spd": [10, 16], "mana": [30, 50]}, "flavor": "空の星がひとつ足りないのは、これのせいだ。"},
    {"name": "黒焔の爪", "slot": "gloves", "base": 1, "tier": 4, "effect": "fervor", "desc": "攻撃が命中するたび3秒間 攻撃速度 +2%（最大15重）",
     "mods": {"more_dmg": [30, 45], "atk_spd": [12, 20], "crit": [4, 7]}, "flavor": "燃えているのは敵ではない。敵のいた場所だ。"},
    {"name": "不滅王の胸甲", "slot": "armor", "base": 2, "tier": 4, "effect": "armor_life", "desc": "アーマーの20%を最大ライフに加える",
     "mods": {"more_life": [35, 55], "dr_pct": [10, 15], "armor": [30, 60]}, "flavor": "王は死ななかった。ただ、鎧の中身が要らなくなった。"},
    {"name": "時を拒む兜", "slot": "helm", "base": 1, "tier": 4, "effect": "iron_stance", "desc": "受けるダメージ -15%",
     "mods": {"more_life": [25, 35], "dr_pct": [12, 16], "life_regen": [4, 8]}, "flavor": "この兜の内側では、傷がまだ負われていない。"},
    {"name": "永劫の指輪", "slot": "ring", "base": 0, "tier": 4, "effect": "kill_heal", "desc": "敵を倒すと最大ライフの3%を回復する",
     "mods": {"more_life": [30, 45], "life": [30, 50], "dr_pct": [8, 12]}, "flavor": "外した者はいない。外せた者が、いない。"},
]


def gd(v):
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, list):
        return "[%s]" % ", ".join(gd(x) for x in v)
    if isinstance(v, dict):
        return "{%s}" % ", ".join("%s: %s" % (gd(k), gd(x)) for k, x in v.items())
    return str(v)


def main():
    uniques = build() + COMBO_UNIQUES + MYTHIC_UNIQUES
    assert len({u["name"] for u in uniques}) == len(uniques)
    lines = [
        "class_name Uniques",
        "extends RefCounted",
        "## The %d unique (legendary rarity) items. `base` indexes Data.BASES[slot]; `effect` is a key the" % len(uniques),
        "## game checks in player.effects (legendary effects, ascendancy cores, or the unique-only keystones",
        "## in Player.recalc); `mods` are fixed [min, max] stat lines grown with item level, negative for a",
        "## drawback. Entries without `mods` roll random affixes instead; `tier` fixes the drop tier (else the name's",
        "## hash picks it, Data.unique_tier). Written by tools/gen_uniques.py.",
        "",
        "const LIST := [",
    ]
    for u in uniques:
        lines.append("\t%s," % gd(u))
    lines.append("]")
    (ROOT / "scripts" / "uniques.gd").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
