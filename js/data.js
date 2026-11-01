'use strict';
// ---- items ----
const RARITY = [
  { name: 'ノーマル', color: '#cfcfcf', aff: [0, 0], w: 60 },
  { name: 'マジック', color: '#5b9bff', aff: [1, 2], w: 29 },
  { name: 'レア', color: '#ffd23f', aff: [3, 4], w: 9 },
  { name: 'レジェンド', color: '#ff7b1c', aff: [3, 4], w: 1.6 },
];

// ---- currencies: ember shards are spent with the merchant; the rest craft items ----
const CURRENCIES = [
  { k: 'ember', name: '灰燼の欠片', icon: '◆', color: '#ffb35a', desc: '商人との取引やパッシブの振り直しに使う基本通貨。' },
  { k: 'transmute', name: '変容の結晶', icon: '✦', color: '#6aa8ff', w: 40, value: 5, desc: 'ノーマルアイテムをマジックに変える。' },
  { k: 'ascend', name: '昇華の焔', icon: '▲', color: '#ffd23f', w: 12, value: 20, desc: 'マジックアイテムをレアに変える。' },
  { k: 'chaos', name: '混沌の残光', icon: '✺', color: '#c070ff', w: 14, value: 25, desc: 'マジック・レアのオプションをすべて作り直す。' },
  { k: 'whet', name: '鍛錬の砥石', icon: '◈', color: '#9ad0a0', w: 16, value: 15, desc: 'マジック・レアにオプションを1つ追加する。' },
  { k: 'purify', name: '浄化の雫', icon: '◯', color: '#d8e8f0', w: 12, value: 8, desc: 'オプションをすべて消してノーマルに戻す。' },
  { k: 'divine', name: '神秘の核', icon: '✷', color: '#ff8a2c', w: 3, value: 80, desc: 'オプションの数値だけを振り直す。レジェンドにも使える。' },
  { k: 'compass', name: '羅針の欠片', icon: '✧', color: '#7fd4ff', w: 10, value: 12, desc: '遠征図でマップ効果を振り直す。' },
];
const CUR_BY_KEY = Object.fromEntries(CURRENCIES.map(c => [c.k, c]));
CUR_BY_KEY.gem = { k: 'gem', name: 'サポートジェム', icon: '◇', color: '#7fe0a0' }; // drop-only, not held as currency
const DROP_CURRENCIES = CURRENCIES.filter(c => c.w);

const SLOTS = ['weapon', 'helm', 'armor', 'gloves', 'boots', 'ring', 'amulet'];
const SLOT_INFO = {
  weapon: { name: '武器', glyph: '剣' }, helm: { name: '兜', glyph: '兜' }, armor: { name: '鎧', glyph: '鎧' },
  gloves: { name: '手袋', glyph: '甲' }, boots: { name: '靴', glyph: '靴' }, ring: { name: '指輪', glyph: '環' },
  amulet: { name: '首飾り', glyph: '飾' },
};

const BASES = {
  weapon: [
    { name: '片手剣', min: 4, max: 8, aps: 1.5 },
    { name: '戦斧', min: 6, max: 12, aps: 1.2 },
    { name: '大槌', min: 9, max: 17, aps: 0.95 },
    { name: 'ルーンの杖', min: 3, max: 7, aps: 1.3, implicit: { spellDmg: 25 } },
    { name: '短剣', min: 3, max: 6, aps: 1.8, implicit: { crit: 3 } },
  ],
  helm: [{ name: '革の頭巾', armor: 4, implicit: { mana: 8 } }, { name: '鉄兜', armor: 9 }],
  armor: [{ name: '布のローブ', armor: 6, implicit: { mana: 15 } }, { name: '鎖帷子', armor: 14 }, { name: '板金鎧', armor: 22 }],
  gloves: [{ name: '革手袋', armor: 3, implicit: { atkSpd: 3 } }, { name: '鉄の篭手', armor: 7 }],
  boots: [{ name: '革靴', armor: 3, implicit: { moveSpd: 4 } }, { name: '鉄靴', armor: 7 }],
  ring: [{ name: '銅の指輪', implicit: { life: 12 } }, { name: '銀の指輪', implicit: { mana: 12 } }, { name: '金の指輪', implicit: { crit: 2 } }],
  amulet: [{ name: '牙の首飾り', implicit: { incDmg: 8 } }, { name: '琥珀の護符', implicit: { lifeRegen: 2 } }],
};

const ELEM_SLOTS = ['weapon', 'helm', 'ring', 'amulet'];
const AFFIXES = [
  { k: 'incDmg', fmt: 'ダメージ +{v}%', word: '猛き', min: 6, max: 14, sc: 0.07, slots: ['weapon', 'ring', 'amulet', 'gloves'] },
  { k: 'flatDmg', fmt: '武器ダメージ +{v}', word: '鋭い', min: 1, max: 4, sc: 0.2, slots: ['weapon', 'gloves', 'ring'] },
  { k: 'life', fmt: '最大ライフ +{v}', word: '頑強な', min: 10, max: 25, sc: 0.12, slots: ['helm', 'armor', 'gloves', 'boots', 'ring', 'amulet'] },
  { k: 'mana', fmt: '最大マナ +{v}', word: '賢明な', min: 8, max: 18, sc: 0.08, slots: ['helm', 'armor', 'ring', 'amulet', 'weapon'] },
  { k: 'armor', fmt: 'アーマー +{v}', word: '堅牢な', min: 5, max: 14, sc: 0.15, slots: ['helm', 'armor', 'gloves', 'boots'] },
  { k: 'crit', fmt: 'クリティカル率 +{v}%', word: '狙い澄ました', min: 1, max: 4, sc: 0.02, slots: ['weapon', 'gloves', 'ring', 'amulet', 'helm'] },
  { k: 'critMulti', fmt: 'クリティカルダメージ +{v}%', word: '残忍な', min: 10, max: 25, sc: 0.04, slots: ['weapon', 'amulet', 'gloves'] },
  { k: 'atkSpd', fmt: '攻撃速度 +{v}%', word: '迅速な', min: 4, max: 10, sc: 0.02, slots: ['weapon', 'gloves', 'ring'] },
  { k: 'castSpd', fmt: '詠唱速度 +{v}%', word: '流麗な', min: 4, max: 10, sc: 0.02, slots: ['weapon', 'helm', 'ring', 'amulet'] },
  { k: 'moveSpd', fmt: '移動速度 +{v}%', word: '疾風の', min: 4, max: 10, sc: 0.015, slots: ['boots'] },
  { k: 'fireDmg', fmt: '火炎ダメージ +{v}%', word: '燃え盛る', min: 8, max: 20, sc: 0.07, slots: ELEM_SLOTS },
  { k: 'coldDmg', fmt: '冷気ダメージ +{v}%', word: '凍てつく', min: 8, max: 20, sc: 0.07, slots: ELEM_SLOTS },
  { k: 'lightDmg', fmt: '雷ダメージ +{v}%', word: '轟く', min: 8, max: 20, sc: 0.07, slots: ELEM_SLOTS },
  { k: 'spellDmg', fmt: 'スキルダメージ +{v}%', word: '神秘の', min: 8, max: 18, sc: 0.07, slots: ['weapon', 'helm', 'amulet', 'armor'] },
  { k: 'lifeRegen', fmt: 'ライフ回復 +{v}/秒', word: '再生の', min: 1, max: 3, sc: 0.1, slots: ['armor', 'helm', 'amulet', 'boots'] },
  { k: 'manaRegen', fmt: 'マナ回復 +{v}/秒', word: '瞑想の', min: 1, max: 3, sc: 0.05, slots: ['helm', 'ring', 'amulet', 'armor'] },
  { k: 'lifeOnKill', fmt: '撃破時ライフ +{v}', word: '貪欲な', min: 2, max: 5, sc: 0.12, slots: ['weapon', 'gloves', 'ring'] },
  { k: 'cdr', fmt: 'クールダウン短縮 +{v}%', word: '時を刻む', min: 3, max: 7, sc: 0, slots: ['helm', 'amulet'] },
];
const AFFIX_BY_KEY = Object.fromEntries(AFFIXES.map(a => [a.k, a]));

const LEGENDARY = [
  { name: '灰燼の王冠', slot: 'helm', base: 1, effect: 'fireballMulti', desc: 'ファイアボールが3方向に放たれる' },
  { name: '霜纏いの足跡', slot: 'boots', base: 0, effect: 'dashNova', desc: 'シャドウダッシュの終点でフロストノヴァが発動する' },
  { name: '嵐呼びの指輪', slot: 'ring', base: 2, effect: 'chainPlus', desc: 'チェインライトニングの連鎖数 +4' },
  { name: '処刑人の大剣', slot: 'weapon', base: 1, effect: 'slashWave', desc: '斬撃が貫通する衝撃波を放つ' },
  { name: '血盟の首飾り', slot: 'amulet', base: 0, effect: 'killHeal', desc: '敵を倒すと最大ライフの3%を回復する' },
  { name: '流星の籠手', slot: 'gloves', base: 1, effect: 'meteorShower', desc: 'メテオが追加で2つ降り注ぐ' },
  { name: '不屈の胸当て', slot: 'armor', base: 2, effect: 'novaOnHit', desc: '被弾時20%の確率でフロストノヴァが発動する' },
];

const RARE_A = ['災厄', '黄昏', '血染め', '嵐', '亡霊', '灰', '深淵', '黒鉄', '緋色', '月影', '残光', '骸'];
const RARE_B = ['の牙', 'の囁き', 'の誓約', 'の棘', 'の鎖', 'の祈り', 'の咆哮', 'の残響', 'の印', 'の爪'];

// ---- skills ----
const SKILLS = {
  slash: { name: '斬撃', icon: '⚔', mana: 0, cd: 0, attack: true, color: '#c9b48a', lvl: 1,
    desc: '前方の敵を薙ぎ払う。攻撃速度の影響を受ける。' },
  whirl: { name: '旋風斬', icon: '✲', mana: 4, cd: 0, attack: true, color: '#e0c070', lvl: 4,
    desc: 'その場で回転し、周囲の敵すべてを斬りつける。攻撃速度の影響を受ける。' },
  fireball: { name: 'ファイアボール', icon: '✹', mana: 6, cd: 0, cast: 0.42, color: '#ff7a2a', lvl: 1,
    desc: '着弾時に爆発する火球を放つ。' },
  iceSpear: { name: 'アイススピア', icon: '➶', mana: 8, cd: 0, cast: 0.35, color: '#9fe8ff', lvl: 3,
    desc: '敵を貫通する氷の槍を放ち、短時間凍結させる。' },
  nova: { name: 'フロストノヴァ', icon: '❄', mana: 16, cd: 5, cast: 0.3, color: '#7fd4ff', lvl: 1,
    desc: '周囲に冷気を放ち、敵を凍結させる。' },
  chain: { name: 'チェインライトニング', icon: 'ϟ', mana: 12, cd: 1.0, cast: 0.35, color: '#c9a8ff', lvl: 1,
    desc: 'カーソル付近の敵に雷を放ち、次々と連鎖する。' },
  storm: { name: 'サンダーストーム', icon: '☈', mana: 24, cd: 7, cast: 0.4, color: '#b0a0ff', lvl: 6,
    desc: 'カーソル位置に雷雲を呼び、範囲内の敵に落雷を降らせ続ける。' },
  meteor: { name: 'メテオ', icon: '☄', mana: 30, cd: 9, cast: 0.5, color: '#ff4d2a', lvl: 1,
    desc: 'カーソル位置に隕石を落とし、地面を燃やす。' },
  dash: { name: 'シャドウダッシュ', icon: '➤', mana: 8, cd: 2.5, color: '#9a8cff', lvl: 1,
    desc: 'カーソル方向へ駆け抜け、通過した敵を切り裂く。移動中は無敵。' },
  skeleton: { name: '骸骨召喚', icon: '☠', mana: 20, cd: 0.8, cast: 0.5, color: '#e8e0c8', lvl: 2,
    desc: '戦う骸骨の戦士を2体呼び出す（最大3体）。骸骨は近くの敵に斬りかかる。' },
};
const SKILL_LIST = Object.keys(SKILLS);
const SKILL_TAGS = {
  slash: ['attack', 'melee'], whirl: ['attack', 'melee', 'aoe'], fireball: ['spell', 'projectile', 'aoe', 'fire'],
  iceSpear: ['spell', 'projectile', 'cold'], nova: ['spell', 'aoe', 'cold'], chain: ['spell', 'chain', 'lightning'],
  storm: ['spell', 'aoe', 'lightning'], meteor: ['spell', 'aoe', 'fire'], dash: ['attack', 'movement'], skeleton: ['spell', 'minion'],
};
const TAG_NAMES = { attack: '攻撃', melee: '近接', spell: 'スペル', projectile: '投射', aoe: '範囲', fire: '火炎', cold: '冷気',
  lightning: '雷', chain: '連鎖', movement: '移動', minion: 'ミニオン' };

// ---- support gems: linked to a skill slot to change how that skill behaves ----
// `tags`: the skill needs at least one of them; `not`: the skill must have none of them
const SUPPORTS = [
  { id: 'power', name: '威力増幅', color: '#ff9a6a', tags: ['attack', 'spell'], desc: 'ダメージ +30%（ミニオンにも有効）／マナコスト +30%',
    apply: s => { s.dmg *= 1.3; s.mana *= 1.3; } },
  { id: 'haste', name: '加速', color: '#8fd18f', tags: ['attack', 'spell'], desc: '攻撃・詠唱速度 +25%（トーテム・ミニオンにも有効）',
    apply: s => { s.speed *= 1.25; s.mana *= 1.1; } },
  { id: 'multi', name: '多重投射', color: '#9fd8ff', tags: ['projectile'], desc: '投射物 +2／ダメージ -20%',
    apply: s => { s.proj += 2; s.dmg *= 0.8; s.mana *= 1.2; } },
  { id: 'aoe', name: '範囲拡大', color: '#ffd36a', tags: ['aoe'], desc: '効果範囲 +35%',
    apply: s => { s.aoe *= 1.35; s.mana *= 1.15; } },
  { id: 'chainS', name: '連鎖増幅', color: '#c9a8ff', tags: ['chain'], desc: '連鎖回数 +3',
    apply: s => { s.chain += 3; s.mana *= 1.2; } },
  { id: 'leech', name: '生命吸収', color: '#ff6a6a', tags: ['attack', 'spell'], desc: '与えたダメージの3%をライフとして回復',
    apply: s => { s.leech += 0.03; } },
  { id: 'frostbite', name: '凍結付与', color: '#bff4ff', tags: ['attack', 'spell'], desc: '命中した敵を0.4秒凍結させる',
    apply: s => { s.freeze = Math.max(s.freeze, 0.4); s.mana *= 1.1; } },
  { id: 'totem', name: 'トーテム化', color: '#d8a060', tags: ['spell'], not: ['minion', 'movement'],
    desc: 'スキルの代わりにカーソル位置へトーテムを設置。トーテムが10秒間スキルを自動で放つ（最大2本）／ダメージ -15%',
    apply: s => { s.totem = true; s.dmg *= 0.85; } },
  { id: 'minionPower', name: 'ミニオン強化', color: '#e8e0c8', tags: ['minion'], desc: 'ミニオンのライフ +50%、ダメージ +30%',
    apply: s => { s.mlife *= 1.5; s.dmg *= 1.3; } },
  { id: 'swarm', name: '軍勢', color: '#b8b0a0', tags: ['minion'], desc: 'ミニオンの最大数 +2',
    apply: s => { s.mcount += 2; s.mana *= 1.2; } },
];
const SUPPORT_BY_ID = Object.fromEntries(SUPPORTS.map(g => [g.id, g]));
const DEFAULT_GEMS = ['power', 'haste'];
const LINK_MAX = 3;
const linkSockets = level => (level >= 10 ? 3 : level >= 5 ? 2 : 1);
const supportFits = (g, skillId) => g.tags.some(t => SKILL_TAGS[skillId].includes(t)) && !(g.not || []).some(t => SKILL_TAGS[skillId].includes(t));
const DEFAULT_SLOTS = ['slash', 'fireball', 'nova', 'chain', 'meteor', 'dash'];
const SKILL_SLOTS = [
  { short: 'LMB', label: '左クリック', on: () => Input.mdown[0] },
  { short: 'RMB', label: '右クリック', on: () => Input.mdown[2] },
  { short: 'Q', label: 'Q', on: () => Input.keys.KeyQ },
  { short: 'E', label: 'E', on: () => Input.keys.KeyE },
  { short: 'R', label: 'R', on: () => Input.keys.KeyR },
  { short: 'SPC', label: 'Space', on: () => Input.keys.Space },
];

// ---- talents ----
const TALENTS = [
  { k: 'might', name: '剛力', desc: 'ダメージ +8%', max: 20 },
  { k: 'vitality', name: '生命力', desc: '最大ライフ +20', max: 20 },
  { k: 'spirit', name: '精神', desc: '最大マナ +12、マナ回復 +0.5/秒', max: 20 },
  { k: 'swift', name: '俊敏', desc: '移動速度・攻撃速度 +3%', max: 10 },
  { k: 'precision', name: '精密', desc: 'クリティカル率 +1.5%、クリティカルダメージ +8%', max: 15 },
  ...SKILL_LIST.map(k => ({ k, name: SKILLS[k].name, desc: 'このスキルのダメージ +15%', max: 10, skill: true })),
];

// ---- enemies ----
const ENEMY_TYPES = {
  imp: { name: 'インプ', r: 11, life: 10, dmg: 4, speed: 175, color: '#c4523a', atkRange: 20, atkCd: 0.9, windup: 0.2, xp: 4 },
  ghoul: { name: 'グール', r: 14, life: 18, dmg: 7, speed: 120, color: '#7a9a5a', atkRange: 24, atkCd: 1.2, windup: 0.3, xp: 6 },
  archer: { name: '骸骨弓兵', r: 13, life: 14, dmg: 6, speed: 110, color: '#d8d0b8', ranged: true, range: 380, atkCd: 1.9, windup: 0.45, xp: 7 },
  brute: { name: 'ブルート', r: 22, life: 60, dmg: 16, speed: 85, color: '#8a5a9a', atkRange: 40, atkCd: 2.4, windup: 0.75, aoe: 75, xp: 16 },
  shaman: { name: '呪術師', r: 13, life: 16, dmg: 11, speed: 100, color: '#4fb0c0', caster: true, range: 400, atkCd: 3.2, windup: 0.9, xp: 10 },
  boss: { name: '深淵の番人', r: 40, life: 650, dmg: 20, speed: 95, color: '#b03030', boss: true, atkRange: 50, atkCd: 1.6, windup: 0.4, xp: 220 },
  colossus: { name: '灼熱の巨像', r: 46, life: 820, dmg: 24, speed: 80, color: '#7a3a22', boss: true, atkRange: 55, atkCd: 1.8, windup: 0.5, xp: 260 },
  witch: { name: '凍嵐の魔女', r: 26, life: 600, dmg: 18, speed: 130, color: '#3a6a9a', boss: true, atkRange: 40, atkCd: 1.5, windup: 0.4, xp: 260 },
};

// boss changes with the floor theme (every 3 floors)
const BOSS_ROTATION = [
  { type: 'boss', guards: ['ghoul', 'ghoul', 'ghoul', 'ghoul'] },
  { type: 'colossus', guards: ['imp', 'imp', 'imp', 'brute'] },
  { type: 'witch', guards: ['archer', 'archer', 'shaman', 'shaman'] },
];

const ELITE_AFFIXES = [
  { k: 'swift', name: '俊足' },
  { k: 'armored', name: '鉄壁' },
  { k: 'volatile', name: '爆裂' },
  { k: 'frenzied', name: '狂乱' },
];

// floor themes rotate every 3 floors
const THEMES = [
  { name: '朽ちた地下墓所', floor: [38, 33, 30], wallTop: '#5c5248', wallFront: '#342c27', dark: '8,6,12', torch: '255,190,120' },
  { name: '溶岩の洞窟', floor: [42, 26, 22], wallTop: '#5a3a30', wallFront: '#2e1a16', dark: '14,4,4', torch: '255,150,90' },
  { name: '凍てつく聖堂', floor: [28, 36, 46], wallTop: '#55606e', wallFront: '#2a323d', dark: '4,8,16', torch: '200,220,255' },
];
const HIDEOUT_THEME = { name: '隠れ家', floor: [58, 46, 34], wallTop: '#6e5c48', wallFront: '#3e3024', dark: '12,7,4', darkA: 0.6, torch: '255,200,140' };
