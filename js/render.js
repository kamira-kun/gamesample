'use strict';
// ---- isometric projection: the world stays a flat 2D grid, only drawing is projected ----
const ISO = 0.75;      // screen px per world px along each diagonal
const PITCH = 0.8;     // vertical squash = sin(camera elevation); 0.5 is classic 2:1 iso, 1 is straight down
const WALL_ISO = 26;   // wall height in screen px (shorter when seen from higher up)
const isoX = (x, y) => (x - y) * ISO;
const isoY = (x, y) => (x + y) * ISO * PITCH;
// screen-space offset -> world-space offset
const screenToWorld = (dx, dy) => ({ x: (dx / ISO + dy / (ISO * PITCH)) / 2, y: (dy / (ISO * PITCH) - dx / ISO) / 2 });
// direction of a world-space angle as seen on screen
const isoAngle = a => Math.atan2((Math.cos(a) + Math.sin(a)) * PITCH, Math.cos(a) - Math.sin(a));
// world -> screen using the camera (no shake); used for mouse picking
function worldToScreen(x, y) {
  return { x: isoX(x, y) - isoX(G.cam.x, G.cam.y) + G.vw / 2, y: isoY(x, y) - isoY(G.cam.x, G.cam.y) + G.vh / 2 };
}

const R = {
  offX: 0, offY: 0,
  init() {
    this.canvas = document.getElementById('game');
    this.ctx = this.canvas.getContext('2d');
    this.light = document.createElement('canvas');
    this.lctx = this.light.getContext('2d');
    this.mini = document.getElementById('minimap');
    this.mctx = this.mini.getContext('2d');
    this.miniT = 0;
    addEventListener('resize', () => this.resize());
    this.resize();
  },
  resize() {
    this.dpr = Math.min(devicePixelRatio || 1, 1.5);
    G.vw = innerWidth; G.vh = innerHeight;
    for (const c of [this.canvas, this.light]) { c.width = G.vw * this.dpr; c.height = G.vh * this.dpr; }
    this.canvas.style.width = G.vw + 'px'; this.canvas.style.height = G.vh + 'px';
  },
  // draw in world coordinates on the ground plane
  ground(c) { const d = this.dpr; c.setTransform(d * ISO, d * ISO * PITCH, -d * ISO, d * ISO * PITCH, d * this.offX, d * this.offY); },
  // draw in plain screen pixels
  screen(c) { c.setTransform(this.dpr, 0, 0, this.dpr, 0, 0); },
  S(x, y) { return { x: isoX(x, y) + this.offX, y: isoY(x, y) + this.offY }; },
};

function tileColor(base, n, k) {
  const v = (n % 17) - 8;
  return `rgb(${base[0] + v * k},${base[1] + v * k},${base[2] + v * k})`;
}

function render(dt) {
  const ctx = R.ctx, W = G.vw, H = G.vh, th = G.theme, p = G.player, m = G.map;
  R.offX = Math.round(W / 2 - isoX(G.cam.x, G.cam.y) + rand(-G.shake, G.shake));
  R.offY = Math.round(H / 2 - isoY(G.cam.x, G.cam.y) + rand(-G.shake, G.shake));
  R.screen(ctx);
  ctx.fillStyle = '#040306';
  ctx.fillRect(0, 0, W, H);

  // visible tile range: invert the screen corners
  let wx0 = Infinity, wy0 = Infinity, wx1 = -Infinity, wy1 = -Infinity;
  for (const [sx, sy] of [[-80, -80], [W + 80, -80], [-80, H + 120], [W + 80, H + 120]]) {
    const w = screenToWorld(sx - R.offX, sy - R.offY);
    wx0 = Math.min(wx0, w.x); wy0 = Math.min(wy0, w.y); wx1 = Math.max(wx1, w.x); wy1 = Math.max(wy1, w.y);
  }
  const tx0 = Math.max(0, Math.floor(wx0 / T)), ty0 = Math.max(0, Math.floor(wy0 / T));
  const tx1 = Math.min(m.w - 1, Math.ceil(wx1 / T)), ty1 = Math.min(m.h - 1, Math.ceil(wy1 / T));
  const onScreen = (sx, sy, pad = 60) => sx > -pad && sx < W + pad && sy > -pad && sy < H + pad * 2;

  // ---- ground layer ----
  R.ground(ctx);
  for (let ty = ty0; ty <= ty1; ty++) for (let tx = tx0; tx <= tx1; tx++) {
    if (m.isWall(tx, ty)) continue;
    const c = R.S(tx * T + T / 2, ty * T + T / 2);
    if (!onScreen(c.x, c.y)) continue;
    const n = m.noise[m.idx(tx, ty)];
    ctx.fillStyle = tileColor(th.floor, n, 0.8);
    ctx.fillRect(tx * T, ty * T, T + 0.6, T + 0.6);
    ctx.fillStyle = 'rgba(0,0,0,0.18)';
    ctx.fillRect(tx * T, ty * T + T - 2, T, 2);
    ctx.fillRect(tx * T + T - 2, ty * T, 2, T);
    if (n < 18) { // cracks
      ctx.strokeStyle = 'rgba(0,0,0,0.35)'; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.moveTo(tx * T + 6, ty * T + 10 + n); ctx.lineTo(tx * T + 20, ty * T + 18); ctx.lineTo(tx * T + 32, ty * T + 12 + n / 2); ctx.stroke();
    } else if (n > 246) { // bones / rubble
      ctx.fillStyle = 'rgba(200,190,170,0.35)';
      ctx.fillRect(tx * T + 12, ty * T + 20, 14, 3); ctx.fillRect(tx * T + 18, ty * T + 14, 3, 12);
    }
  }
  for (const pa of G.particles) if (pa.decal) {
    ctx.globalAlpha = Math.min(1, (pa.max - pa.t) / 1.5);
    ctx.fillStyle = pa.color; ctx.beginPath(); ctx.arc(pa.x, pa.y, pa.size, 0, TAU); ctx.fill();
  }
  ctx.globalAlpha = 1;
  for (const h of G.hazards) {
    const a = Math.min(1, (h.max - h.t) / 0.5);
    const g = ctx.createRadialGradient(h.x, h.y, 0, h.x, h.y, h.r);
    g.addColorStop(0, h.hostile ? `rgba(255,40,10,${0.55 * a})` : `rgba(255,90,20,${0.45 * a})`); g.addColorStop(1, 'rgba(120,20,0,0)');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(h.x, h.y, h.r, 0, TAU); ctx.fill();
    if (h.hostile) { ctx.strokeStyle = `rgba(255,60,30,${0.5 * a})`; ctx.lineWidth = 1.5; ctx.stroke(); }
  }
  for (const t of G.tele) {
    const k = t.t / t.max, c = t.hostile ? '255,50,40' : '255,150,40';
    if (t.line) {
      ctx.save(); ctx.translate(t.x, t.y); ctx.rotate(t.line.a);
      ctx.fillStyle = `rgba(${c},0.14)`; ctx.fillRect(0, -t.line.w / 2, t.line.len, t.line.w);
      ctx.strokeStyle = `rgba(${c},0.8)`; ctx.lineWidth = 2; ctx.strokeRect(0, -t.line.w / 2, t.line.len, t.line.w);
      ctx.fillStyle = `rgba(${c},0.25)`; ctx.fillRect(0, -t.line.w / 2, t.line.len * k, t.line.w);
      ctx.restore();
      continue;
    }
    ctx.strokeStyle = `rgba(${c},0.8)`; ctx.lineWidth = 2;
    ctx.fillStyle = `rgba(${c},0.12)`;
    ctx.beginPath(); ctx.arc(t.x, t.y, t.r, 0, TAU); ctx.fill(); ctx.stroke();
    ctx.fillStyle = `rgba(${c},0.25)`;
    ctx.beginPath(); ctx.arc(t.x, t.y, t.r * k, 0, TAU); ctx.fill();
  }
  for (const st of G.storms) {
    const a = Math.min(1, (st.max - st.t) / 0.4, st.t / 0.2);
    ctx.fillStyle = `rgba(120,100,255,${0.1 * a})`;
    ctx.strokeStyle = `rgba(170,150,255,${0.45 * a})`; ctx.lineWidth = 2;
    ctx.setLineDash([8, 8]); ctx.lineDashOffset = -G.time * 30;
    ctx.beginPath(); ctx.arc(st.x, st.y, st.r, 0, TAU); ctx.fill(); ctx.stroke();
    ctx.setLineDash([]);
  }
  for (const g of G.ground) {
    ctx.fillStyle = RARITY[g.item.rarity].color;
    ctx.fillRect(g.x - 7, g.y - 7, 14, 14);
    ctx.strokeStyle = '#000'; ctx.lineWidth = 1.5; ctx.strokeRect(g.x - 7, g.y - 7, 14, 14);
  }
  for (const g of G.drops) {
    const c = CUR_BY_KEY[g.k], s = g.k === 'ember' ? 6 : 9;
    ctx.save(); ctx.translate(g.x, g.y); ctx.rotate(g.k === 'ember' ? 0 : G.time * 2);
    ctx.fillStyle = c.color; ctx.fillRect(-s / 2, -s / 2, s, s);
    ctx.strokeStyle = 'rgba(0,0,0,0.6)'; ctx.lineWidth = 1; ctx.strokeRect(-s / 2, -s / 2, s, s);
    ctx.restore();
  }

  // entities on screen, with shadows on the ground
  const ents = [...G.enemies, ...G.minions, ...G.totems, p];
  if (G.merchant) ents.push(G.merchant);
  if (G.device) ents.push(G.device);
  ents.push(...G.props);
  if (G.pet) ents.push(G.pet);
  const vis = ents.filter(e => { const s = R.S(e.x, e.y); return onScreen(s.x, s.y, 100); });
  ctx.fillStyle = 'rgba(0,0,0,0.4)';
  for (const e of vis) { ctx.beginPath(); ctx.arc(e.x, e.y, e.r * 1.05, 0, TAU); ctx.fill(); }

  // ---- upright layer: walls and entities sorted by depth (x + y) ----
  R.screen(ctx);
  if (G.portal) drawPortal(ctx, G.portal);
  for (const g of G.ground) if (g.item.rarity >= 2) {
    const s = R.S(g.x, g.y), col = RARITY[g.item.rarity].color;
    const gr = ctx.createLinearGradient(0, s.y - 90, 0, s.y);
    gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, col + '88');
    ctx.fillStyle = gr; ctx.fillRect(s.x - 3, s.y - 90, 6, 90);
  }
  const list = vis.map(e => ({ d: e.x + e.y, e }));
  for (let ty = ty0; ty <= ty1; ty++) for (let tx = tx0; tx <= tx1; tx++) {
    if (!m.isWall(tx, ty)) continue;
    if (m.isWall(tx, ty + 1) && m.isWall(tx + 1, ty) && m.isWall(tx, ty - 1) && m.isWall(tx - 1, ty) &&
      m.isWall(tx + 1, ty + 1) && m.isWall(tx - 1, ty - 1) && m.isWall(tx + 1, ty - 1) && m.isWall(tx - 1, ty + 1)) continue;
    list.push({ d: (tx + ty + 1) * T, wall: true, tx, ty });
  }
  list.sort((a, b) => a.d - b.d);
  const ps = R.S(p.x, p.y), pd = p.x + p.y;
  for (const it of list) {
    if (it.wall) { drawWall(ctx, m, th, it.tx, it.ty, ps, pd); continue; }
    const e = it.e, s = R.S(e.x, e.y);
    if (e === p) drawPlayer(ctx, p, s.x, s.y);
    else if (e.merchant) drawMerchant(ctx, e, s.x, s.y);
    else if (e.device) drawDevice(ctx, e, s.x, s.y);
    else if (e.brazier) drawBrazier(ctx, e, s.x, s.y);
    else if (e.pet) drawPet(ctx, e, s.x, s.y);
    else if (e.minion) drawMinion(ctx, e, s.x, s.y);
    else if (e.totem) drawTotem(ctx, e, s.x, s.y);
    else drawEnemy(ctx, e, s.x, s.y);
  }

  // ---- lighting: darkness with holes punched by light sources ----
  const L = R.lctx;
  L.setTransform(1, 0, 0, 1, 0, 0);
  L.globalCompositeOperation = 'source-over';
  L.fillStyle = `rgba(${th.dark},${th.darkA ?? 0.86})`;
  L.fillRect(0, 0, R.light.width, R.light.height);
  L.globalCompositeOperation = 'destination-out';
  R.ground(L);
  const flick = 1 + Math.sin(G.time * 13) * 0.015 + Math.sin(G.time * 7.3) * 0.02;
  const lights = [[p.x, p.y, 460 * flick, 1]];
  for (const pr of G.projs) lights.push([pr.x, pr.y, 120, 0.8]);
  for (const pr of G.eprojs) lights.push([pr.x, pr.y, 60, 0.5]);
  for (const h of G.hazards) lights.push([h.x, h.y, 180, 0.7]);
  for (const fx of G.effects) if (fx.kind === 'ring') lights.push([fx.x, fx.y, fx.r1 * 1.4, 0.8 * (1 - fx.t / fx.max)]);
  for (const t of G.tele) lights.push([t.x, t.y, (t.r || 60) * 1.2, 0.35]);
  if (G.portal) lights.push([G.portal.x, G.portal.y, 240, 0.9]);
  if (G.merchant) lights.push([G.merchant.x, G.merchant.y, 200, 0.85]);
  if (G.device) lights.push([G.device.x, G.device.y, 260, 0.9]);
  for (const b of G.props) lights.push([b.x, b.y, 230 * flick, 0.9]);
  if (G.pet) lights.push([G.pet.x, G.pet.y, 120, 0.6]);
  for (const t of G.totems) lights.push([t.x, t.y, 150, 0.7]);
  for (const st of G.storms) lights.push([st.x, st.y, st.r * 1.3, 0.5]);
  for (const g of G.ground) if (g.item.rarity >= 2) lights.push([g.x, g.y, 70, 0.4]);
  for (const g of G.drops) if (g.k !== 'ember') lights.push([g.x, g.y, 60, 0.4]);
  for (const [lx, ly, lr, li] of lights) {
    const s = R.S(lx, ly);
    if (!onScreen(s.x, s.y, lr)) continue;
    const g = L.createRadialGradient(lx, ly, 0, lx, ly, lr);
    g.addColorStop(0, `rgba(0,0,0,${li})`); g.addColorStop(0.5, `rgba(0,0,0,${li * 0.75})`); g.addColorStop(1, 'rgba(0,0,0,0)');
    L.fillStyle = g; L.fillRect(lx - lr, ly - lr, lr * 2, lr * 2);
  }
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.drawImage(R.light, 0, 0);
  R.screen(ctx);

  // warm torch tint around player
  const tg = ctx.createRadialGradient(ps.x, ps.y, 0, ps.x, ps.y, 380);
  tg.addColorStop(0, `rgba(${th.torch},0.10)`); tg.addColorStop(1, `rgba(${th.torch},0)`);
  ctx.fillStyle = tg; ctx.fillRect(0, 0, W, H);

  // ---- glow layer ----
  ctx.globalCompositeOperation = 'lighter';
  R.ground(ctx);
  for (const fx of G.effects) if (fx.kind !== 'bolt') drawEffect(ctx, fx);
  for (const pr of G.projs) if (pr.kind === 'wave') {
    ctx.strokeStyle = 'rgba(255,230,180,0.8)'; ctx.lineWidth = 6;
    ctx.beginPath(); ctx.arc(pr.x - Math.cos(pr.a) * 20, pr.y - Math.sin(pr.a) * 20, 26, pr.a - 0.9, pr.a + 0.9); ctx.stroke();
  }
  R.screen(ctx);
  for (const pa of G.particles) {
    if (pa.decal) continue;
    const a = 1 - pa.t / pa.max, s = R.S(pa.x, pa.y);
    ctx.globalAlpha = pa.glow ? a : a * 0.9;
    ctx.fillStyle = pa.color;
    if (!pa.glow) ctx.globalCompositeOperation = 'source-over';
    ctx.fillRect(s.x - pa.size / 2, s.y - (pa.z || 0) - 6 - pa.size / 2, pa.size, pa.size);
    if (!pa.glow) ctx.globalCompositeOperation = 'lighter';
  }
  ctx.globalAlpha = 1;
  for (const pr of G.projs) {
    const s = R.S(pr.x, pr.y);
    if (pr.kind === 'fireball') glowBall(ctx, s.x, s.y - 10, 16, '255,160,60');
    else if (pr.kind === 'spear') {
      const b = R.S(pr.x - Math.cos(pr.a) * 34, pr.y - Math.sin(pr.a) * 34), tip = R.S(pr.x + Math.cos(pr.a) * 6, pr.y + Math.sin(pr.a) * 6);
      ctx.lineCap = 'round';
      ctx.strokeStyle = 'rgba(120,210,255,0.5)'; ctx.lineWidth = 10;
      ctx.beginPath(); ctx.moveTo(b.x, b.y - 10); ctx.lineTo(s.x, s.y - 10); ctx.stroke();
      ctx.strokeStyle = 'rgba(230,250,255,0.95)'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(b.x, b.y - 10); ctx.lineTo(tip.x, tip.y - 10); ctx.stroke();
    }
  }
  for (const pr of G.eprojs) { const s = R.S(pr.x, pr.y); glowBall(ctx, s.x, s.y - 10, pr.r * 2, pr.rgb || '230,220,170'); }
  for (const fx of G.effects) if (fx.kind === 'bolt') drawBolt(ctx, fx);
  ctx.globalCompositeOperation = 'source-over';

  // ---- overlays: hp bars, labels, damage numbers ----
  ctx.textAlign = 'center';
  for (const e of vis) {
    if (e === p || e.merchant || e.pet || e.device || e.brazier) continue;
    const s = R.S(e.x, e.y);
    if (e.ally) {
      const w = 26, y = s.y - (e.totem ? 58 : 36);
      ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillRect(s.x - w / 2 - 1, y - 1, w + 2, 5);
      ctx.fillStyle = '#5ac85a'; ctx.fillRect(s.x - w / 2, y, w * Math.max(0, e.life / e.maxLife), 3);
      if (e.totem) { ctx.fillStyle = '#d8a060'; ctx.fillRect(s.x - w / 2, y + 4, w * (1 - e.t / e.max), 2); }
      continue;
    }
    if (e.life < e.maxLife || e.elite) {
      const w = Math.max(30, e.r * 2.4), y = s.y - e.r * 2 - 18 - (e.boss ? 14 : 0);
      ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillRect(s.x - w / 2 - 1, y - 1, w + 2, 6);
      ctx.fillStyle = e.elite ? '#4f8cff' : '#c42a2a'; ctx.fillRect(s.x - w / 2, y, w * Math.max(0, e.life / e.maxLife), 4);
    }
    if (e.elite) {
      ctx.font = 'bold 12px sans-serif'; ctx.fillStyle = '#8fb4ff';
      ctx.fillText(e.name, s.x, s.y - e.r * 2 - 24);
    }
  }
  if (G.merchant) {
    const mer = G.merchant, s = R.S(mer.x, mer.y), near = dist2(mer.x, mer.y, p.x, p.y) < 200 * 200;
    ctx.font = 'bold 13px sans-serif'; ctx.fillStyle = '#ffd36a';
    ctx.fillText('商人', s.x, s.y - 44);
    if (near) { ctx.font = '11px sans-serif'; ctx.fillStyle = '#e8dcc4'; ctx.fillText('クリック / B で取引', s.x, s.y - 58); }
  }
  if (G.device) {
    const dv = G.device, s = R.S(dv.x, dv.y), near = dist2(dv.x, dv.y, p.x, p.y) < 200 * 200;
    ctx.font = 'bold 13px sans-serif'; ctx.fillStyle = '#ffb35a';
    ctx.fillText('遠征図の祭壇', s.x, s.y - 54);
    if (near) { ctx.font = '11px sans-serif'; ctx.fillStyle = '#e8dcc4'; ctx.fillText('クリック / B で行き先を選ぶ', s.x, s.y - 68); }
  }
  ctx.font = '12px sans-serif';
  for (const g of G.drops) {
    if (g.k === 'ember' || dist2(g.x, g.y, p.x, p.y) > 520 * 520) continue;
    const s = R.S(g.x, g.y), c = CUR_BY_KEY[g.k], label = g.gem ? `${c.icon} ${SUPPORT_BY_ID[g.gem].name}のジェム` : `${c.icon} ${c.name}`, w = ctx.measureText(label).width + 10;
    ctx.fillStyle = 'rgba(0,0,0,0.75)'; ctx.fillRect(s.x - w / 2, s.y - 28, w, 17);
    ctx.fillStyle = c.color; ctx.fillText(label, s.x, s.y - 15);
  }
  for (const g of G.ground) {
    const d = dist(g.x, g.y, p.x, p.y);
    if (d > 520 || (g.item.rarity === 0 && d > 200)) continue;
    const s = R.S(g.x, g.y), w = ctx.measureText(g.item.name).width + 10;
    ctx.fillStyle = 'rgba(0,0,0,0.75)'; ctx.fillRect(s.x - w / 2, s.y - 30, w, 17);
    ctx.fillStyle = RARITY[g.item.rarity].color; ctx.fillText(g.item.name, s.x, s.y - 17);
  }
  for (const t of G.texts) {
    const s = R.S(t.x, t.y);
    ctx.globalAlpha = Math.min(1, (0.9 - t.t) * 3);
    ctx.font = `bold ${t.size}px sans-serif`;
    ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(0,0,0,0.8)';
    ctx.strokeText(t.str, s.x, s.y - 20 + t.z); ctx.fillStyle = t.color; ctx.fillText(t.str, s.x, s.y - 20 + t.z);
  }
  ctx.globalAlpha = 1;

  // low-life vignette
  if (p.life / p.s.maxLife < 0.3 || p.hitFlash > 0) {
    const k = p.hitFlash > 0 ? 0.35 : 0.25 * (1 + Math.sin(G.time * 6)) / 2 + 0.1;
    const vg = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.3, W / 2, H / 2, Math.max(W, H) * 0.7);
    vg.addColorStop(0, 'rgba(150,0,0,0)'); vg.addColorStop(1, `rgba(150,0,0,${k})`);
    ctx.fillStyle = vg; ctx.fillRect(0, 0, W, H);
  }

  R.miniT -= dt;
  if (R.miniT <= 0) { R.miniT = 0.2; drawMinimap(); }
}

// an isometric wall block; only the faces that look toward the camera are drawn
function drawWall(ctx, m, th, tx, ty, ps, pd) {
  const x = tx * T, y = ty * T, h = WALL_ISO;
  const a = R.S(x, y), b = R.S(x + T, y), c = R.S(x + T, y + T), d = R.S(x, y + T);
  const quad = (p1, p2, p3, p4) => { ctx.beginPath(); ctx.moveTo(p1.x, p1.y); ctx.lineTo(p2.x, p2.y); ctx.lineTo(p3.x, p3.y); ctx.lineTo(p4.x, p4.y); ctx.closePath(); ctx.fill(); };
  const up = q => ({ x: q.x, y: q.y - h });
  // see-through when the block hides the player
  const cx = (a.x + c.x) / 2, cy = (a.y + c.y) / 2 - h;
  ctx.globalAlpha = (tx + ty + 1) * T > pd && Math.abs(cx - ps.x) < 70 && cy - ps.y < 20 && ps.y - cy < 90 ? 0.35 : 1;
  if (!m.isWall(tx, ty + 1)) {
    ctx.fillStyle = th.wallFront; quad(d, c, up(c), up(d));
    ctx.fillStyle = 'rgba(0,0,0,0.2)'; ctx.fillRect(d.x, up(d).y + h * 0.5, 1, 1);
  }
  if (!m.isWall(tx + 1, ty)) { ctx.fillStyle = th.wallFront; quad(b, c, up(c), up(b)); ctx.fillStyle = 'rgba(0,0,0,0.3)'; quad(b, c, up(c), up(b)); }
  const n = m.noise[m.idx(tx, ty)];
  ctx.fillStyle = th.wallTop; quad(up(a), up(b), up(c), up(d));
  ctx.fillStyle = `rgba(0,0,0,${0.05 + (n % 7) * 0.025})`; quad(up(a), up(b), up(c), up(d));
  ctx.globalAlpha = 1;
}

function glowBall(ctx, x, y, r, rgb) {
  const g = ctx.createRadialGradient(x, y, 0, x, y, r);
  g.addColorStop(0, 'rgba(255,255,230,1)'); g.addColorStop(0.3, `rgba(${rgb},0.9)`); g.addColorStop(1, `rgba(${rgb},0)`);
  ctx.fillStyle = g; ctx.fillRect(x - r, y - r, r * 2, r * 2);
}

// ground-plane effects (drawn with the iso transform)
function drawEffect(ctx, fx) {
  const k = fx.t / fx.max;
  if (fx.kind === 'arc') {
    ctx.strokeStyle = `rgba(255,240,210,${1 - k})`; ctx.lineWidth = 10 * (1 - k) + 2;
    const sweep = -1.1 + k * 2.2;
    ctx.beginPath(); ctx.arc(fx.x, fx.y, fx.r * 0.8, fx.a - 1.1, fx.a + Math.min(1.1, sweep)); ctx.stroke();
  } else if (fx.kind === 'spin') {
    ctx.strokeStyle = `rgba(255,230,170,${1 - k})`; ctx.lineWidth = 12 * (1 - k) + 2;
    ctx.beginPath(); ctx.arc(fx.x, fx.y, fx.r * 0.75, fx.a + k * TAU - 2.2, fx.a + k * TAU); ctx.stroke();
    ctx.strokeStyle = `rgba(255,200,120,${0.4 * (1 - k)})`; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.arc(fx.x, fx.y, fx.r, 0, TAU); ctx.stroke();
  } else if (fx.kind === 'ring') {
    const r = fx.r0 + (fx.r1 - fx.r0) * Math.sqrt(k);
    ctx.strokeStyle = `rgba(${fx.color},${1 - k})`; ctx.lineWidth = 6 * (1 - k) + 1;
    ctx.beginPath(); ctx.arc(fx.x, fx.y, r, 0, TAU); ctx.stroke();
    if (fx.fill) { ctx.fillStyle = `rgba(${fx.color},${0.25 * (1 - k)})`; ctx.fill(); }
  }
}

// lightning between two points, or straight down from the sky
function drawBolt(ctx, fx) {
  const k = fx.t / fx.max, e = R.S(fx.x1, fx.y1);
  const s = fx.sky ? { x: e.x + rand(-30, 30), y: e.y - 320 } : R.S(fx.x0, fx.y0);
  const off = fx.sky ? 0 : 10;
  ctx.strokeStyle = `rgba(220,200,255,${1 - k})`; ctx.lineWidth = 3;
  ctx.beginPath(); ctx.moveTo(s.x, s.y - off);
  for (let i = 1; i < 7; i++) {
    const t = i / 7;
    ctx.lineTo(s.x + (e.x - s.x) * t + rand(-10, 10), s.y - off + (e.y - off - s.y + off) * t + rand(-8, 8));
  }
  ctx.lineTo(e.x, e.y - off); ctx.stroke();
  ctx.lineWidth = 8; ctx.strokeStyle = `rgba(150,110,255,${0.3 * (1 - k)})`; ctx.stroke();
}

function drawPortal(ctx, po) {
  const t = po.t, s = R.S(po.x, po.y), x = s.x, y = s.y - 30;
  for (let i = 0; i < 3; i++) {
    ctx.strokeStyle = `rgba(${i === 1 ? '255,150,60' : '120,80,255'},0.8)`; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.ellipse(x, y, 22 - i * 5, 36 - i * 7, 0, t * (2 + i), t * (2 + i) + 4.5); ctx.stroke();
  }
  const g = ctx.createRadialGradient(x, y, 0, x, y, 36);
  g.addColorStop(0, 'rgba(255,200,140,0.8)'); g.addColorStop(1, 'rgba(90,40,200,0)');
  ctx.fillStyle = g; ctx.beginPath(); ctx.ellipse(x, y, 24, 38, 0, 0, TAU); ctx.fill();
  if (Math.random() < 0.5) G.particles.push({ x: po.x + rand(-15, 15), y: po.y + rand(-15, 15), vx: 0, vy: 0, vz: rand(40, 90), t: 0, max: 0.8, size: 3, color: '#b9a0ff', glow: true });
}

function drawPlayer(ctx, p, sx, sy) {
  const bob = Math.sin(p.walkT * 14) * 1.5;
  const x = sx, y = sy - 10 + bob, aim = isoAngle(p.aim);
  ctx.save();
  if (p.invuln > 0 && p.dash) ctx.globalAlpha = 0.6;
  // cape
  const back = aim + Math.PI;
  ctx.fillStyle = '#6a1e22';
  ctx.beginPath();
  ctx.moveTo(x + Math.cos(back + 1.3) * 11, y + Math.sin(back + 1.3) * 6 - 6);
  ctx.lineTo(x + Math.cos(back) * 18, y + Math.sin(back) * 9 + 6);
  ctx.lineTo(x + Math.cos(back - 1.3) * 11, y + Math.sin(back - 1.3) * 6 - 6);
  ctx.fill();
  // body
  ctx.fillStyle = p.hitFlash > 0 ? '#fff' : p.chill > 0 ? '#6a9ac8' : '#3c4f6e';
  ctx.strokeStyle = '#0d1018'; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.ellipse(x, y, p.r * 0.9, p.r * 1.15, 0, 0, TAU); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#8a7a5a';
  ctx.beginPath(); ctx.ellipse(x, y + 2, p.r * 0.5, p.r * 0.65, 0, 0, TAU); ctx.fill();
  // head
  ctx.fillStyle = '#c9a98a';
  ctx.beginPath(); ctx.arc(x + Math.cos(aim) * 2, y - p.r - 2, 6, 0, TAU); ctx.fill();
  // weapon
  let wa = aim;
  if (p.swingT > 0) wa = isoAngle(p.swingDir) - 1.2 + (1 - p.swingT / 0.2) * 2.4;
  ctx.strokeStyle = '#d8d8e0'; ctx.lineWidth = 4; ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(x + Math.cos(wa) * 10, y + Math.sin(wa) * 6);
  ctx.lineTo(x + Math.cos(wa) * 34, y + Math.sin(wa) * 20 - 4);
  ctx.stroke();
  ctx.strokeStyle = '#7a5a2a'; ctx.lineWidth = 6;
  ctx.beginPath();
  ctx.moveTo(x + Math.cos(wa) * 8, y + Math.sin(wa) * 5);
  ctx.lineTo(x + Math.cos(wa) * 13, y + Math.sin(wa) * 8);
  ctx.stroke();
  ctx.restore();
}

function drawPet(ctx, pet, sx, sy) {
  const moving = pet.target || (pet.home && dist(pet.x, pet.y, G.player.x + pet.home.dx, G.player.y + pet.home.dy) > 6);
  const hop = moving ? Math.abs(Math.sin(pet.walkT * 16)) * 3 : 0;
  const f = isoAngle(pet.face), x = sx, y = sy - 8 - hop, dir = Math.cos(f) >= 0 ? 1 : -1;
  // tail with a little lantern on its tip
  const sw = Math.sin(G.time * 5) * 0.4;
  const tx = x - dir * 14, ty = y - 6 + sw * 6;
  ctx.strokeStyle = '#e8873a'; ctx.lineWidth = 6; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.moveTo(x - dir * 5, y); ctx.quadraticCurveTo(x - dir * 14, y + 2, tx, ty); ctx.stroke();
  ctx.strokeStyle = '#fff3e0'; ctx.lineWidth = 4;
  ctx.beginPath(); ctx.moveTo(tx + dir * 2, ty + 2); ctx.lineTo(tx, ty); ctx.stroke();
  const g = ctx.createRadialGradient(tx, ty - 4, 0, tx, ty - 4, 10);
  g.addColorStop(0, 'rgba(255,240,170,1)'); g.addColorStop(1, 'rgba(255,170,60,0)');
  ctx.fillStyle = g; ctx.fillRect(tx - 10, ty - 14, 20, 20);
  // body
  ctx.fillStyle = '#e8873a'; ctx.strokeStyle = 'rgba(0,0,0,0.6)'; ctx.lineWidth = 1.5;
  ctx.beginPath(); ctx.ellipse(x, y, 10, 7, 0, 0, TAU); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#fff3e0';
  ctx.beginPath(); ctx.ellipse(x + dir * 3, y + 3, 5, 3, 0, 0, TAU); ctx.fill();
  // head and ears
  const hx = x + dir * 9, hy = y - 6;
  ctx.fillStyle = '#e8873a';
  for (const e of [-1, 1]) {
    ctx.beginPath(); ctx.moveTo(hx + e * 4 - 2, hy - 3); ctx.lineTo(hx + e * 5, hy - 12); ctx.lineTo(hx + e * 6 + 2, hy - 2); ctx.fill();
  }
  ctx.beginPath(); ctx.arc(hx, hy, 6.5, 0, TAU); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#fff3e0';
  ctx.beginPath(); ctx.arc(hx + dir * 3, hy + 2, 3, 0, TAU); ctx.fill();
  ctx.fillStyle = '#2a1a10';
  ctx.beginPath(); ctx.arc(hx + dir * 2.5, hy - 1.5, 1.4, 0, TAU); ctx.fill();
  ctx.beginPath(); ctx.arc(hx + dir * 6, hy + 1.5, 1.2, 0, TAU); ctx.fill();
}

function drawMinion(ctx, m, sx, sy) {
  const f = isoAngle(m.face), bob = Math.abs(Math.sin(m.walkT * 12)) * 2, x = sx, y = sy - 12 - bob;
  ctx.fillStyle = m.hitT > 0 ? '#fff' : '#d8d0b8'; ctx.strokeStyle = 'rgba(0,0,0,0.7)'; ctx.lineWidth = 1.5;
  // ribcage body and skull
  ctx.beginPath(); ctx.ellipse(x, y, 7, 9, 0, 0, TAU); ctx.fill(); ctx.stroke();
  ctx.strokeStyle = 'rgba(60,50,40,0.6)'; ctx.lineWidth = 1;
  for (const k of [-3, 0, 3]) { ctx.beginPath(); ctx.moveTo(x - 5, y + k); ctx.lineTo(x + 5, y + k); ctx.stroke(); }
  ctx.fillStyle = '#e8e0c8'; ctx.strokeStyle = 'rgba(0,0,0,0.7)';
  ctx.beginPath(); ctx.arc(x + Math.cos(f) * 1.5, y - 13, 6, 0, TAU); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#7fe0ff';
  if (Math.sin(f) > -0.3) for (const s of [-2.2, 2.2]) { ctx.beginPath(); ctx.arc(x + Math.cos(f) * 2 + s, y - 13, 1.3, 0, TAU); ctx.fill(); }
  // rusty sword
  let wa = f; if (m.swingT > 0) wa = f - 1 + (1 - m.swingT / 0.2) * 2;
  ctx.strokeStyle = '#a8a090'; ctx.lineWidth = 3; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.moveTo(x + Math.cos(wa) * 6, y + Math.sin(wa) * 4); ctx.lineTo(x + Math.cos(wa) * 22, y + Math.sin(wa) * 12 - 4); ctx.stroke();
}

function drawTotem(ctx, t, sx, sy) {
  const col = SKILLS[t.skill].color, x = sx, y = sy, h = 40, pulse = 0.6 + Math.sin(G.time * 6) * 0.3;
  // carved wooden pole
  ctx.fillStyle = t.hitT > 0 ? '#fff' : '#6a4a2a'; ctx.strokeStyle = 'rgba(0,0,0,0.7)'; ctx.lineWidth = 2;
  ctx.fillRect(x - 7, y - h, 14, h); ctx.strokeRect(x - 7, y - h, 14, h);
  ctx.fillStyle = '#4a3018';
  for (const k of [10, 22]) ctx.fillRect(x - 9, y - h + k, 18, 4);
  // glowing rune head in the skill's color
  const g = ctx.createRadialGradient(x, y - h - 6, 0, x, y - h - 6, 16);
  g.addColorStop(0, col); g.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.globalAlpha = pulse; ctx.fillStyle = g; ctx.fillRect(x - 16, y - h - 22, 32, 32); ctx.globalAlpha = 1;
  ctx.fillStyle = col; ctx.font = 'bold 14px sans-serif'; ctx.textAlign = 'center';
  ctx.fillText(SKILLS[t.skill].icon, x, y - h - 1);
}

// stone table holding the glowing expedition map
function drawDevice(ctx, d, sx, sy) {
  const x = sx, y = sy, t = G.time;
  ctx.fillStyle = '#4a3e32'; ctx.strokeStyle = 'rgba(0,0,0,0.7)'; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.ellipse(x, y - 4, 30, 30 * PITCH, 0, 0, TAU); ctx.fill(); ctx.stroke();
  ctx.fillRect(x - 30, y - 22, 60, 18); ctx.strokeRect(x - 30, y - 22, 60, 18);
  ctx.fillStyle = '#6a5a48';
  ctx.beginPath(); ctx.ellipse(x, y - 22, 30, 30 * PITCH, 0, 0, TAU); ctx.fill(); ctx.stroke();
  // the map itself: rotating rune rings
  for (let i = 0; i < 3; i++) {
    ctx.strokeStyle = `rgba(${i === 1 ? '180,140,255' : '255,180,90'},${0.5 + Math.sin(t * 3 + i) * 0.3})`; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.ellipse(x, y - 22, 24 - i * 7, (24 - i * 7) * PITCH, 0, t * (1 + i * 0.5), t * (1 + i * 0.5) + 4.5); ctx.stroke();
  }
  const g = ctx.createRadialGradient(x, y - 30, 0, x, y - 30, 26);
  g.addColorStop(0, 'rgba(255,200,130,0.7)'); g.addColorStop(1, 'rgba(255,140,40,0)');
  ctx.fillStyle = g; ctx.fillRect(x - 26, y - 56, 52, 52);
  if (Math.random() < 0.3) G.particles.push({ x: d.x + rand(-15, 15), y: d.y + rand(-15, 15), vx: 0, vy: 0, vz: rand(30, 60), z: 20, t: 0, max: 0.9, size: 2.5, color: '#ffc880', glow: true });
}

function drawBrazier(ctx, b, sx, sy) {
  const x = sx, y = sy;
  ctx.fillStyle = '#3a2e24'; ctx.strokeStyle = 'rgba(0,0,0,0.7)'; ctx.lineWidth = 2;
  ctx.fillRect(x - 4, y - 22, 8, 22);
  ctx.beginPath(); ctx.ellipse(x, y - 24, 12, 12 * PITCH, 0, 0, TAU); ctx.fill(); ctx.stroke();
  const fl = 0.8 + Math.sin(G.time * 11 + x) * 0.2;
  const g = ctx.createRadialGradient(x, y - 32, 0, x, y - 32, 16 * fl);
  g.addColorStop(0, 'rgba(255,240,180,1)'); g.addColorStop(0.5, 'rgba(255,140,40,0.8)'); g.addColorStop(1, 'rgba(255,80,20,0)');
  ctx.fillStyle = g; ctx.fillRect(x - 16, y - 48, 32, 32);
  if (Math.random() < 0.3) G.particles.push({ x: b.x + rand(-5, 5), y: b.y + rand(-5, 5), vx: 0, vy: 0, vz: rand(40, 80), z: 30, t: 0, max: 0.7, size: 2.5, color: '#ff9a40', glow: true });
}

function drawMerchant(ctx, m, sx, sy) {
  const x = sx, y = sy - 12, sway = Math.sin(G.time * 2) * 1.5;
  // pack on the back
  ctx.fillStyle = '#5a3e22'; ctx.strokeStyle = 'rgba(0,0,0,0.7)'; ctx.lineWidth = 2;
  ctx.fillRect(x - 15, y - 16, 14, 18); ctx.strokeRect(x - 15, y - 16, 14, 18);
  // robe
  ctx.fillStyle = '#4a3a5a';
  ctx.beginPath(); ctx.ellipse(x, y, m.r * 0.95, m.r * 1.2, 0, 0, TAU); ctx.fill(); ctx.stroke();
  // hood
  ctx.fillStyle = '#36284a';
  ctx.beginPath(); ctx.arc(x + 1, y - 13, 8, 0, TAU); ctx.fill();
  ctx.fillStyle = '#c9a98a';
  ctx.beginPath(); ctx.arc(x + 3, y - 12, 3.5, 0, TAU); ctx.fill();
  // lantern on a staff
  ctx.strokeStyle = '#6a4a22'; ctx.lineWidth = 3;
  ctx.beginPath(); ctx.moveTo(x + 12, y + 14); ctx.lineTo(x + 14, y - 26); ctx.stroke();
  const g = ctx.createRadialGradient(x + 14 + sway, y - 16, 0, x + 14 + sway, y - 16, 12);
  g.addColorStop(0, 'rgba(255,240,180,1)'); g.addColorStop(1, 'rgba(255,170,60,0)');
  ctx.fillStyle = g; ctx.fillRect(x + 2 + sway, y - 28, 24, 24);
  ctx.fillStyle = '#ffd36a'; ctx.fillRect(x + 11 + sway, y - 19, 6, 7);
}

function drawEnemy(ctx, e, sx, sy) {
  const t = e.t, f = isoAngle(e.face);
  let x = sx, y = sy - e.r * 0.9;
  if (e.windup > 0) { x += rand(-1.5, 1.5); y += rand(-1.5, 1.5); }
  let col = t.color;
  if (e.hitT > 0) col = '#ffffff';
  else if (e.frozen > 0) col = '#9fdcff';
  if (e.elite || e.boss) {
    const g = ctx.createRadialGradient(x, y, e.r * 0.6, x, y, e.r * 1.8);
    g.addColorStop(0, e.boss ? 'rgba(255,60,40,0.4)' : 'rgba(80,140,255,0.4)'); g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, e.r * 1.8, 0, TAU); ctx.fill();
  }
  ctx.fillStyle = col; ctx.strokeStyle = 'rgba(0,0,0,0.7)'; ctx.lineWidth = 2;
  if (e.type === 'colossus') { drawColossus(ctx, e, x, y, col, f); return; }
  if (e.type === 'witch') { drawWitch(ctx, e, x, y, col, f); return; }
  if (e.type === 'brute' || e.boss) {
    // horns
    ctx.fillStyle = '#d8ccb0';
    for (const s of [-1, 1]) {
      ctx.beginPath();
      ctx.moveTo(x + Math.cos(f + s * 0.6) * e.r * 0.8, y + Math.sin(f + s * 0.6) * e.r * 0.4 - e.r * 0.5);
      ctx.lineTo(x + Math.cos(f + s * 0.9) * e.r * 1.4, y + Math.sin(f + s * 0.9) * e.r * 0.6 - e.r * 1.3);
      ctx.lineTo(x + Math.cos(f + s * 1.1) * e.r * 0.8, y + Math.sin(f + s * 1.1) * e.r * 0.4 - e.r * 0.5);
      ctx.fill();
    }
    ctx.fillStyle = col;
  }
  if (e.type === 'imp') {
    ctx.beginPath();
    for (let i = 0; i < 5; i++) { const a = -Math.PI / 2 + i / 5 * TAU; ctx.lineTo(x + Math.cos(a) * e.r * (i % 2 ? 0.8 : 1.15), y + Math.sin(a) * e.r * (i % 2 ? 0.85 : 1.2)); }
    ctx.closePath(); ctx.fill(); ctx.stroke();
  } else {
    ctx.beginPath(); ctx.ellipse(x, y, e.r, e.r * 1.1, 0, 0, TAU); ctx.fill(); ctx.stroke();
  }
  if (e.type === 'archer') {
    ctx.strokeStyle = '#7a5a30'; ctx.lineWidth = 2.5;
    ctx.beginPath(); ctx.arc(x + Math.cos(f) * 6, y + Math.sin(f) * 3, e.r + 2, f - 1.1, f + 1.1); ctx.stroke();
  } else if (e.type === 'shaman') {
    ctx.strokeStyle = '#5a4020'; ctx.lineWidth = 3;
    const stx = x + Math.cos(f + 0.8) * e.r, sty = y + Math.sin(f + 0.8) * e.r * 0.5;
    ctx.beginPath(); ctx.moveTo(stx, sty + 10); ctx.lineTo(stx, sty - 20); ctx.stroke();
    ctx.fillStyle = e.windup > 0 ? '#bff' : '#5ad8e8'; ctx.beginPath(); ctx.arc(stx, sty - 22, 4, 0, TAU); ctx.fill();
  } else if (e.type === 'ghoul') {
    ctx.fillStyle = 'rgba(0,0,0,0.35)'; ctx.beginPath(); ctx.arc(x, y + 3, e.r * 0.6, 0, Math.PI); ctx.fill();
  }
  // eyes: only when facing the camera side
  if (Math.sin(f) > -0.3) {
    ctx.fillStyle = e.boss ? '#ff3' : e.type === 'archer' ? '#4ff' : '#ffda4a';
    for (const s of [-0.45, 0.45]) {
      ctx.beginPath(); ctx.arc(x + Math.cos(f + s) * e.r * 0.55, y - e.r * 0.3 + Math.sin(f + s) * e.r * 0.25, Math.max(1.6, e.r * 0.12), 0, TAU); ctx.fill();
    }
  }
}

function drawColossus(ctx, e, x, y, col, f) {
  const r = e.r, pulse = 0.6 + Math.sin(G.time * 4) * 0.25 + (e.enraged ? 0.3 : 0);
  y -= r * 0.3;
  // rocky body made of overlapping boulders
  ctx.fillStyle = col;
  for (const [ox, oy, s] of [[-0.55, 0.25, 0.55], [0.55, 0.25, 0.55], [0, -0.3, 0.8], [0, 0.45, 0.6]]) {
    ctx.beginPath(); ctx.arc(x + ox * r, y + oy * r, s * r, 0, TAU); ctx.fill(); ctx.stroke();
  }
  // molten cracks
  ctx.strokeStyle = `rgba(255,${120 + pulse * 60 | 0},40,${pulse})`; ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(x - r * 0.5, y - r * 0.5); ctx.lineTo(x - r * 0.1, y - r * 0.1); ctx.lineTo(x - r * 0.3, y + r * 0.5);
  ctx.moveTo(x + r * 0.2, y - r * 0.7); ctx.lineTo(x + r * 0.35, y - r * 0.15); ctx.lineTo(x + r * 0.6, y + r * 0.3);
  ctx.moveTo(x - r * 0.1, y - r * 0.1); ctx.lineTo(x + r * 0.35, y - r * 0.15);
  ctx.stroke();
  // fists
  for (const s of [-1, 1]) {
    const fx = x + Math.cos(f + s * 1.1) * r * 1.05, fy = y + Math.sin(f + s * 1.1) * r * 0.5 + r * 0.2;
    ctx.fillStyle = '#5a2a18'; ctx.beginPath(); ctx.arc(fx, fy, r * 0.32, 0, TAU); ctx.fill(); ctx.stroke();
  }
  // burning eyes
  ctx.fillStyle = '#ffe070';
  for (const s of [-0.35, 0.35]) {
    ctx.beginPath(); ctx.arc(x + Math.cos(f + s) * r * 0.45, y - r * 0.45 + Math.sin(f + s) * r * 0.15, 4, 0, TAU); ctx.fill();
  }
  if (Math.random() < 0.4) G.particles.push({ x: e.x + rand(-r, r) * 0.6, y: e.y + rand(-r, r) * 0.6, vx: 0, vy: 0, vz: rand(30, 70), z: r, t: 0, max: 0.7, size: 3, color: '#ff8a30', glow: true });
}

function drawWitch(ctx, e, x, y, col, f) {
  const r = e.r, t = G.time;
  // orbiting ice crystals
  for (let i = 0; i < (e.enraged ? 5 : 3); i++) {
    const a = t * 2 + i / (e.enraged ? 5 : 3) * TAU, cx = x + Math.cos(a) * r * 1.6, cy = y + Math.sin(a) * r * 0.8 - 6;
    ctx.fillStyle = '#bff4ff';
    ctx.beginPath(); ctx.moveTo(cx, cy - 8); ctx.lineTo(cx + 4, cy); ctx.lineTo(cx, cy + 8); ctx.lineTo(cx - 4, cy); ctx.fill();
  }
  // robe
  ctx.fillStyle = col; ctx.strokeStyle = 'rgba(0,0,0,0.7)'; ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(x - r, y + r * 0.8); ctx.quadraticCurveTo(x - r * 0.9, y - r * 0.3, x, y - r * 0.5);
  ctx.quadraticCurveTo(x + r * 0.9, y - r * 0.3, x + r, y + r * 0.8); ctx.closePath(); ctx.fill(); ctx.stroke();
  // pale face and pointed hood
  ctx.fillStyle = '#d8e8f0';
  ctx.beginPath(); ctx.arc(x + Math.cos(f) * 3, y - r * 0.55, r * 0.32, 0, TAU); ctx.fill();
  ctx.fillStyle = '#22344e';
  ctx.beginPath(); ctx.moveTo(x - r * 0.5, y - r * 0.55); ctx.lineTo(x + Math.cos(f) * 6, y - r * 1.9); ctx.lineTo(x + r * 0.5, y - r * 0.55); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#7ff0ff';
  for (const s of [-1, 1]) { ctx.beginPath(); ctx.arc(x + Math.cos(f) * 4 + s * 4, y - r * 0.55, 2, 0, TAU); ctx.fill(); }
  // staff with a glowing tip
  const stx = x + Math.cos(f + 0.9) * r, sty = y + Math.sin(f + 0.9) * r * 0.5;
  ctx.strokeStyle = '#9ab0c0'; ctx.lineWidth = 3;
  ctx.beginPath(); ctx.moveTo(stx, sty + 14); ctx.lineTo(stx, sty - 30); ctx.stroke();
  ctx.fillStyle = e.windup > 0 ? '#ffffff' : '#9fe8ff';
  ctx.beginPath(); ctx.arc(stx, sty - 33, 5, 0, TAU); ctx.fill();
}

// minimap drawn with the same iso rotation as the world
function drawMinimap() {
  const m = G.map, c = R.mctx, S = 2.4, p = G.player;
  const W = R.mini.width, H = R.mini.height;
  c.setTransform(1, 0, 0, 1, 0, 0);
  c.clearRect(0, 0, W, H);
  c.fillStyle = 'rgba(0,0,0,0.55)'; c.fillRect(0, 0, W, H);
  c.translate(W / 2, H / 2);
  c.transform(0.7071, 0.7071 * PITCH, -0.7071, 0.7071 * PITCH, 0, 0);
  c.scale(S * 1.4, S * 1.4);
  c.translate(-p.x / T, -p.y / T);
  const r = 40, cx = Math.floor(p.x / T), cy = Math.floor(p.y / T);
  c.fillStyle = 'rgba(190,170,140,0.55)';
  for (let ty = cy - r; ty <= cy + r; ty++) for (let tx = cx - r; tx <= cx + r; tx++) {
    if (tx < 0 || ty < 0 || tx >= m.w || ty >= m.h || !m.explored[m.idx(tx, ty)] || m.isWall(tx, ty)) continue;
    c.fillRect(tx, ty, 1.05, 1.05);
  }
  const dot = (wx, wy, col, rad) => {
    c.fillStyle = col; c.beginPath(); c.arc(wx / T, wy / T, rad, 0, TAU); c.fill();
  };
  for (const e of G.enemies) if (m.explored[m.idx(Math.floor(e.x / T), Math.floor(e.y / T))] && dist2(e.x, e.y, p.x, p.y) < 500 * 500) dot(e.x, e.y, e.elite ? '#6af' : '#d33', e.boss ? 1.4 : 0.55);
  if (G.boss && m.explored[m.idx(Math.floor(G.boss.x / T), Math.floor(G.boss.y / T))]) dot(G.boss.x, G.boss.y, '#f40', 1.4);
  if (G.portal) dot(G.portal.x, G.portal.y, '#b9f', 1.6);
  for (const a of [...G.minions, ...G.totems]) dot(a.x, a.y, '#6d6', 0.6);
  dot(p.x, p.y, '#fff', 1);
}
