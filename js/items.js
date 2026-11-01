'use strict';
function rollRarity(boost) {
  const w = [RARITY[0].w, RARITY[1].w * (1 + boost), RARITY[2].w * (1 + boost * 2), RARITY[3].w * (1 + boost * 3)];
  let t = w.reduce((a, b) => a + b, 0), r = Math.random() * t;
  for (let i = 0; i < 4; i++) { r -= w[i]; if (r <= 0) return i; }
  return 0;
}

function genItem(ilvl, boost = 0, forceRarity = null, forceSlot = null) {
  const rarity = forceRarity ?? rollRarity(boost);
  let slot = forceSlot || pick(SLOTS), legend = null, base;
  if (rarity === 3) {
    legend = pick(forceSlot ? LEGENDARY.filter(l => l.slot === forceSlot) : LEGENDARY);
    slot = legend.slot;
    base = BASES[slot][Math.min(legend.base, BASES[slot].length - 1)];
  } else {
    base = pick(BASES[slot]);
  }
  const it = { uid: uid(), slot, base: base.name, rarity, ilvl, mods: {}, implicit: { ...(base.implicit || {}) } };
  const grow = 1 + ilvl * 0.22;
  if (slot === 'weapon') {
    it.min = Math.round(base.min * grow); it.max = Math.round(base.max * grow); it.aps = base.aps;
    if (rarity === 3) { it.min = Math.round(it.min * 1.25); it.max = Math.round(it.max * 1.25); }
  }
  if (base.armor) it.armor = Math.round(base.armor * (1 + ilvl * 0.2));

  addAffixes(it, randi(...RARITY[rarity].aff));
  if (rarity === 3) { it.name = legend.name; it.effect = legend.effect; it.desc = legend.desc; }
  else nameItem(it);
  return it;
}

function rollAffixValue(it, a) {
  const v = (a.min + Math.random() * (a.max - a.min)) * (1 + it.ilvl * a.sc) * (it.rarity === 3 ? 1.2 : 1);
  return Math.max(1, Math.round(v));
}
function addAffixes(it, n) {
  const pool = AFFIXES.filter(a => a.slots.includes(it.slot) && !(a.k in it.mods));
  for (let i = 0; i < n && pool.length; i++) {
    const a = pool.splice(Math.floor(Math.random() * pool.length), 1)[0];
    it.mods[a.k] = rollAffixValue(it, a);
  }
}
function nameItem(it) {
  if (it.rarity === 0) it.name = it.base;
  else if (it.rarity === 1) { const k = Object.keys(it.mods)[0]; it.name = (k ? AFFIX_BY_KEY[k].word : '') + it.base; }
  else if (it.rarity === 2) it.name = pick(RARE_A) + pick(RARE_B);
}

// ---- crafting with currency: returns an error message, or null on success ----
const affixCount = it => Object.keys(it.mods).length;
const CRAFT = {
  transmute(it) {
    if (it.rarity !== 0) return 'ノーマルアイテムにのみ使えます';
    it.rarity = 1; addAffixes(it, randi(1, 2)); nameItem(it);
  },
  ascend(it) {
    if (it.rarity !== 1) return 'マジックアイテムにのみ使えます';
    it.rarity = 2; addAffixes(it, randi(3, 4) - affixCount(it)); nameItem(it);
  },
  chaos(it) {
    if (it.rarity !== 1 && it.rarity !== 2) return 'マジック・レアアイテムにのみ使えます';
    it.mods = {}; addAffixes(it, randi(...RARITY[it.rarity].aff)); nameItem(it);
  },
  whet(it) {
    if (it.rarity !== 1 && it.rarity !== 2) return 'マジック・レアアイテムにのみ使えます';
    if (affixCount(it) >= RARITY[it.rarity].aff[1]) return 'これ以上オプションを追加できません';
    const before = affixCount(it);
    addAffixes(it, 1);
    if (affixCount(it) === before) return '追加できるオプションがありません';
  },
  purify(it) {
    if (it.rarity !== 1 && it.rarity !== 2) return 'マジック・レアアイテムにのみ使えます';
    it.rarity = 0; it.mods = {}; nameItem(it);
  },
  divine(it) {
    if (!affixCount(it)) return 'オプションのあるアイテムにのみ使えます';
    for (const k in it.mods) it.mods[k] = rollAffixValue(it, AFFIX_BY_KEY[k]);
  },
};

const sellPrice = it => Math.round((3 + it.ilvl * 2) * (1 + it.rarity * 2));
const discount = () => 1 - apVal('haggle') / 100;
const buyPrice = it => Math.round(sellPrice(it) * 5 * discount());
const potionPrice = () => Math.round((15 + G.floor * 8) * discount());
const rerollPrice = () => 25 + G.floor * 15;
const currencyPrice = c => Math.round(c.value * 4 * discount());

function genShop() {
  const items = [];
  for (let i = 0; i < 8; i++) {
    const r = Math.random();
    items.push(genItem(G.floor + 1, 1, r < 0.05 ? 3 : r < 0.35 ? 2 : 1));
  }
  return { floor: G.floor, items };
}

function itemLines(it) {
  const lines = [];
  lines.push({ t: it.name, c: RARITY[it.rarity].color, big: true });
  lines.push({ t: `${RARITY[it.rarity].name} ${SLOT_INFO[it.slot].name}` + (it.rarity >= 2 ? `（${it.base}）` : ''), c: '#9a9080' });
  lines.push({ t: `アイテムレベル ${it.ilvl}`, c: '#7a7266' });
  if (it.slot === 'weapon') {
    const f = it.mods.flatDmg || 0;
    lines.push({ t: `ダメージ ${it.min + f}–${it.max + f}`, c: '#fff' });
    lines.push({ t: `攻撃/秒 ${it.aps.toFixed(2)}`, c: '#fff' });
  }
  if (it.armor) lines.push({ t: `アーマー ${it.armor}`, c: '#fff' });
  for (const k in it.implicit) lines.push({ t: AFFIX_BY_KEY[k].fmt.replace('{v}', it.implicit[k]), c: '#b8b0a0' });
  if (Object.keys(it.mods).length) lines.push({ sep: true });
  for (const k in it.mods) lines.push({ t: AFFIX_BY_KEY[k].fmt.replace('{v}', it.mods[k]), c: '#8fb4ff' });
  if (it.desc) { lines.push({ sep: true }); lines.push({ t: it.desc, c: '#ff9a4a' }); }
  return lines;
}
