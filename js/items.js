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

  const [lo, hi] = RARITY[rarity].aff;
  const n = randi(lo, hi);
  const pool = AFFIXES.filter(a => a.slots.includes(slot));
  const chosen = [];
  while (chosen.length < n && pool.length) chosen.push(...pool.splice(Math.floor(Math.random() * pool.length), 1));
  for (const a of chosen) {
    const v = (a.min + Math.random() * (a.max - a.min)) * (1 + ilvl * a.sc) * (rarity === 3 ? 1.2 : 1);
    it.mods[a.k] = Math.max(1, Math.round(v));
  }

  if (rarity === 0) it.name = base.name;
  else if (rarity === 1) it.name = (chosen[0] ? chosen[0].word : '') + base.name;
  else if (rarity === 2) it.name = pick(RARE_A) + pick(RARE_B);
  else { it.name = legend.name; it.effect = legend.effect; it.desc = legend.desc; }
  return it;
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
