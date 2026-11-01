'use strict';
// ---- items ----
const RARITY = [
  { name: 'ノーマル', color: '#cfcfcf', aff: [0, 0], w: 60 },
  { name: 'マジック', color: '#5b9bff', aff: [1, 2], w: 29 },
  { name: 'レア', color: '#ffd23f', aff: [3, 4], w: 9 },
  { name: 'レジェンド', color: '#ff7b1c', aff: [3, 4], w: 1.6 },
];

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
const SKILL_ORDER = ['slash', 'fireball', 'nova', 'chain', 'meteor', 'dash'];
const SKILLS = {
  slash: { key: '左クリック', short: 'LMB', name: '斬撃', icon: '⚔', mana: 0, cd: 0, attack: true, color: '#c9b48a',
    desc: '前方の敵を薙ぎ払う。攻撃速度の影響を受ける。' },
  fireball: { key: '右クリック', short: 'RMB', name: 'ファイアボール', icon: '✹', mana: 6, cd: 0, cast: 0.42, color: '#ff7a2a',
    desc: '着弾時に爆発する火球を放つ。' },
  nova: { key: 'Q', short: 'Q', name: 'フロストノヴァ', icon: '❄', mana: 16, cd: 5, cast: 0.3, color: '#7fd4ff',
    desc: '周囲に冷気を放ち、敵を凍結させる。' },
  chain: { key: 'E', short: 'E', name: 'チェインライトニング', icon: 'ϟ', mana: 12, cd: 1.0, cast: 0.35, color: '#c9a8ff',
    desc: 'カーソル付近の敵に雷を放ち、次々と連鎖する。' },
  meteor: { key: 'R', short: 'R', name: 'メテオ', icon: '☄', mana: 30, cd: 9, cast: 0.5, color: '#ff4d2a',
    desc: 'カーソル位置に隕石を落とし、地面を燃やす。' },
  dash: { key: 'Space', short: 'SPC', name: 'シャドウダッシュ', icon: '➤', mana: 8, cd: 2.5, color: '#9a8cff',
    desc: 'カーソル方向へ駆け抜け、通過した敵を切り裂く。移動中は無敵。' },
};

// ---- talents ----
const TALENTS = [
  { k: 'might', name: '剛力', desc: 'ダメージ +8%', max: 20 },
  { k: 'vitality', name: '生命力', desc: '最大ライフ +20', max: 20 },
  { k: 'spirit', name: '精神', desc: '最大マナ +12、マナ回復 +0.5/秒', max: 20 },
  { k: 'swift', name: '俊敏', desc: '移動速度・攻撃速度 +3%', max: 10 },
  { k: 'precision', name: '精密', desc: 'クリティカル率 +1.5%、クリティカルダメージ +8%', max: 15 },
  ...SKILL_ORDER.map(k => ({ k, name: SKILLS[k].name, desc: 'このスキルのダメージ +15%', max: 10, skill: true })),
];

// ---- enemies ----
const ENEMY_TYPES = {
  imp: { name: 'インプ', r: 11, life: 10, dmg: 4, speed: 175, color: '#c4523a', atkRange: 20, atkCd: 0.9, windup: 0.2, xp: 4 },
  ghoul: { name: 'グール', r: 14, life: 18, dmg: 7, speed: 120, color: '#7a9a5a', atkRange: 24, atkCd: 1.2, windup: 0.3, xp: 6 },
  archer: { name: '骸骨弓兵', r: 13, life: 14, dmg: 6, speed: 110, color: '#d8d0b8', ranged: true, range: 380, atkCd: 1.9, windup: 0.45, xp: 7 },
  brute: { name: 'ブルート', r: 22, life: 60, dmg: 16, speed: 85, color: '#8a5a9a', atkRange: 40, atkCd: 2.4, windup: 0.75, aoe: 75, xp: 16 },
  shaman: { name: '呪術師', r: 13, life: 16, dmg: 11, speed: 100, color: '#4fb0c0', caster: true, range: 400, atkCd: 3.2, windup: 0.9, xp: 10 },
  boss: { name: '深淵の番人', r: 40, life: 650, dmg: 20, speed: 95, color: '#b03030', boss: true, atkRange: 50, atkCd: 1.6, windup: 0.4, xp: 220 },
};

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
