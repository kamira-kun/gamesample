'use strict';
// ---- expedition atlas: pick a map node, then enter it ----
const ATLAS_NODES = [
  { id: 'ash', name: '灰の入口', theme: 0, level: 1, x: 0.07, y: 0.55, links: ['bone', 'wail'], desc: '深淵へ続く最初の階段。灯火を掲げて進め。' },
  { id: 'bone', name: '骨の回廊', theme: 0, level: 2, x: 0.2, y: 0.3, links: ['ember'], desc: '無数の骨が積み上げられた細い通路。' },
  { id: 'wail', name: '嘆きの納骨堂', theme: 0, level: 3, x: 0.24, y: 0.75, links: ['ember', 'obsidian'], desc: '夜な夜な泣き声が響くという古い納骨堂。' },
  { id: 'ember', name: '燻る坑道', theme: 1, level: 4, x: 0.38, y: 0.42, links: ['forge'], desc: '地熱で焼けた岩が赤く光る廃坑。' },
  { id: 'obsidian', name: '黒曜の裂け目', theme: 1, level: 5, x: 0.43, y: 0.8, links: ['forge', 'frost'], desc: '溶岩が冷えて固まった鋭い岩の谷。' },
  { id: 'forge', name: '溶鉄の炉心', theme: 1, level: 6, x: 0.55, y: 0.52, links: ['cathedral'], desc: '巨像が生まれたと伝わる灼熱の炉。' },
  { id: 'frost', name: '凍てつく参道', theme: 2, level: 7, x: 0.62, y: 0.82, links: ['cathedral', 'grave'], desc: '氷に閉ざされた巡礼者の道。' },
  { id: 'cathedral', name: '霜の大聖堂', theme: 2, level: 8, x: 0.72, y: 0.35, links: ['abyss'], desc: '魔女が祈りを捧げる凍った聖堂。' },
  { id: 'grave', name: '氷霧の墓標', theme: 2, level: 9, x: 0.8, y: 0.72, links: ['abyss'], desc: '霧の中に墓標が並ぶ静寂の丘。' },
  { id: 'abyss', name: '残り火の深淵', theme: -1, level: 10, x: 0.92, y: 0.5, links: [], endless: true,
    desc: '終わりなき深淵。踏破するたびに、さらに深く強大になる。' },
];
const NODE_BY_ID = Object.fromEntries(ATLAS_NODES.map(n => [n.id, n]));
const THEME_COLORS = ['#c9b89a', '#ff7a3a', '#7fd4ff', '#b48cff'];

const MAP_MODS = [
  { k: 'life', name: '敵のライフ +40%', life: 1.4 },
  { k: 'dmg', name: '敵のダメージ +30%', dmg: 1.3 },
  { k: 'swarm', name: '敵の数 +40%', swarm: 1.4 },
  { k: 'fast', name: '敵の移動速度 +25%', speed: 1.25 },
  { k: 'elite', name: 'エリートの出現率 2倍', elite: 2 },
];
const MOD_BY_KEY = Object.fromEntries(MAP_MODS.map(m => [m.k, m]));

// ---- atlas passives: points come from first clears and each Ember Abyss clear ----
const ATLAS_PASSIVES = [
  { branch: '財宝', color: '#ffcf3a', nodes: [
    { id: 'gold', name: '黄金の嗅覚', max: 3, per: 10, fmt: 'カレンシー獲得量 +{v}%' },
    { id: 'find', name: '目利き', max: 3, per: 8, fmt: 'アイテムレア度 +{v}%' },
    { id: 'plenty', name: '豊穣', max: 3, per: 6, fmt: 'アイテム数量 +{v}%' },
    { id: 'relic', name: '秘宝の導き', max: 2, per: 10, fmt: 'ボスのレジェンド確定ドロップ率 +{v}%' },
  ] },
  { branch: '征服', color: '#ff7a5a', nodes: [
    { id: 'horde', name: '群れの呼び声', max: 3, per: 8, fmt: 'マップの敵の数 +{v}%' },
    { id: 'hunt', name: '精鋭狩り', max: 3, per: 15, fmt: 'エリートの出現率 +{v}%' },
    { id: 'train', name: '修練', max: 3, per: 8, fmt: '獲得経験値 +{v}%' },
    { id: 'prowess', name: '強者の証', max: 2, per: 10, fmt: 'マップ効果1つにつきアイテムレア度 +{v}%' },
  ] },
  { branch: '探索', color: '#7fd4ff', nodes: [
    { id: 'flask', name: '携行袋', max: 2, per: 1, fmt: '回復薬の最大所持数 +{v}' },
    { id: 'ward', name: '灯火の加護', max: 3, per: 2, fmt: 'ライフ回復 +{v}/秒' },
    { id: 'haggle', name: '商人の縁', max: 3, per: 8, fmt: 'ショップの購入価格 -{v}%' },
    { id: 'fox', name: '狐の嗅覚', max: 2, per: 25, fmt: 'ペットの回収範囲 +{v}%' },
  ] },
];
const PASSIVE_BY_ID = Object.fromEntries(ATLAS_PASSIVES.flatMap(b => b.nodes.map((n, i) => [n.id, { ...n, branch: b, tier: i }])));
const apRank = id => (G.atlas && G.atlas.passives[id]) || 0;
const apVal = id => apRank(id) * PASSIVE_BY_ID[id].per;
const apTotal = () => G.atlas.cleared.length + G.atlas.abyss;
const apSpent = () => Object.values(G.atlas.passives).reduce((a, b) => a + b, 0);
const apFree = () => apTotal() - apSpent();
const apUnlocked = id => { const n = PASSIVE_BY_ID[id]; return n.tier === 0 || apRank(n.branch.nodes[n.tier - 1].id) > 0; };
const apResetPrice = () => apSpent() * 30;
const maxPotions = () => 5 + apVal('flask');

function newAtlas() { return { cleared: [], abyss: 0, mods: {}, sel: 'ash', passives: {} }; }
const nodeLevel = n => (n.endless ? n.level + G.atlas.abyss : n.level);
const nodeTheme = n => (n.endless ? G.atlas.abyss % THEMES.length : n.theme);
const isCleared = n => G.atlas.cleared.includes(n.id);
const isUnlocked = n => n.id === 'ash' || isCleared(n) || ATLAS_NODES.some(o => isCleared(o) && o.links.includes(n.id));

function rollMods(n) {
  const L = nodeLevel(n);
  const count = n.endless ? randi(2, 3) : L >= 6 ? randi(1, 2) : L >= 3 ? randi(0, 1) : 0;
  const pool = MAP_MODS.map(m => m.k), out = [];
  while (out.length < count) out.push(...pool.splice(Math.floor(Math.random() * pool.length), 1));
  return out;
}
function nodeMods(n) {
  if (!G.atlas.mods[n.id]) G.atlas.mods[n.id] = rollMods(n);
  return G.atlas.mods[n.id];
}
function modEffects(keys) {
  const fx = { life: 1, dmg: 1, speed: 1, swarm: 1, elite: 1, rarity: 0, quantity: 1, gold: 1, xp: 1, legend: 0 };
  for (const k of keys) {
    const m = MOD_BY_KEY[k];
    for (const f of ['life', 'dmg', 'speed', 'swarm', 'elite']) if (m[f]) fx[f] *= m[f];
    fx.rarity += 0.3; fx.quantity += 0.15;
  }
  return fx;
}
// map modifiers plus atlas passive bonuses for a run
function mapEffects(keys) {
  const fx = modEffects(keys);
  fx.gold += apVal('gold') / 100;
  fx.rarity += apVal('find') / 100 + keys.length * apVal('prowess') / 100;
  fx.quantity += apVal('plenty') / 100;
  fx.legend = apVal('relic') / 100;
  fx.swarm *= 1 + apVal('horde') / 100;
  fx.elite *= 1 + apVal('hunt') / 100;
  fx.xp += apVal('train') / 100;
  return fx;
}

// ---- flow ----
function enterMap(id) {
  const n = NODE_BY_ID[id];
  if (!isUnlocked(n)) return;
  G.area = n;
  G.floor = nodeLevel(n);
  G.runMods = [...nodeMods(n)];
  G.modFx = mapEffects(G.runMods);
  if (UI.open) UI.toggle(UI.open);
  Atlas.hide();
  G.state = 'play';
  spawnFloor();
  saveGame();
}

function completeMap() {
  const n = G.area, wasCleared = isCleared(n);
  if (!wasCleared) G.atlas.cleared.push(n.id);
  const newly = n.links.map(id => NODE_BY_ID[id]).filter(o => !isCleared(o));
  if (n.endless) G.atlas.abyss++;
  delete G.atlas.mods[n.id];
  Atlas.show();
  showMsg(`${n.name} を踏破した！`, '#ffd36a');
  if (newly.length) showMsg(`新たな地点が開放：${newly.map(o => o.name).join('、')}`, '#e8d8b0');
  if (n.endless) showMsg(`残り火の深淵が Lv ${nodeLevel(n)} に深まった`, '#b48cff');
  const gained = (wasCleared ? 0 : 1) + (n.endless ? 1 : 0);
  if (gained) showMsg(`アトラスパッシブポイント +${gained}（P）`, '#8fd18f');
}

function abandonMap() {
  Atlas.show();
  showMsg('拠点に帰還した', '#e8d8b0');
}

// ---- screen ----
const Atlas = {
  init() {
    this.canvas = $('atlasCanvas');
    this.ctx = this.canvas.getContext('2d');
    this.canvas.addEventListener('click', e => this.click(e));
    this.canvas.addEventListener('mousemove', e => this.hover(e));
    document.querySelectorAll('#atlas [data-open]').forEach(b => b.addEventListener('click', () => UI.toggle(b.dataset.open)));
    $('atlasTitleBtn').addEventListener('click', () => { saveGame(); location.reload(); });
    addEventListener('resize', () => this.resize());
  },
  show() {
    G.state = 'atlas';
    Object.assign(G, { enemies: [], projs: [], eprojs: [], tele: [], hazards: [], storms: [], minions: [], totems: [], ground: [], drops: [], portal: null, boss: null, merchant: null, pet: null });
    if (UI.open) UI.toggle(UI.open);
    UI.setBoss(null);
    $('death').classList.add('hidden');
    $('atlas').classList.remove('hidden');
    document.body.classList.add('in-atlas');
    const p = G.player;
    p.dead = false; p.recalc(true);
    this.resize();
    this.renderDetail();
    saveGame();
  },
  hide() {
    $('atlas').classList.add('hidden');
    document.body.classList.remove('in-atlas');
  },
  resize() {
    const c = this.canvas, r = c.getBoundingClientRect(), dpr = Math.min(devicePixelRatio || 1, 2);
    if (!r.width) return;
    c.width = r.width * dpr; c.height = r.height * dpr;
    this.dpr = dpr; this.w = r.width; this.h = r.height;
  },
  pos(n) { return { x: 50 + n.x * (this.w - 100), y: 40 + n.y * (this.h - 90) }; },
  nodeAt(e) {
    const r = this.canvas.getBoundingClientRect(), mx = e.clientX - r.left, my = e.clientY - r.top;
    return ATLAS_NODES.find(n => { const q = this.pos(n); return dist2(q.x, q.y, mx, my) < 28 * 28; });
  },
  click(e) {
    const n = this.nodeAt(e);
    if (!n) return;
    G.atlas.sel = n.id;
    this.renderDetail();
  },
  hover(e) { this.canvas.style.cursor = this.nodeAt(e) ? 'pointer' : 'default'; },

  draw() {
    const c = this.ctx, W = this.w, H = this.h, t = performance.now() / 1000;
    if (!W) return;
    c.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    const bg = c.createRadialGradient(W * 0.5, H * 0.5, 50, W * 0.5, H * 0.5, Math.max(W, H) * 0.7);
    bg.addColorStop(0, '#2a1c12'); bg.addColorStop(1, '#0a0705');
    c.fillStyle = bg; c.fillRect(0, 0, W, H);
    // faint glow under each region's nodes
    for (const n of ATLAS_NODES) {
      const q = this.pos(n), col = THEME_COLORS[n.endless ? 3 : n.theme];
      const g = c.createRadialGradient(q.x, q.y, 0, q.x, q.y, 130);
      g.addColorStop(0, col + '12'); g.addColorStop(1, col + '00');
      c.fillStyle = g; c.fillRect(q.x - 130, q.y - 130, 260, 260);
    }
    // links
    for (const n of ATLAS_NODES) for (const id of n.links) {
      const o = NODE_BY_ID[id], a = this.pos(n), b = this.pos(o);
      const open = isCleared(n);
      c.strokeStyle = open ? 'rgba(255,200,110,0.7)' : 'rgba(120,100,80,0.35)';
      c.lineWidth = open ? 3 : 2;
      c.setLineDash(open ? [] : [6, 6]);
      c.beginPath(); c.moveTo(a.x, a.y);
      c.quadraticCurveTo((a.x + b.x) / 2, (a.y + b.y) / 2 - 20, b.x, b.y); c.stroke();
    }
    c.setLineDash([]);
    // nodes
    c.textAlign = 'center';
    for (const n of ATLAS_NODES) {
      const q = this.pos(n), unlocked = isUnlocked(n), cleared = isCleared(n), sel = G.atlas.sel === n.id;
      const col = THEME_COLORS[n.endless ? 3 : n.theme];
      if (unlocked) {
        const gl = c.createRadialGradient(q.x, q.y, 4, q.x, q.y, 44);
        gl.addColorStop(0, col + 'aa'); gl.addColorStop(1, col + '00');
        c.fillStyle = gl; c.beginPath(); c.arc(q.x, q.y, 44, 0, TAU); c.fill();
      }
      if (sel) {
        c.strokeStyle = `rgba(255,220,140,${0.6 + Math.sin(t * 4) * 0.3})`; c.lineWidth = 2;
        c.beginPath(); c.arc(q.x, q.y, 27 + Math.sin(t * 4) * 2, 0, TAU); c.stroke();
      }
      c.fillStyle = unlocked ? '#1a120c' : '#0c0a08';
      c.strokeStyle = unlocked ? col : '#3a3024'; c.lineWidth = 3;
      c.beginPath();
      if (n.endless) { for (let i = 0; i < 8; i++) { const a = i / 8 * TAU + t * 0.3; c.lineTo(q.x + Math.cos(a) * (i % 2 ? 15 : 22), q.y + Math.sin(a) * (i % 2 ? 15 : 22)); } c.closePath(); }
      else c.arc(q.x, q.y, 18, 0, TAU);
      c.fill(); c.stroke();
      c.font = 'bold 15px sans-serif';
      c.fillStyle = unlocked ? col : '#4a4032';
      c.fillText(cleared ? '✓' : unlocked ? String(nodeLevel(n)) : '—', q.x, q.y + 5);
      c.font = '13px sans-serif';
      c.fillStyle = unlocked ? '#f0dcb4' : '#5a4e40';
      c.fillText(n.name, q.x, q.y + 40);
      c.font = '11px sans-serif'; c.fillStyle = unlocked ? '#a89878' : '#4a4032';
      c.fillText(`Lv ${nodeLevel(n)}`, q.x, q.y + 55);
    }
  },

  renderDetail() {
    const n = NODE_BY_ID[G.atlas.sel] || ATLAS_NODES[0], p = G.player;
    const unlocked = isUnlocked(n), ti = nodeTheme(n);
    const mods = unlocked ? nodeMods(n) : [];
    const fx = mapEffects(mods), boss = ENEMY_TYPES[BOSS_ROTATION[ti].type];
    const status = isCleared(n) ? '<span style="color:#8fd18f">踏破済み</span>' : unlocked ? '<span style="color:#ffd36a">未踏</span>' : '<span style="color:#8a5040">未開放</span>';
    $('atlasDetail').innerHTML = `
      <div class="ad-name" style="color:${THEME_COLORS[n.endless ? 3 : n.theme]}">${n.name}</div>
      <div class="ad-sub">エリアレベル ${nodeLevel(n)}　・　${status}</div>
      <p class="ad-desc">${n.desc}</p>
      <div class="ad-row"><span>地形</span><b>${THEMES[ti].name}</b></div>
      <div class="ad-row"><span>ボス</span><b style="color:#ff7a5a">${boss.name}</b></div>
      <h4>マップ効果</h4>
      ${mods.length ? mods.map(k => `<div class="ad-mod">◆ ${MOD_BY_KEY[k].name}</div>`).join('') : '<div class="ad-none">なし</div>'}
      ${fx.rarity > 0 || fx.quantity > 1 ? `<div class="ad-bonus">アイテムレア度 +${Math.round(fx.rarity * 100)}%　アイテム数量 +${Math.round((fx.quantity - 1) * 100)}%</div>` : ''}
      <button class="btn ad-go" id="atlasGo"${unlocked ? '' : ' disabled'}>${unlocked ? '出撃する' : '隣接する地点を踏破すると開放'}</button>
      ${unlocked && nodeLevel(n) >= 3 ? `<button class="sbtn ad-reroll" id="atlasReroll"${p.cur.compass < 1 ? ' disabled' : ''}>マップ効果を再抽選（<span style="color:${CUR_BY_KEY.compass.color}">✧</span> 羅針の欠片 1／所持 ${p.cur.compass}）</button>` : ''}`;
    $('atlasInfo').innerHTML = `Lv ${p.level}　<span class="gold">◆ ${p.cur.ember}</span>　<span style="color:${CUR_BY_KEY.compass.color}">✧ ${p.cur.compass}</span>　踏破 ${G.atlas.cleared.length}/${ATLAS_NODES.length}`;
    $('apBadge').textContent = apFree() > 0 ? apFree() : '';
    const go = $('atlasGo');
    if (go && unlocked) go.addEventListener('click', () => enterMap(n.id));
    const rr = $('atlasReroll');
    if (rr) rr.addEventListener('click', () => {
      if (p.cur.compass < 1) return;
      p.cur.compass--; G.atlas.mods[n.id] = rollMods(n);
      this.renderDetail();
    });
  },
};
