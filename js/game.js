'use strict';
const G = {
  state: 'title', floor: 1, time: 0, shake: 0, cam: { x: 0, y: 0 },
  enemies: [], projs: [], eprojs: [], particles: [], texts: [], effects: [], hazards: [], tele: [], storms: [],
  ground: [], golds: [], portal: null, boss: null, flowT: 0, merchant: null, shop: null,
};
const BAG_SIZE = 30;
const xpNeed = l => Math.round(25 * Math.pow(l, 1.7) + 20);

// =================== player ===================
class Player {
  constructor() {
    this.x = 0; this.y = 0; this.r = 13;
    this.level = 1; this.xp = 0; this.talentPts = 0;
    this.talents = Object.fromEntries(TALENTS.map(t => [t.k, 0]));
    this.equip = {}; this.bag = []; this.slots = [...DEFAULT_SLOTS];
    this.filter = defaultFilter();
    this.gold = 0; this.potions = 3; this.potionProg = 0;
    this.cds = {}; this.actionT = 0; this.swingT = 0; this.aim = 0;
    this.invuln = 0; this.hitFlash = 0; this.walkT = 0; this.dash = null; this.dead = false;
    this.equip.weapon = genItem(1, 0, 0, 'weapon');
    this.equip.weapon.base = this.equip.weapon.name = '片手剣';
    this.equip.weapon.min = 5; this.equip.weapon.max = 9; this.equip.weapon.aps = 1.5;
    this.recalc(true);
  }

  recalc(full = false) {
    const L = this.level, tl = this.talents;
    const s = {
      maxLife: 90 + L * 12, maxMana: 60 + L * 5, lifeRegen: 1.5 + L * 0.25, manaRegen: 5 + L * 0.3,
      dmgMin: 2 + L, dmgMax: 4 + L * 2, aps: 1.3,
      incDmg: 0, flatDmg: 0, crit: 5, critMulti: 150, atkSpd: 0, castSpd: 0, moveSpd: 0, armor: 0,
      fireDmg: 0, coldDmg: 0, lightDmg: 0, spellDmg: 0, lifeOnKill: 0, cdr: 0, life: 0, mana: 0,
      effects: new Set(),
    };
    for (const slot in this.equip) {
      const it = this.equip[slot];
      if (!it) continue;
      if (it.slot === 'weapon') { s.dmgMin += it.min; s.dmgMax += it.max; s.aps = it.aps; }
      if (it.armor) s.armor += it.armor;
      for (const src of [it.implicit, it.mods]) for (const k in src) s[k] = (s[k] || 0) + src[k];
      if (it.effect) s.effects.add(it.effect);
    }
    s.dmgMin += s.flatDmg; s.dmgMax += s.flatDmg;
    s.maxLife += s.life + tl.vitality * 20;
    s.maxMana += s.mana + tl.spirit * 12;
    s.manaRegen += tl.spirit * 0.5;
    s.lifeRegen += apVal('ward');
    s.incDmg += tl.might * 8;
    s.moveSpd += tl.swift * 3; s.atkSpd += tl.swift * 3;
    s.crit += tl.precision * 1.5; s.critMulti += tl.precision * 8;
    s.moveSpeed = 220 * (1 + s.moveSpd / 100);
    s.attackRate = s.aps * (1 + s.atkSpd / 100);
    s.dr = Math.min(0.75, s.armor / (s.armor + 60 + G.floor * 12));
    s.cdr = Math.min(40, s.cdr);
    const lr = this.s ? this.life / this.s.maxLife : 1, mr = this.s ? this.mana / this.s.maxMana : 1;
    this.s = s;
    this.life = full ? s.maxLife : s.maxLife * lr;
    this.mana = full ? s.maxMana : s.maxMana * mr;
  }

  gainXp(v) {
    this.xp += v;
    while (this.xp >= xpNeed(this.level)) {
      this.xp -= xpNeed(this.level);
      this.level++; this.talentPts++;
      this.recalc(true);
      addText(this.x, this.y - 40, 'LEVEL UP!', '#ffe27a', 26);
      G.effects.push({ kind: 'ring', x: this.x, y: this.y, r0: 10, r1: 120, t: 0, max: 0.6, color: '255,226,122' });
      burst(this.x, this.y, 40, '#ffe27a', 260, true);
      showMsg(`レベル ${this.level} に到達！ タレントポイント +1（Tキー）`, '#ffe27a');
      for (const id of SKILL_LIST) if (SKILLS[id].lvl === this.level) showMsg(`新スキル「${SKILLS[id].name}」を習得！（Kで付け替え）`, SKILLS[id].color);
      UI.refresh();
    }
  }
}

function worldMouse() { return { x: Input.mx + G.cam.x - G.vw / 2, y: Input.my + G.cam.y - G.vh / 2 }; }

function updatePlayer(dt) {
  const p = G.player, s = p.s;
  if (p.dead) return;
  p.life = Math.min(s.maxLife, p.life + s.lifeRegen * dt);
  p.mana = Math.min(s.maxMana, p.mana + s.manaRegen * dt);
  for (const k in p.cds) if (p.cds[k] > 0) p.cds[k] -= dt;
  p.actionT -= dt; p.swingT -= dt; p.invuln -= dt; p.hitFlash -= dt; p.chill = (p.chill || 0) - dt;
  if (p.chill > 0 && Math.random() < 0.3) G.particles.push({ x: p.x + rand(-12, 12), y: p.y + rand(-12, 12), vx: 0, vy: -20, t: 0, max: 0.5, size: 3, color: '#bff4ff', glow: true });
  const wm = worldMouse();
  p.aim = Math.atan2(wm.y - p.y, wm.x - p.x);

  if (p.dash) { updateDash(p, dt); return; }

  let mx = 0, my = 0;
  if (Input.keys.KeyW) my--; if (Input.keys.KeyS) my++;
  if (Input.keys.KeyA) mx--; if (Input.keys.KeyD) mx++;
  if (mx || my) {
    const l = Math.hypot(mx, my), sp = s.moveSpeed * (p.actionT > 0 ? 0.5 : 1) * (p.chill > 0 ? 0.6 : 1);
    moveCircle(p, mx / l * sp * dt, my / l * sp * dt);
    p.walkT += dt;
  }
  const mer = G.merchant;
  if (mer && dist2(p.x, p.y, mer.x, mer.y) < 200 * 200 &&
      (Input.pressed.KeyB || (Input.mdown[0] && dist2(wm.x, wm.y, mer.x, mer.y) < 30 * 30))) {
    UI.toggle('shop');
    return;
  }
  SKILL_SLOTS.forEach((slot, i) => { if (slot.on()) tryCast(p.slots[i]); });
  if (Input.pressed.KeyF) usePotion();
  G.map.reveal(p.x, p.y);
}

function usePotion() {
  const p = G.player;
  if (p.potions <= 0) { showMsg('回復薬がない', '#ff8080'); return; }
  if (p.life >= p.s.maxLife) return;
  p.potions--;
  p.life = Math.min(p.s.maxLife, p.life + p.s.maxLife * 0.5);
  burst(p.x, p.y, 20, '#ff5a5a', 120, true);
  addText(p.x, p.y - 30, '+' + Math.round(p.s.maxLife * 0.5), '#6f6', 18);
}

function damagePlayer(amount, src) {
  const p = G.player;
  if (p.dead || p.invuln > 0) return;
  const d = Math.max(1, Math.round(amount * (1 - p.s.dr)));
  p.life -= d; p.hitFlash = 0.15;
  addText(p.x + rand(-10, 10), p.y - 28, d, '#ff5050', 16);
  G.shake = Math.max(G.shake, 4);
  if (p.s.effects.has('novaOnHit') && Math.random() < 0.2) CAST.nova(p, true);
  if (p.life <= 0) {
    p.life = 0; p.dead = true;
    burst(p.x, p.y, 60, '#a01010', 200, false);
    setTimeout(() => UI.showDeath(), 900);
  }
}

// =================== combat ===================
function rollDamage(coef, type, spell, skill) {
  const p = G.player, s = p.s;
  let d = rand(s.dmgMin, s.dmgMax) * coef;
  const elem = type === 'fire' ? s.fireDmg : type === 'cold' ? s.coldDmg : type === 'light' ? s.lightDmg : 0;
  d *= (1 + (s.incDmg + (spell ? s.spellDmg : 0) + elem) / 100) * (1 + 0.15 * (p.talents[skill] || 0));
  const crit = Math.random() * 100 < s.crit;
  if (crit) d *= s.critMulti / 100;
  return { dmg: Math.max(1, Math.round(d)), crit, type };
}

const DMG_COLORS = { phys: '#ffffff', fire: '#ff9a40', cold: '#8fdcff', light: '#d9b8ff' };
function hitEnemy(e, hit, freeze = 0) {
  if (e.dead) return;
  e.life -= hit.dmg; e.hitT = 0.12;
  if (!e.aggro) alertPack(e);
  addText(e.x + rand(-12, 12), e.y - e.r - 12, hit.dmg + (hit.crit ? '!' : ''), hit.crit ? '#ffe040' : DMG_COLORS[hit.type], hit.crit ? 22 : 15);
  if (freeze && !e.boss) e.frozen = Math.max(e.frozen, freeze);
  if (freeze && e.boss) e.slow = Math.max(e.slow, freeze);
  for (let i = 0; i < 3; i++) G.particles.push({ x: e.x, y: e.y, vx: rand(-90, 90), vy: rand(-90, 90), t: 0, max: 0.35, size: 3, color: e.boss ? '#600' : '#5a1010' });
  if (e.life <= 0) killEnemy(e);
}

function enemiesInRadius(x, y, r) {
  return G.enemies.filter(e => !e.dead && dist2(x, y, e.x, e.y) < (r + e.r) ** 2);
}

function killEnemy(e) {
  e.dead = true;
  const p = G.player;
  p.gainXp(Math.round(e.xp * G.modFx.xp));
  p.life = Math.min(p.s.maxLife, p.life + p.s.lifeOnKill + (p.s.effects.has('killHeal') ? p.s.maxLife * 0.03 : 0));
  if (++p.potionProg >= 14) { p.potionProg = 0; if (p.potions < maxPotions()) { p.potions++; addText(p.x, p.y - 44, '回復薬 +1', '#ff7070', 14); } }
  burst(e.x, e.y, e.boss ? 80 : 14, e.t.color, e.boss ? 300 : 150, false);
  for (let i = 0; i < 6; i++) G.particles.push({ x: e.x, y: e.y, vx: rand(-40, 40), vy: rand(-40, 40), t: 0, max: 6, size: rand(3, 6), color: 'rgba(70,10,10,0.8)', drag: 6, decal: true });

  // loot
  const ilvl = G.floor + (e.elite ? 1 : 0) + (e.boss ? 2 : 0);
  const fx = G.modFx;
  let drops = 0, boost = fx.rarity;
  if (e.boss) { drops = 4; boost += 2.5; }
  else if (e.elite) { drops = randi(1, 2); boost += 1.2; }
  else if (Math.random() < 0.13 * fx.quantity) drops = 1;
  if ((e.boss || e.elite) && Math.random() < fx.quantity - 1) drops++;
  for (let i = 0; i < drops; i++) dropItem(genItem(ilvl, boost, e.boss && i === 0 ? (Math.random() < 0.35 + fx.legend ? 3 : 2) : null), e.x, e.y);
  if (Math.random() < (e.elite || e.boss ? 1 : 0.25)) {
    const n = e.boss ? 6 : e.elite ? 3 : 1;
    for (let i = 0; i < n; i++) G.golds.push({ x: e.x + rand(-30, 30), y: e.y + rand(-30, 30), amt: Math.round(rand(2, 6) * G.floor * (e.elite ? 2 : 1) * fx.gold) });
  }

  if (e.elite && e.elite.k === 'volatile') {
    addTele(e.x, e.y, 90, 0.8, true, () => {
      explosionFx(e.x, e.y, 90, '255,120,60');
      if (dist(e.x, e.y, p.x, p.y) < 90 + p.r) damagePlayer(e.dmg * 1.5);
    });
  }
  if (e.boss) {
    G.boss = null;
    G.portal = { x: e.x, y: e.y, t: 0 };
    showMsg(`${e.name}を討伐した！ ポータルが開いた`, '#ff9a4a');
    UI.setBoss(null);
  }
}

// ---- item filter ----
// per rarity: 'pick' | 'sell' (sold the moment it's picked up) | 'hide' (left on the ground, not shown)
// unchecked equipment slots are hidden too, except legendaries
function defaultFilter() {
  return { rarity: ['pick', 'pick', 'pick', 'pick'], slots: Object.fromEntries(SLOTS.map(s => [s, true])) };
}
function itemAction(it) {
  const f = G.player.filter;
  if (it.rarity < 3 && !f.slots[it.slot]) return 'hide';
  return f.rarity[it.rarity];
}
const willAutoSell = it => itemAction(it) === 'sell';
const isHidden = it => itemAction(it) === 'hide';

function collectNearbyLoot(radius) {
  const p = G.player;
  let n = 0, gold = 0;
  for (const g of G.golds) if (dist2(g.x, g.y, p.x, p.y) < radius * radius) { g.dead = true; gold += g.amt; }
  for (const g of G.ground) {
    if (isHidden(g.item) || dist2(g.x, g.y, p.x, p.y) > radius * radius) continue;
    if (!pickupItem(g.item, g.x, g.y, false, true)) continue;
    g.dead = true; n++;
  }
  p.gold += gold;
  G.golds = G.golds.filter(g => !g.dead);
  G.ground = G.ground.filter(g => !g.dead);
  if (n || gold) showMsg(`ポータル周辺のアイテム ${n} 点${gold ? `と ${gold} ゴールド` : ''}を回収した`, '#ffd36a');
  const left = G.ground.filter(g => !isHidden(g.item) && dist2(g.x, g.y, p.x, p.y) < radius * radius).length;
  if (left) showMsg(`インベントリが一杯で ${left} 点を拾えなかった`, '#ff8080');
}
// returns false when the item can't be taken (bag full)
function pickupItem(it, x, y, byPet = false, quiet = false) {
  const p = G.player;
  if (willAutoSell(it)) {
    const g = sellPrice(it);
    p.gold += g;
    addText(x, y - 20, `自動売却 +${g}`, '#ffcf3a', 13);
    return true;
  }
  if (p.bag.length >= BAG_SIZE) return false;
  p.bag.push(it);
  if (!quiet || it.rarity >= 2) showMsg(byPet ? `${PET_NAME}が ${it.name} を拾ってきた` : `${it.name} を拾った`, RARITY[it.rarity].color);
  UI.refresh();
  return true;
}

// hidden items never touch the ground: they're sold the moment they drop
function sellHidden(it, x, y) {
  const g = sellPrice(it);
  G.player.gold += g;
  addText(x, y - 10, `+${g}`, '#b8a060', 11);
}
function sellHiddenGround() {
  for (const g of G.ground) if (isHidden(g.item)) { sellHidden(g.item, g.x, g.y); g.dead = true; }
  G.ground = G.ground.filter(g => !g.dead);
}

function dropItem(it, x, y) {
  if (isHidden(it)) { sellHidden(it, x, y); return; }
  const a = rand(0, TAU), d = rand(10, 45);
  let gx = x + Math.cos(a) * d, gy = y + Math.sin(a) * d;
  if (G.map.solidAt(gx, gy)) { gx = x; gy = y; }
  G.ground.push({ item: it, x: gx, y: gy, t: 0 });
}

function addTele(x, y, r, dur, hostile, onDone) { G.tele.push({ x, y, r, t: 0, max: dur, hostile, onDone }); }
function addText(x, y, str, color, size = 15) { G.texts.push({ x, y, str: String(str), color, size, t: 0, vy: -55 }); }
function burst(x, y, n, color, speed, glow) {
  for (let i = 0; i < n; i++) {
    const a = rand(0, TAU), sp = rand(speed * 0.2, speed);
    G.particles.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, t: 0, max: rand(0.3, 0.7), size: rand(2, 4), color, glow, drag: 3 });
  }
}
function explosionFx(x, y, r, rgb) {
  G.effects.push({ kind: 'ring', x, y, r0: r * 0.2, r1: r, t: 0, max: 0.35, color: rgb, fill: true });
  burst(x, y, Math.round(r / 3), `rgb(${rgb})`, r * 3, true);
  G.shake = Math.max(G.shake, r / 12);
}

// =================== skills ===================
function tryCast(id) {
  const p = G.player, sk = SKILLS[id];
  if (p.actionT > 0 && id !== 'dash') return;
  if ((p.cds[id] || 0) > 0) return;
  if (p.mana < sk.mana) { if (!G.oomT || G.time - G.oomT > 1.2) { G.oomT = G.time; showMsg('マナが足りない', '#7fa8ff'); } return; }
  if (id === 'chain' && !findChainTarget()) return;
  p.mana -= sk.mana;
  if (sk.cd) p.cds[id] = sk.cd * (1 - p.s.cdr / 100);
  if (sk.attack) p.actionT = 1 / p.s.attackRate;
  else if (sk.cast) p.actionT = sk.cast / (1 + p.s.castSpd / 100);
  CAST[id](p);
}

function findChainTarget() {
  const p = G.player, wm = worldMouse();
  let best = null, bd = Infinity;
  for (const e of G.enemies) {
    if (e.dead || dist2(p.x, p.y, e.x, e.y) > 450 * 450) continue;
    const d = dist2(wm.x, wm.y, e.x, e.y);
    if (d < bd && G.map.los(p.x, p.y, e.x, e.y)) { bd = d; best = e; }
  }
  return best;
}

const CAST = {
  slash(p) {
    p.swingT = 0.2; p.swingDir = p.aim;
    const range = 78;
    for (const e of G.enemies) {
      if (e.dead) continue;
      const d = dist(p.x, p.y, e.x, e.y);
      if (d > range + e.r) continue;
      if (Math.abs(angleDiff(p.aim, Math.atan2(e.y - p.y, e.x - p.x))) > 1.15 && d > e.r + p.r) continue;
      hitEnemy(e, rollDamage(1.0, 'phys', false, 'slash'));
    }
    G.effects.push({ kind: 'arc', x: p.x, y: p.y, a: p.aim, r: range, t: 0, max: 0.18 });
    if (p.s.effects.has('slashWave')) {
      G.projs.push({ kind: 'wave', x: p.x, y: p.y, vx: Math.cos(p.aim) * 650, vy: Math.sin(p.aim) * 650, r: 22, t: 0, max: 0.55, hit: new Set(), a: p.aim });
    }
  },
  whirl(p) {
    const R = 105;
    for (const e of enemiesInRadius(p.x, p.y, R)) hitEnemy(e, rollDamage(0.85, 'phys', false, 'whirl'));
    G.effects.push({ kind: 'spin', x: p.x, y: p.y, a: p.aim, r: R, t: 0, max: 0.22 });
    p.swingT = 0.2; p.swingDir = p.aim;
  },
  iceSpear(p) {
    const a = p.aim;
    G.projs.push({ kind: 'spear', x: p.x + Math.cos(a) * 16, y: p.y + Math.sin(a) * 16, vx: Math.cos(a) * 820, vy: Math.sin(a) * 820, r: 9, t: 0, max: 0.8, hit: new Set(), a });
  },
  storm(p) {
    const wm = worldMouse();
    const a = Math.atan2(wm.y - p.y, wm.x - p.x), d = Math.min(480, dist(p.x, p.y, wm.x, wm.y));
    G.storms.push({ x: p.x + Math.cos(a) * d, y: p.y + Math.sin(a) * d, r: 170, t: 0, max: 3, tick: 0.1 });
  },
  fireball(p) {
    const angles = p.s.effects.has('fireballMulti') ? [-0.22, 0, 0.22] : [0];
    for (const da of angles) {
      const a = p.aim + da;
      G.projs.push({ kind: 'fireball', x: p.x + Math.cos(a) * 16, y: p.y + Math.sin(a) * 16, vx: Math.cos(a) * 620, vy: Math.sin(a) * 620, r: 8, t: 0, max: 1.4 });
    }
  },
  nova(p, free = false) {
    const R = 185;
    G.effects.push({ kind: 'ring', x: p.x, y: p.y, r0: 20, r1: R, t: 0, max: 0.4, color: '140,220,255', fill: true });
    burst(p.x, p.y, 50, '#aee8ff', 520, true);
    for (const e of enemiesInRadius(p.x, p.y, R)) hitEnemy(e, rollDamage(free ? 0.8 : 1.3, 'cold', true, 'nova'), 1.8);
  },
  chain(p) {
    let target = findChainTarget();
    const hit = new Set();
    let sx = p.x, sy = p.y;
    let n = 5 + (p.s.effects.has('chainPlus') ? 4 : 0);
    while (target && n-- > 0) {
      hit.add(target);
      G.effects.push({ kind: 'bolt', x0: sx, y0: sy, x1: target.x, y1: target.y, t: 0, max: 0.22 });
      burst(target.x, target.y, 6, '#d9c2ff', 150, true);
      hitEnemy(target, rollDamage(1.15, 'light', true, 'chain'));
      sx = target.x; sy = target.y;
      let next = null, bd = 260 * 260;
      for (const e of G.enemies) {
        if (e.dead || hit.has(e)) continue;
        const d = dist2(sx, sy, e.x, e.y);
        if (d < bd && G.map.los(sx, sy, e.x, e.y)) { bd = d; next = e; }
      }
      target = next;
    }
  },
  meteor(p) {
    const wm = worldMouse();
    const a = Math.atan2(wm.y - p.y, wm.x - p.x), d = Math.min(520, dist(p.x, p.y, wm.x, wm.y));
    const tx = p.x + Math.cos(a) * d, ty = p.y + Math.sin(a) * d;
    const drop = (x, y, delay) => addTele(x, y, 115, delay, false, () => {
      explosionFx(x, y, 115, '255,110,40');
      for (const e of enemiesInRadius(x, y, 115)) hitEnemy(e, rollDamage(3.6, 'fire', true, 'meteor'));
      G.hazards.push({ x, y, r: 95, t: 0, max: 3.5, tick: 0 });
    });
    drop(tx, ty, 0.75);
    if (p.s.effects.has('meteorShower')) {
      drop(tx + rand(-130, 130), ty + rand(-130, 130), 1.0);
      drop(tx + rand(-130, 130), ty + rand(-130, 130), 1.25);
    }
  },
  dash(p) {
    const wm = worldMouse();
    const a = Math.atan2(wm.y - p.y, wm.x - p.x);
    p.dash = { dx: Math.cos(a), dy: Math.sin(a), left: Math.min(280, Math.max(120, dist(p.x, p.y, wm.x, wm.y))), hit: new Set() };
    p.invuln = 0.3;
  },
};

function updateDash(p, dt) {
  const d = p.dash;
  let step = Math.min(d.left, 1600 * dt);
  d.left -= step;
  while (step > 0) {
    const s = Math.min(8, step); step -= s;
    const ox = p.x, oy = p.y;
    moveCircle(p, d.dx * s, d.dy * s);
    if (Math.abs(p.x - ox) + Math.abs(p.y - oy) < 0.5) { d.left = 0; break; }
  }
  G.particles.push({ x: p.x, y: p.y, vx: 0, vy: 0, t: 0, max: 0.3, size: 11, color: 'rgba(140,120,255,0.5)', glow: true });
  for (const e of G.enemies) {
    if (e.dead || d.hit.has(e) || dist2(p.x, p.y, e.x, e.y) > (e.r + p.r + 14) ** 2) continue;
    d.hit.add(e);
    hitEnemy(e, rollDamage(0.9, 'phys', false, 'dash'));
  }
  if (d.left <= 0) {
    p.dash = null;
    if (p.s.effects.has('dashNova')) CAST.nova(p, true);
  }
}

// =================== enemies ===================
function makeEnemy(type, x, y, pack, eliteAffix = null) {
  const t = ENEMY_TYPES[type], f = G.floor - 1;
  const lm = 1 + 0.5 * f + 0.05 * f * f, dm = 1 + 0.3 * f;
  const e = {
    t, type, x, y, r: t.r, maxLife: t.life * lm, dmg: t.dmg * dm, speed: t.speed * rand(0.9, 1.1),
    atkCdMul: 1, atkCd: rand(0.2, 1), windup: 0, pending: null, hitT: 0, frozen: 0, slow: 0,
    aggro: false, los: false, losT: rand(0, 0.2), face: rand(0, TAU), xp: t.xp * (1 + 0.25 * f),
    elite: null, pack, name: t.name, boss: !!t.boss, wanderT: rand(0, 2), actT: 2,
  };
  if (eliteAffix) {
    e.elite = eliteAffix; e.name = `${eliteAffix.name}の${t.name}`;
    e.maxLife *= 3; e.r *= 1.25; e.xp *= 4; e.dmg *= 1.25;
    if (eliteAffix.k === 'swift') { e.speed *= 1.5; e.atkCdMul = 0.65; }
    if (eliteAffix.k === 'armored') e.maxLife *= 1.8;
    if (eliteAffix.k === 'frenzied') e.dmg *= 1.5;
  }
  const fx = G.modFx || modEffects([]);
  e.maxLife *= fx.life; e.dmg *= fx.dmg; e.speed *= fx.speed;
  e.life = e.maxLife;
  G.enemies.push(e);
  return e;
}

function alertPack(e) {
  e.aggro = true;
  for (const o of G.enemies) if (o.pack === e.pack && !o.aggro && dist2(o.x, o.y, e.x, e.y) < 500 * 500) o.aggro = true;
}

function updateEnemy(e, dt) {
  const p = G.player;
  e.hitT -= dt; e.atkCd -= dt; e.slow -= dt;
  if (e.frozen > 0) { e.frozen -= dt; return; }
  const d = dist(e.x, e.y, p.x, p.y);
  e.losT -= dt;
  if (e.losT <= 0) { e.losT = 0.2 + Math.random() * 0.1; e.los = d < 750 && G.map.los(e.x, e.y, p.x, p.y); }
  if (!e.aggro) {
    if ((d < 380 && e.los) || (e.boss && d < 500 && e.los)) {
      alertPack(e);
    } else {
      e.wanderT -= dt;
      if (e.wanderT < 0) { e.wanderT = rand(1.5, 4); e.face = rand(0, TAU); e.wandering = rand(0.3, 0.9); }
      if (e.wandering > 0) { e.wandering -= dt; moveCircle(e, Math.cos(e.face) * e.speed * 0.3 * dt, Math.sin(e.face) * e.speed * 0.3 * dt); }
      return;
    }
  }
  if (p.dead) return;
  if (e.windup > 0) {
    e.windup -= dt;
    if (e.windup <= 0 && e.pending) { const fn = e.pending; e.pending = null; fn(); }
    return;
  }
  if (e.boss) { updateBoss(e, dt, d); return; }

  const t = e.t;
  let move = true;
  if (t.ranged || t.caster) {
    if (d < t.range && e.los) {
      move = false;
      if (t.ranged && d < 150) moveCircle(e, -(p.x - e.x) / d * e.speed * 0.7 * dt, -(p.y - e.y) / d * e.speed * 0.7 * dt);
      if (e.atkCd <= 0) startAttack(e);
    }
  } else if (d < t.atkRange + e.r + p.r) {
    move = false;
    if (e.atkCd <= 0) startAttack(e);
  }
  if (move) chase(e, dt);
  e.face = Math.atan2(p.y - e.y, p.x - e.x);
}

function chase(e, dt) {
  const p = G.player;
  let tx = p.x, ty = p.y;
  if (!e.los) { const n = G.map.flowNext(e.x, e.y); if (!n) return; tx = n.x; ty = n.y; }
  const dx = tx - e.x, dy = ty - e.y, l = Math.hypot(dx, dy) || 1;
  const sp = e.speed * (e.slow > 0 ? 0.5 : 1);
  moveCircle(e, dx / l * sp * dt, dy / l * sp * dt);
}

function startAttack(e) {
  const p = G.player, t = e.t;
  e.atkCd = t.atkCd * e.atkCdMul;
  e.windup = t.windup;
  if (t.ranged) {
    e.pending = () => {
      if (e.dead) return;
      const a = Math.atan2(p.y - e.y, p.x - e.x);
      G.eprojs.push({ x: e.x, y: e.y, vx: Math.cos(a) * 360, vy: Math.sin(a) * 360, r: 5, dmg: e.dmg, t: 0, max: 2, color: '#e8e0b0' });
    };
  } else if (t.caster) {
    const tx = p.x, ty = p.y;
    addTele(tx, ty, 65, t.windup + 0.15, true, () => {
      explosionFx(tx, ty, 65, '90,220,240');
      if (dist(tx, ty, p.x, p.y) < 65 + p.r) damagePlayer(e.dmg);
    });
    e.pending = () => {};
  } else if (t.aoe) {
    addTele(e.x, e.y, t.aoe, t.windup, true, () => {
      if (e.dead || e.frozen > 0) return;
      explosionFx(e.x, e.y, t.aoe, '200,140,255');
      if (dist(e.x, e.y, p.x, p.y) < t.aoe + p.r) damagePlayer(e.dmg);
    });
    e.pending = () => {};
  } else {
    e.lunge = 0.15;
    e.pending = () => {
      if (dist(e.x, e.y, p.x, p.y) < t.atkRange + e.r + p.r + 12) damagePlayer(e.dmg);
    };
  }
}

function updateBoss(e, dt, d) {
  const p = G.player;
  if (!e.announced) { e.announced = true; UI.setBoss(e); showMsg(`${e.name} が目覚めた！`, '#ff6040'); }
  if (e.charge) { updateCharge(e, dt); return; }
  const enraged = e.life < e.maxLife * 0.5;
  if (enraged && !e.enraged) {
    e.enraged = true;
    showMsg(`${e.name} が激昂した！`, '#ff6040');
    burst(e.x, e.y, 50, e.t.color, 300, true);
    G.shake = Math.max(G.shake, 8);
  }
  e.actT -= dt;
  if (e.actT <= 0) { BOSS_AI[e.type](e, d, enraged); return; }
  if (e.type === 'witch') {
    // keeps her distance and pelts the player from range
    const sp = e.speed * (e.slow > 0 ? 0.5 : 1);
    if (d < 220) moveCircle(e, -(p.x - e.x) / d * sp * dt, -(p.y - e.y) / d * sp * dt);
    else if (d > 380 || !e.los) chase(e, dt);
  } else if (d > e.r + p.r + 30) chase(e, dt);
  else if (e.atkCd <= 0) {
    e.atkCd = 1.6; e.windup = 0.4;
    e.pending = () => { if (dist(e.x, e.y, p.x, p.y) < e.r + p.r + 40) damagePlayer(e.dmg); };
  }
  e.face = Math.atan2(p.y - e.y, p.x - e.x);
}

function updateCharge(e, dt) {
  const p = G.player, c = e.charge;
  let step = Math.min(c.left, 760 * dt);
  c.left -= step;
  while (step > 0) {
    const s = Math.min(8, step); step -= s;
    const ox = e.x, oy = e.y;
    moveCircle(e, c.dx * s, c.dy * s);
    if (Math.abs(e.x - ox) + Math.abs(e.y - oy) < 0.5) { c.left = 0; break; }
    c.trail += s;
    if (c.trail > 45) { c.trail = 0; G.hazards.push({ x: e.x, y: e.y, r: 42, t: 0, max: 2.2, tick: 0.3, hostile: true, dmg: e.dmg * 0.3 }); }
  }
  burst(e.x, e.y, 3, '#ff8a3a', 120, true);
  if (!c.hit && dist(e.x, e.y, p.x, p.y) < e.r + p.r + 6) { c.hit = true; damagePlayer(e.dmg * 1.4); }
  if (c.left <= 0) {
    e.charge = null;
    explosionFx(e.x, e.y, 90, '255,110,40');
    if (dist(e.x, e.y, p.x, p.y) < 90 + p.r && !c.hit) damagePlayer(e.dmg * 0.8);
  }
}

function enemyShot(e, a, speed, dmg, rgb, extra = {}) {
  G.eprojs.push({ x: e.x, y: e.y, vx: Math.cos(a) * speed, vy: Math.sin(a) * speed, r: 7, dmg, t: 0, max: 3, rgb, ...extra });
}

const BOSS_AI = {
  boss(e, d, enraged) {
    const p = G.player;
    e.actT = enraged ? 2.2 : 3.0;
    const r = Math.random();
    if (d < 230 && r < 0.45) {
      e.windup = 1.0; e.pending = () => {};
      addTele(e.x, e.y, 175, 1.0, true, () => {
        if (e.dead) return;
        explosionFx(e.x, e.y, 175, '255,70,50');
        if (dist(e.x, e.y, p.x, p.y) < 175 + p.r) damagePlayer(e.dmg * 1.7);
      });
    } else if (r < 0.8) {
      e.windup = 0.7;
      e.pending = () => {
        const n = enraged ? 26 : 18, off = rand(0, TAU);
        for (let i = 0; i < n; i++) enemyShot(e, off + i / n * TAU, 260, e.dmg * 0.8, '255,70,50');
      };
      burst(e.x, e.y, 20, '#ff4030', 200, true);
    } else {
      e.windup = 0.6;
      e.pending = () => summonAround(e, 'imp', enraged ? 6 : 4, 70);
    }
  },

  colossus(e, d, enraged) {
    const p = G.player;
    e.actT = enraged ? 2.0 : 2.8;
    const r = Math.random();
    if (r < 0.35 && d > 120) {
      // telegraphed charge that leaves burning ground behind
      const a = Math.atan2(p.y - e.y, p.x - e.x), len = Math.min(560, d + 140);
      e.windup = 0.8;
      e.pending = () => { e.charge = { dx: Math.cos(a), dy: Math.sin(a), left: len, hit: false, trail: 0 }; };
      G.tele.push({ x: e.x, y: e.y, r: e.r, t: 0, max: 0.8, hostile: true, onDone: () => {}, line: { a, len, w: e.r * 2 } });
    } else if (r < 0.7) {
      // meteor rain around the player
      const n = enraged ? 8 : 5;
      for (let i = 0; i < n; i++) {
        const x = p.x + (i ? rand(-230, 230) : 0), y = p.y + (i ? rand(-230, 230) : 0);
        addTele(x, y, 75, 1.0 + i * 0.15, true, () => {
          explosionFx(x, y, 75, '255,110,40');
          if (dist(x, y, p.x, p.y) < 75 + p.r) damagePlayer(e.dmg * 1.1);
          G.hazards.push({ x, y, r: 60, t: 0, max: 2.5, tick: 0.4, hostile: true, dmg: e.dmg * 0.3 });
        });
      }
      e.windup = 0.5; e.pending = () => {};
      burst(e.x, e.y - 30, 30, '#ff7030', 250, true);
    } else {
      // eruption: ground slam followed by a ring of fireballs
      e.windup = 0.9; e.pending = () => {};
      addTele(e.x, e.y, 165, 0.9, true, () => {
        if (e.dead) return;
        explosionFx(e.x, e.y, 165, '255,90,30');
        if (dist(e.x, e.y, p.x, p.y) < 165 + p.r) damagePlayer(e.dmg * 1.5);
        const n = enraged ? 16 : 10, off = rand(0, TAU);
        for (let i = 0; i < n; i++) enemyShot(e, off + i / n * TAU, 300, e.dmg * 0.6, '255,120,40');
      });
    }
  },

  witch(e, d, enraged) {
    const p = G.player;
    e.actT = enraged ? 1.7 : 2.4;
    const r = Math.random();
    if (r < 0.25) {
      // blink to a new spot around the player
      for (let i = 0; i < 25; i++) {
        const a = rand(0, TAU), dd = rand(230, 330), x = p.x + Math.cos(a) * dd, y = p.y + Math.sin(a) * dd;
        if (circleHits(G.map, x, y, e.r) || !G.map.los(x, y, p.x, p.y)) continue;
        burst(e.x, e.y, 30, '#9fe8ff', 220, true);
        e.x = x; e.y = y;
        burst(x, y, 30, '#9fe8ff', 220, true);
        break;
      }
      e.actT = 0.6;
    } else if (r < 0.6) {
      // fan of chilling ice shards
      e.windup = 0.5;
      e.pending = () => {
        const n = enraged ? 11 : 7, base = Math.atan2(p.y - e.y, p.x - e.x);
        for (let i = 0; i < n; i++) enemyShot(e, base + (i - (n - 1) / 2) * 0.13, 390, e.dmg * 0.7, '150,230,255', { chill: true, r: 6 });
      };
      burst(e.x, e.y, 15, '#bff4ff', 150, true);
    } else if (r < 0.88) {
      // frost circles under and around the player
      const n = enraged ? 5 : 3;
      for (let i = 0; i < n; i++) {
        const x = p.x + (i ? rand(-170, 170) : 0), y = p.y + (i ? rand(-170, 170) : 0);
        addTele(x, y, 90, 1.1, true, () => {
          explosionFx(x, y, 90, '140,220,255');
          if (dist(x, y, p.x, p.y) < 90 + p.r) { damagePlayer(e.dmg); p.chill = 2.5; }
        });
      }
      e.windup = 0.4; e.pending = () => {};
    } else {
      e.windup = 0.6;
      e.pending = () => summonAround(e, 'archer', enraged ? 5 : 3, 80);
    }
  },
};

function summonAround(e, type, n, radius) {
  for (let i = 0; i < n; i++) {
    const a = rand(0, TAU), x = e.x + Math.cos(a) * radius, y = e.y + Math.sin(a) * radius;
    if (circleHits(G.map, x, y, ENEMY_TYPES[type].r)) continue;
    const m = makeEnemy(type, x, y, e.pack);
    m.aggro = true;
    burst(x, y, 10, ENEMY_TYPES[type].color, 120, true);
  }
}

function separateEnemies() {
  const list = G.enemies, p = G.player;
  for (let i = 0; i < list.length; i++) {
    const a = list[i];
    if (a.dead || !a.aggro) continue;
    for (let j = i + 1; j < list.length; j++) {
      const b = list[j];
      if (b.dead) continue;
      const dx = b.x - a.x, dy = b.y - a.y, rr = a.r + b.r, d2 = dx * dx + dy * dy;
      if (d2 >= rr * rr || d2 === 0) continue;
      const d = Math.sqrt(d2), push = (rr - d) / 2;
      moveCircle(a, -dx / d * push, -dy / d * push);
      moveCircle(b, dx / d * push, dy / d * push);
    }
    const dx = a.x - p.x, dy = a.y - p.y, rr = a.r + p.r, d2 = dx * dx + dy * dy;
    if (d2 < rr * rr && d2 > 0) { const d = Math.sqrt(d2); moveCircle(a, dx / d * (rr - d), dy / d * (rr - d)); }
  }
}

// =================== floor setup ===================
function spawnFloor() {
  Object.assign(G, { enemies: [], projs: [], eprojs: [], particles: [], texts: [], effects: [], hazards: [], tele: [], storms: [], ground: [], golds: [], portal: null, boss: null });
  G.area = G.area || ATLAS_NODES[0];
  G.modFx = G.modFx || modEffects([]);
  G.map = new Dungeon(72, 72, G.floor);
  const ti = nodeTheme(G.area), fx = G.modFx;
  G.theme = THEMES[ti];
  const p = G.player, m = G.map;
  p.x = m.start.cx * T + T / 2; p.y = m.start.cy * T + T / 2;
  p.dead = false; p.dash = null; p.recalc(true);
  G.cam.x = p.x; G.cam.y = p.y;

  // a merchant waits in the entrance room; stock refreshes each new floor
  let mp = m.randomFloorIn(m.start);
  for (let i = 0; i < 20 && dist2(mp.x, mp.y, p.x, p.y) < 90 * 90; i++) mp = m.randomFloorIn(m.start);
  G.merchant = { x: mp.x, y: mp.y, r: 14, merchant: true };
  G.pet = { x: p.x - 30, y: p.y + 10, r: 9, pet: true, face: 0, walkT: 0, target: null, scanT: 0, wanderT: 0, home: null, stuckT: 0, ignore: new Set() };
  if (circleHits(m, G.pet.x, G.pet.y, G.pet.r)) { G.pet.x = p.x; G.pet.y = p.y; }
  if (!G.shop || G.shop.floor !== G.floor) G.shop = genShop();

  const f = G.floor;
  const pool = [
    { k: 'imp', w: 3 }, { k: 'ghoul', w: 4 }, { k: 'archer', w: 2 },
    { k: 'brute', w: f >= 2 ? 1.5 : 0.4 }, { k: 'shaman', w: f >= 2 ? 1.5 : 0.5 },
  ];
  let packId = 0;
  for (const room of m.rooms) {
    if (room === m.start) continue;
    if (room === m.bossRoom) {
      const bt = BOSS_ROTATION[ti];
      const b = makeEnemy(bt.type, room.cx * T + T / 2, room.cy * T + T / 2, ++packId);
      b.maxLife = b.life = b.maxLife * (1 + 0.12 * (f - 1));
      G.boss = b;
      for (const g of bt.guards) { const q = m.randomFloorIn(room); makeEnemy(g, q.x, q.y, packId); }
      continue;
    }
    const packs = clamp(Math.round(room.w * room.h / 25 * fx.swarm), 2, 7);
    for (let k = 0; k < packs; k++) spawnPack(m.randomFloorIn(room), ++packId, Math.round((randi(4, 8) + Math.floor(f / 2)) * fx.swarm), pool);
  }
  // ambush packs scattered through corridors, away from the entrance
  for (let k = 0, tries = 0; k < 6 + Math.floor(f / 2) && tries < 300; tries++) {
    const tx = randi(1, m.w - 2), ty = randi(1, m.h - 2);
    if (m.isWall(tx, ty)) continue;
    const c = { x: tx * T + T / 2, y: ty * T + T / 2 };
    const br = m.bossRoom;
    if (dist2(c.x, c.y, p.x, p.y) < 700 * 700) continue;
    if (tx >= br.x - 2 && tx < br.x + br.w + 2 && ty >= br.y - 2 && ty < br.y + br.h + 2) continue;
    spawnPack(c, ++packId, randi(3, 5), [{ k: 'imp', w: 2 }, { k: 'ghoul', w: 2 }, { k: 'archer', w: 1 }]);
    k++;
  }
  showMsg(`${G.area.name}（エリアLv ${f}）— ${G.theme.name}`, '#e8d8b0');
  for (const k of G.runMods || []) showMsg(`◆ ${MOD_BY_KEY[k].name}`, '#d88a6a');
  UI.setBoss(null);
  UI.refresh();
}

// =================== pet ===================
// a lantern fox that roams around the player and fetches nearby loot
const PET_NAME = '灯り狐';
function updatePet(dt) {
  const pet = G.pet, p = G.player;
  if (!pet || p.dead) return;
  const dp = dist(pet.x, pet.y, p.x, p.y);
  if (dp > 650) {
    burst(pet.x, pet.y, 12, '#ffd36a', 120, true);
    pet.x = p.x; pet.y = p.y; pet.target = null;
    burst(pet.x, pet.y, 12, '#ffd36a', 120, true);
  }
  if (pet.target && pet.target.dead) pet.target = null;

  pet.scanT -= dt;
  if (!pet.target && pet.scanT <= 0) {
    pet.scanT = 0.3;
    const bagFull = p.bag.length >= BAG_SIZE;
    let best = null, bd = Infinity;
    for (const g of [...G.golds, ...G.ground.filter(g => !isHidden(g.item) && (!bagFull || willAutoSell(g.item)))]) {
      if (pet.ignore.has(g) || dist2(g.x, g.y, p.x, p.y) > (380 * (1 + apVal('fox') / 100)) ** 2) continue;
      const d = dist2(g.x, g.y, pet.x, pet.y) * (g.item ? 1 : 0.6);
      if (d < bd && G.map.los(pet.x, pet.y, g.x, g.y)) { bd = d; best = g; }
    }
    pet.target = best;
    pet.stuckT = 0;
  }

  let tx, ty, sp;
  if (pet.target) { tx = pet.target.x; ty = pet.target.y; sp = 330; }
  else {
    pet.wanderT -= dt;
    if (pet.wanderT <= 0 || !pet.home) {
      pet.wanderT = rand(1.2, 2.6);
      const a = rand(0, TAU), d = rand(40, 110);
      pet.home = { dx: Math.cos(a) * d, dy: Math.sin(a) * d };
    }
    tx = p.x + pet.home.dx; ty = p.y + pet.home.dy;
    sp = dp > 200 ? 330 : 140;
  }
  const dx = tx - pet.x, dy = ty - pet.y, d = Math.hypot(dx, dy);
  if (d > 4) {
    const ox = pet.x, oy = pet.y, s = Math.min(d, sp * dt);
    moveCircle(pet, dx / d * s, dy / d * s);
    pet.face = Math.atan2(dy, dx); pet.walkT += dt;
    const moved = Math.abs(pet.x - ox) + Math.abs(pet.y - oy);
    pet.stuckT = moved < s * 0.3 ? pet.stuckT + dt : 0;
    if (pet.stuckT > 1) { if (pet.target) pet.ignore.add(pet.target); pet.target = null; pet.home = null; pet.stuckT = 0; }
  }

  const g = pet.target;
  if (g && dist2(g.x, g.y, pet.x, pet.y) < 16 * 16) {
    if (g.item) {
      if (!pickupItem(g.item, pet.x, pet.y, true)) { pet.target = null; return; }
    } else p.gold += g.amt;
    g.dead = true; pet.target = null;
    burst(pet.x, pet.y, 8, '#ffe8a0', 90, true);
  }
}

function spawnPack(c, packId, n, pool) {
  const main = weighted(pool).k;
  if (Math.random() < (0.13 + G.floor * 0.01) * G.modFx.elite) makeEnemy(main, c.x, c.y, packId, pick(ELITE_AFFIXES));
  for (let i = 0; i < n; i++) {
    const type = Math.random() < 0.7 ? main : weighted(pool).k;
    let x = c.x + rand(-60, 60), y = c.y + rand(-60, 60);
    if (circleHits(G.map, x, y, ENEMY_TYPES[type].r)) { x = c.x; y = c.y; }
    makeEnemy(type, x, y, packId);
  }
}

// =================== world update ===================
function updateWorld(dt) {
  const p = G.player;
  G.time += dt;
  updatePlayer(dt);
  updatePet(dt);

  G.flowT -= dt;
  if (G.flowT <= 0) { G.flowT = 0.25; G.map.computeFlow(p.x, p.y); }
  for (const e of G.enemies) if (!e.dead && dist2(e.x, e.y, p.x, p.y) < 1400 * 1400) updateEnemy(e, dt);
  separateEnemies();
  G.enemies = G.enemies.filter(e => !e.dead);

  // player projectiles
  for (const pr of G.projs) {
    pr.t += dt; pr.x += pr.vx * dt; pr.y += pr.vy * dt;
    if (pr.kind === 'fireball') {
      G.particles.push({ x: pr.x, y: pr.y, vx: rand(-30, 30), vy: rand(-30, 30), t: 0, max: 0.3, size: rand(3, 6), color: pick(['#ff9a30', '#ffcc50', '#ff5a20']), glow: true });
      let boom = pr.t > pr.max || G.map.solidAt(pr.x, pr.y);
      if (!boom) for (const e of G.enemies) if (!e.dead && dist2(pr.x, pr.y, e.x, e.y) < (e.r + pr.r) ** 2) { boom = true; break; }
      if (boom) {
        pr.dead = true;
        explosionFx(pr.x, pr.y, 70, '255,140,50');
        for (const e of enemiesInRadius(pr.x, pr.y, 70)) hitEnemy(e, rollDamage(1.5, 'fire', true, 'fireball'));
      }
    } else if (pr.kind === 'wave') {
      if (pr.t > pr.max || G.map.solidAt(pr.x, pr.y)) { pr.dead = true; continue; }
      for (const e of G.enemies) {
        if (e.dead || pr.hit.has(e) || dist2(pr.x, pr.y, e.x, e.y) > (e.r + pr.r) ** 2) continue;
        pr.hit.add(e); hitEnemy(e, rollDamage(0.7, 'phys', false, 'slash'));
      }
    } else if (pr.kind === 'spear') {
      if (Math.random() < 0.7) G.particles.push({ x: pr.x, y: pr.y, vx: rand(-20, 20), vy: rand(-20, 20), t: 0, max: 0.35, size: rand(2, 4), color: pick(['#bff4ff', '#7fd4ff']), glow: true });
      if (pr.t > pr.max || G.map.solidAt(pr.x, pr.y)) { pr.dead = true; burst(pr.x, pr.y, 10, '#bff4ff', 160, true); continue; }
      for (const e of G.enemies) {
        if (e.dead || pr.hit.has(e) || dist2(pr.x, pr.y, e.x, e.y) > (e.r + pr.r) ** 2) continue;
        pr.hit.add(e); hitEnemy(e, rollDamage(1.1, 'cold', true, 'iceSpear'), 0.6);
      }
    }
  }
  G.projs = G.projs.filter(pr => !pr.dead);

  // enemy projectiles
  for (const pr of G.eprojs) {
    pr.t += dt; pr.x += pr.vx * dt; pr.y += pr.vy * dt;
    if (pr.t > pr.max || G.map.solidAt(pr.x, pr.y)) { pr.dead = true; continue; }
    if (!p.dead && dist2(pr.x, pr.y, p.x, p.y) < (pr.r + p.r) ** 2 && p.invuln <= 0) {
      pr.dead = true; damagePlayer(pr.dmg);
      if (pr.chill) p.chill = 2;
    }
  }
  G.eprojs = G.eprojs.filter(pr => !pr.dead);

  for (const t of G.tele) { t.t += dt; if (t.t >= t.max) { t.dead = true; t.onDone(); } }
  G.tele = G.tele.filter(t => !t.dead);

  for (const h of G.hazards) {
    h.t += dt; h.tick -= dt;
    if (Math.random() < 0.6) G.particles.push({ x: h.x + rand(-h.r, h.r) * 0.8, y: h.y + rand(-h.r, h.r) * 0.8, vx: 0, vy: -rand(30, 80), t: 0, max: 0.6, size: rand(3, 6), color: pick(['#ff6a20', '#ffb040']), glow: true });
    if (h.tick > 0) continue;
    h.tick = 0.5;
    if (h.hostile) { if (dist(h.x, h.y, p.x, p.y) < h.r + p.r * 0.5) damagePlayer(h.dmg); }
    else for (const e of enemiesInRadius(h.x, h.y, h.r)) hitEnemy(e, rollDamage(0.35, 'fire', true, 'meteor'));
  }
  G.hazards = G.hazards.filter(h => h.t < h.max);

  for (const st of G.storms) {
    st.t += dt; st.tick -= dt;
    if (st.tick > 0) continue;
    st.tick = 0.22;
    const near = enemiesInRadius(st.x, st.y, st.r);
    const tgt = near.length ? pick(near) : null;
    const x = tgt ? tgt.x : st.x + rand(-st.r, st.r) * 0.8, y = tgt ? tgt.y : st.y + rand(-st.r, st.r) * 0.8;
    G.effects.push({ kind: 'bolt', x0: x + rand(-40, 40), y0: y - 340, x1: x, y1: y, t: 0, max: 0.18 });
    burst(x, y, 8, '#d9c2ff', 160, true);
    if (tgt) hitEnemy(tgt, rollDamage(0.9, 'light', true, 'storm'));
  }
  G.storms = G.storms.filter(s => s.t < s.max);

  for (const pa of G.particles) {
    pa.t += dt; pa.x += pa.vx * dt; pa.y += pa.vy * dt;
    if (pa.drag) { const k = Math.max(0, 1 - pa.drag * dt); pa.vx *= k; pa.vy *= k; }
  }
  G.particles = G.particles.filter(pa => pa.t < pa.max);
  if (G.particles.length > 1500) G.particles.splice(0, G.particles.length - 1500);
  for (const fx of G.effects) fx.t += dt;
  G.effects = G.effects.filter(fx => fx.t < fx.max);
  for (const tx of G.texts) { tx.t += dt; tx.y += tx.vy * dt; tx.vy *= 0.96; }
  G.texts = G.texts.filter(tx => tx.t < 0.9);

  // pickups
  if (!p.dead) {
    for (const g of G.ground) {
      g.t += dt;
      if (!isHidden(g.item) && dist2(g.x, g.y, p.x, p.y) < 34 * 34) {
        if (pickupItem(g.item, g.x, g.y)) g.dead = true;
        else if (!G.fullT || G.time - G.fullT > 2) { G.fullT = G.time; showMsg('インベントリが一杯です（I）', '#ff8080'); }
      }
    }
    G.ground = G.ground.filter(g => !g.dead);
    for (const g of G.golds) {
      const d2 = dist2(g.x, g.y, p.x, p.y);
      if (d2 < 110 * 110) { const d = Math.sqrt(d2) || 1; g.x += (p.x - g.x) / d * 400 * dt; g.y += (p.y - g.y) / d * 400 * dt; }
      if (d2 < 20 * 20) { g.dead = true; p.gold += g.amt; }
    }
    G.golds = G.golds.filter(g => !g.dead);
  }

  if (G.portal) {
    G.portal.t += dt;
    if (!p.dead && dist2(G.portal.x, G.portal.y, p.x, p.y) < 30 * 30) { collectNearbyLoot(700); completeMap(); return; }
  }

  G.cam.x += (p.x - G.cam.x) * Math.min(1, dt * 8);
  G.cam.y += (p.y - G.cam.y) * Math.min(1, dt * 8);
  G.shake = Math.max(0, G.shake - dt * 30);
}

// =================== save ===================
const SAVE_KEY = 'emberfall-save-v1';
function saveGame() {
  const p = G.player;
  try {
    localStorage.setItem(SAVE_KEY, JSON.stringify({
      floor: G.floor, level: p.level, xp: p.xp, talentPts: p.talentPts, talents: p.talents,
      equip: p.equip, bag: p.bag, gold: p.gold, potions: p.potions, slots: p.slots, shop: G.shop, filter: p.filter, atlas: G.atlas,
    }));
  } catch (e) { /* storage unavailable */ }
}
function loadSave() {
  try { const s = localStorage.getItem(SAVE_KEY); return s ? JSON.parse(s) : null; } catch (e) { return null; }
}
function applySave(d) {
  const p = new Player();
  Object.assign(p, { level: d.level, xp: d.xp, talentPts: d.talentPts, equip: d.equip, bag: d.bag, gold: d.gold, potions: d.potions });
  p.talents = { ...p.talents, ...d.talents };
  if (Array.isArray(d.slots) && d.slots.length === SKILL_SLOTS.length && d.slots.every(id => SKILLS[id])) p.slots = d.slots;
  if (d.filter && Array.isArray(d.filter.rarity)) p.filter = { rarity: d.filter.rarity, slots: { ...defaultFilter().slots, ...d.filter.slots } };
  else if (Array.isArray(d.autoSell)) p.filter.rarity = d.autoSell.map(s => (s ? 'sell' : 'pick')); // older auto-sell setting
  G.player = p; G.floor = d.floor; G.shop = d.shop || null;
  if (d.atlas) G.atlas = { ...newAtlas(), ...d.atlas };
  else { // saves from before the atlas: count earlier depths as cleared
    G.atlas = newAtlas();
    G.atlas.cleared = ATLAS_NODES.filter(n => !n.endless && n.level < d.floor).map(n => n.id);
  }
  p.recalc(true);
}
