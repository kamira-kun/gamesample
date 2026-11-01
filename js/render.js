'use strict';
const R = {
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
};

function tileColor(base, n, k) {
  const v = (n % 17) - 8;
  return `rgb(${base[0] + v * k},${base[1] + v * k},${base[2] + v * k})`;
}

function render(dt) {
  const ctx = R.ctx, W = G.vw, H = G.vh, th = G.theme, p = G.player, m = G.map;
  ctx.setTransform(R.dpr, 0, 0, R.dpr, 0, 0);
  ctx.fillStyle = '#040306';
  ctx.fillRect(0, 0, W, H);
  const ox = Math.round(G.cam.x - W / 2 + rand(-G.shake, G.shake));
  const oy = Math.round(G.cam.y - H / 2 + rand(-G.shake, G.shake));
  ctx.save();
  ctx.translate(-ox, -oy);

  const tx0 = Math.max(0, Math.floor(ox / T) - 1), ty0 = Math.max(0, Math.floor(oy / T) - 1);
  const tx1 = Math.min(m.w - 1, Math.ceil((ox + W) / T) + 1), ty1 = Math.min(m.h - 1, Math.ceil((oy + H) / T) + 2);

  // floor
  for (let ty = ty0; ty <= ty1; ty++) for (let tx = tx0; tx <= tx1; tx++) {
    if (m.isWall(tx, ty)) continue;
    const n = m.noise[m.idx(tx, ty)];
    ctx.fillStyle = tileColor(th.floor, n, 0.8);
    ctx.fillRect(tx * T, ty * T, T, T);
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

  // decals (blood) and ground fx
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
  if (G.portal) drawPortal(ctx, G.portal);

  // loot on ground
  for (const g of G.ground) {
    const col = RARITY[g.item.rarity].color;
    if (g.item.rarity >= 2) {
      const gr = ctx.createLinearGradient(0, g.y - 90, 0, g.y);
      gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, col + '88');
      ctx.fillStyle = gr; ctx.fillRect(g.x - 3, g.y - 90, 6, 90);
    }
    ctx.fillStyle = col;
    ctx.save(); ctx.translate(g.x, g.y); ctx.rotate(0.6);
    ctx.fillRect(-6, -6, 12, 12);
    ctx.strokeStyle = '#000'; ctx.lineWidth = 1.5; ctx.strokeRect(-6, -6, 12, 12);
    ctx.restore();
  }
  for (const g of G.golds) {
    ctx.fillStyle = '#ffcf3a'; ctx.beginPath(); ctx.arc(g.x, g.y, 4, 0, TAU); ctx.fill();
    ctx.fillStyle = '#fff6b0'; ctx.fillRect(g.x - 1, g.y - 2, 2, 2);
  }

  // entities sorted by y
  const ents = G.enemies.filter(e => e.x > ox - 80 && e.x < ox + W + 80 && e.y > oy - 80 && e.y < oy + H + 80);
  ents.push(p);
  if (G.merchant) ents.push(G.merchant);
  ents.sort((a, b) => a.y - b.y);
  for (const e of ents) {
    ctx.fillStyle = 'rgba(0,0,0,0.4)';
    ctx.beginPath(); ctx.ellipse(e.x, e.y + e.r * 0.7, e.r * 1.1, e.r * 0.45, 0, 0, TAU); ctx.fill();
  }
  for (const e of ents) e === p ? drawPlayer(ctx, p) : e.merchant ? drawMerchant(ctx, e) : drawEnemy(ctx, e);

  // walls (drawn after entities so they occlude what stands behind them)
  for (let ty = ty0; ty <= ty1; ty++) for (let tx = tx0; tx <= tx1; tx++) {
    if (!m.isWall(tx, ty)) continue;
    const x = tx * T, y = ty * T;
    const below = !m.isWall(tx, ty + 1);
    const nearFloor = below || !m.isWall(tx, ty - 1) || !m.isWall(tx - 1, ty) || !m.isWall(tx + 1, ty) ||
      !m.isWall(tx - 1, ty + 1) || !m.isWall(tx + 1, ty + 1) || !m.isWall(tx - 1, ty - 1) || !m.isWall(tx + 1, ty - 1);
    if (!nearFloor) { ctx.fillStyle = '#060408'; ctx.fillRect(x, y - WALL_H, T, T); continue; }
    if (below) {
      ctx.fillStyle = th.wallFront; ctx.fillRect(x, y + T - WALL_H, T, WALL_H);
      ctx.fillStyle = 'rgba(0,0,0,0.25)';
      for (let bx = 0; bx < T; bx += 20) ctx.fillRect(x + bx + ((ty % 2) * 10), y + T - WALL_H, 1.5, WALL_H);
    }
    const n = m.noise[m.idx(tx, ty)];
    ctx.fillStyle = th.wallTop; ctx.fillRect(x, y - WALL_H, T, T);
    ctx.fillStyle = `rgba(0,0,0,${0.05 + (n % 7) * 0.025})`; ctx.fillRect(x, y - WALL_H, T, T);
    ctx.fillStyle = 'rgba(255,255,255,0.05)'; ctx.fillRect(x, y - WALL_H, T, 2);
  }
  ctx.restore();

  // ---- lighting: darkness with holes punched by light sources ----
  const L = R.lctx;
  L.setTransform(R.dpr, 0, 0, R.dpr, 0, 0);
  L.globalCompositeOperation = 'source-over';
  L.fillStyle = `rgba(${th.dark},0.86)`;
  L.fillRect(0, 0, W, H);
  L.globalCompositeOperation = 'destination-out';
  const flick = 1 + Math.sin(G.time * 13) * 0.015 + Math.sin(G.time * 7.3) * 0.02;
  const lights = [[p.x, p.y, 420 * flick, 1]];
  for (const pr of G.projs) lights.push([pr.x, pr.y, 110, 0.8]);
  for (const pr of G.eprojs) lights.push([pr.x, pr.y, 50, 0.5]);
  for (const h of G.hazards) lights.push([h.x, h.y, 170, 0.7]);
  for (const fx of G.effects) if (fx.kind === 'ring') lights.push([fx.x, fx.y, fx.r1 * 1.4, 0.8 * (1 - fx.t / fx.max)]);
  for (const t of G.tele) lights.push([t.x, t.y, t.r * 1.2, 0.35]);
  if (G.portal) lights.push([G.portal.x, G.portal.y, 220, 0.9]);
  if (G.merchant) lights.push([G.merchant.x + 14, G.merchant.y - 10, 180, 0.85]);
  for (const st of G.storms) lights.push([st.x, st.y, st.r * 1.3, 0.5]);
  for (const g of G.ground) if (g.item.rarity >= 2) lights.push([g.x, g.y, 60, 0.4]);
  for (const [lx, ly, lr, li] of lights) {
    const sx = lx - ox, sy = ly - oy;
    if (sx < -lr || sy < -lr || sx > W + lr || sy > H + lr) continue;
    const g = L.createRadialGradient(sx, sy, 0, sx, sy, lr);
    g.addColorStop(0, `rgba(0,0,0,${li})`); g.addColorStop(0.5, `rgba(0,0,0,${li * 0.75})`); g.addColorStop(1, 'rgba(0,0,0,0)');
    L.fillStyle = g; L.fillRect(sx - lr, sy - lr, lr * 2, lr * 2);
  }
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.drawImage(R.light, 0, 0);
  ctx.setTransform(R.dpr, 0, 0, R.dpr, 0, 0);

  // warm torch tint around player
  const tg = ctx.createRadialGradient(p.x - ox, p.y - oy, 0, p.x - ox, p.y - oy, 380);
  tg.addColorStop(0, `rgba(${th.torch},0.10)`); tg.addColorStop(1, `rgba(${th.torch},0)`);
  ctx.fillStyle = tg; ctx.fillRect(0, 0, W, H);

  // ---- glow layer ----
  ctx.save();
  ctx.translate(-ox, -oy);
  ctx.globalCompositeOperation = 'lighter';
  for (const pa of G.particles) {
    if (pa.decal) continue;
    const a = 1 - pa.t / pa.max;
    ctx.globalAlpha = pa.glow ? a : a * 0.9;
    ctx.fillStyle = pa.color;
    if (!pa.glow) ctx.globalCompositeOperation = 'source-over';
    ctx.fillRect(pa.x - pa.size / 2, pa.y - pa.size / 2, pa.size, pa.size);
    if (!pa.glow) ctx.globalCompositeOperation = 'lighter';
  }
  ctx.globalAlpha = 1;
  for (const pr of G.projs) {
    if (pr.kind === 'fireball') glowBall(ctx, pr.x, pr.y, 16, '255,160,60');
    else if (pr.kind === 'spear') {
      const bx = pr.x - Math.cos(pr.a) * 30, by = pr.y - Math.sin(pr.a) * 30;
      ctx.lineCap = 'round';
      ctx.strokeStyle = 'rgba(120,210,255,0.5)'; ctx.lineWidth = 10;
      ctx.beginPath(); ctx.moveTo(bx, by); ctx.lineTo(pr.x, pr.y); ctx.stroke();
      ctx.strokeStyle = 'rgba(230,250,255,0.95)'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(bx, by); ctx.lineTo(pr.x + Math.cos(pr.a) * 6, pr.y + Math.sin(pr.a) * 6); ctx.stroke();
    } else {
      ctx.strokeStyle = 'rgba(255,230,180,0.8)'; ctx.lineWidth = 5;
      ctx.beginPath(); ctx.arc(pr.x - Math.cos(pr.a) * 20, pr.y - Math.sin(pr.a) * 20, 26, pr.a - 0.9, pr.a + 0.9); ctx.stroke();
    }
  }
  for (const pr of G.eprojs) glowBall(ctx, pr.x, pr.y, pr.r * 2, pr.rgb || '230,220,170');
  for (const fx of G.effects) drawEffect(ctx, fx);
  ctx.restore();

  // ---- overlays: hp bars, labels, damage numbers ----
  ctx.save();
  ctx.translate(-ox, -oy);
  ctx.textAlign = 'center';
  for (const e of ents) {
    if (e === p) continue;
    if (e.life < e.maxLife || e.elite) {
      const w = Math.max(30, e.r * 2.4), y = e.y - e.r - 16 - (e.boss ? 14 : 0);
      ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillRect(e.x - w / 2 - 1, y - 1, w + 2, 6);
      ctx.fillStyle = e.elite ? '#4f8cff' : '#c42a2a'; ctx.fillRect(e.x - w / 2, y, w * Math.max(0, e.life / e.maxLife), 4);
    }
    if (e.elite) {
      ctx.font = 'bold 12px sans-serif'; ctx.fillStyle = '#8fb4ff';
      ctx.fillText(e.name, e.x, e.y - e.r - 22);
    }
  }
  if (G.merchant) {
    const mer = G.merchant, near = dist2(mer.x, mer.y, p.x, p.y) < 200 * 200;
    ctx.font = 'bold 13px sans-serif'; ctx.fillStyle = '#ffd36a';
    ctx.fillText('商人', mer.x, mer.y - 34);
    if (near) { ctx.font = '11px sans-serif'; ctx.fillStyle = '#e8dcc4'; ctx.fillText('クリック / B で取引', mer.x, mer.y - 20 - 28); }
  }
  ctx.font = '12px sans-serif';
  for (const g of G.ground) {
    const d = dist(g.x, g.y, p.x, p.y);
    if (d > 520 || (g.item.rarity === 0 && d > 200)) continue;
    const w = ctx.measureText(g.item.name).width + 10;
    ctx.fillStyle = 'rgba(0,0,0,0.75)'; ctx.fillRect(g.x - w / 2, g.y - 30, w, 17);
    ctx.fillStyle = RARITY[g.item.rarity].color; ctx.fillText(g.item.name, g.x, g.y - 17);
  }
  for (const t of G.texts) {
    ctx.globalAlpha = Math.min(1, (0.9 - t.t) * 3);
    ctx.font = `bold ${t.size}px sans-serif`;
    ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(0,0,0,0.8)';
    ctx.strokeText(t.str, t.x, t.y); ctx.fillStyle = t.color; ctx.fillText(t.str, t.x, t.y);
  }
  ctx.globalAlpha = 1;
  ctx.restore();

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

function glowBall(ctx, x, y, r, rgb) {
  const g = ctx.createRadialGradient(x, y, 0, x, y, r);
  g.addColorStop(0, 'rgba(255,255,230,1)'); g.addColorStop(0.3, `rgba(${rgb},0.9)`); g.addColorStop(1, `rgba(${rgb},0)`);
  ctx.fillStyle = g; ctx.fillRect(x - r, y - r, r * 2, r * 2);
}

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
  } else if (fx.kind === 'bolt') {
    ctx.strokeStyle = `rgba(220,200,255,${1 - k})`; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.moveTo(fx.x0, fx.y0);
    const segs = 7;
    for (let i = 1; i < segs; i++) {
      const t = i / segs;
      ctx.lineTo(fx.x0 + (fx.x1 - fx.x0) * t + rand(-12, 12), fx.y0 + (fx.y1 - fx.y0) * t + rand(-12, 12));
    }
    ctx.lineTo(fx.x1, fx.y1); ctx.stroke();
    ctx.lineWidth = 8; ctx.strokeStyle = `rgba(150,110,255,${0.3 * (1 - k)})`; ctx.stroke();
  }
}

function drawPortal(ctx, po) {
  const t = po.t;
  for (let i = 0; i < 3; i++) {
    ctx.strokeStyle = `rgba(${i === 1 ? '255,150,60' : '120,80,255'},0.8)`; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.ellipse(po.x, po.y, 26 - i * 6, 34 - i * 7, 0, t * (2 + i) , t * (2 + i) + 4.5); ctx.stroke();
  }
  const g = ctx.createRadialGradient(po.x, po.y, 0, po.x, po.y, 34);
  g.addColorStop(0, 'rgba(255,200,140,0.8)'); g.addColorStop(1, 'rgba(90,40,200,0)');
  ctx.fillStyle = g; ctx.beginPath(); ctx.ellipse(po.x, po.y, 28, 36, 0, 0, TAU); ctx.fill();
  if (Math.random() < 0.5) G.particles.push({ x: po.x + rand(-20, 20), y: po.y + 20, vx: 0, vy: -rand(40, 90), t: 0, max: 0.8, size: 3, color: '#b9a0ff', glow: true });
}

function drawPlayer(ctx, p) {
  const bob = Math.sin(p.walkT * 14) * 1.5;
  const x = p.x, y = p.y + bob;
  ctx.save();
  if (p.invuln > 0 && p.dash) ctx.globalAlpha = 0.6;
  // cape
  const back = p.aim + Math.PI;
  ctx.fillStyle = '#6a1e22';
  ctx.beginPath();
  ctx.moveTo(x + Math.cos(back + 1.3) * 11, y + Math.sin(back + 1.3) * 11 - 4);
  ctx.lineTo(x + Math.cos(back) * 20, y + Math.sin(back) * 20 + 4);
  ctx.lineTo(x + Math.cos(back - 1.3) * 11, y + Math.sin(back - 1.3) * 11 - 4);
  ctx.fill();
  // body
  ctx.fillStyle = p.hitFlash > 0 ? '#fff' : p.chill > 0 ? '#6a9ac8' : '#3c4f6e';
  ctx.strokeStyle = '#0d1018'; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.arc(x, y - 4, p.r, 0, TAU); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#8a7a5a';
  ctx.beginPath(); ctx.arc(x, y - 4, p.r * 0.55, 0, TAU); ctx.fill();
  // head + eyes
  ctx.fillStyle = '#c9a98a';
  ctx.beginPath(); ctx.arc(x + Math.cos(p.aim) * 3, y - 10 + Math.sin(p.aim) * 2, 6, 0, TAU); ctx.fill();
  // weapon
  let wa = p.aim;
  if (p.swingT > 0) wa = p.swingDir - 1.2 + (1 - p.swingT / 0.2) * 2.4;
  ctx.strokeStyle = '#d8d8e0'; ctx.lineWidth = 4; ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(x + Math.cos(wa) * 10, y - 4 + Math.sin(wa) * 10);
  ctx.lineTo(x + Math.cos(wa) * 34, y - 4 + Math.sin(wa) * 34);
  ctx.stroke();
  ctx.strokeStyle = '#7a5a2a'; ctx.lineWidth = 6;
  ctx.beginPath();
  ctx.moveTo(x + Math.cos(wa) * 8, y - 4 + Math.sin(wa) * 8);
  ctx.lineTo(x + Math.cos(wa) * 13, y - 4 + Math.sin(wa) * 13);
  ctx.stroke();
  ctx.restore();
}

function drawMerchant(ctx, m) {
  const x = m.x, y = m.y - 3, sway = Math.sin(G.time * 2) * 1.5;
  // pack on the back
  ctx.fillStyle = '#5a3e22'; ctx.strokeStyle = 'rgba(0,0,0,0.7)'; ctx.lineWidth = 2;
  ctx.fillRect(x - 15, y - 16, 14, 18); ctx.strokeRect(x - 15, y - 16, 14, 18);
  // robe
  ctx.fillStyle = '#4a3a5a';
  ctx.beginPath(); ctx.arc(x, y, m.r, 0, TAU); ctx.fill(); ctx.stroke();
  // hood
  ctx.fillStyle = '#36284a';
  ctx.beginPath(); ctx.arc(x + 1, y - 9, 8, 0, TAU); ctx.fill();
  ctx.fillStyle = '#c9a98a';
  ctx.beginPath(); ctx.arc(x + 3, y - 8, 3.5, 0, TAU); ctx.fill();
  // lantern on a staff
  ctx.strokeStyle = '#6a4a22'; ctx.lineWidth = 3;
  ctx.beginPath(); ctx.moveTo(x + 12, y + 10); ctx.lineTo(x + 14, y - 22); ctx.stroke();
  const g = ctx.createRadialGradient(x + 14 + sway, y - 12, 0, x + 14 + sway, y - 12, 12);
  g.addColorStop(0, 'rgba(255,240,180,1)'); g.addColorStop(1, 'rgba(255,170,60,0)');
  ctx.fillStyle = g; ctx.fillRect(x + 2 + sway, y - 24, 24, 24);
  ctx.fillStyle = '#ffd36a'; ctx.fillRect(x + 11 + sway, y - 15, 6, 7);
}

function drawEnemy(ctx, e) {
  const t = e.t;
  let x = e.x, y = e.y - 3;
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
  const f = e.face;
  if (e.type === 'colossus') { drawColossus(ctx, e, x, y, col); return; }
  if (e.type === 'witch') { drawWitch(ctx, e, x, y, col); return; }
  if (e.type === 'brute' || e.boss) {
    // horns
    ctx.fillStyle = '#d8ccb0';
    for (const s of [-1, 1]) {
      ctx.beginPath();
      ctx.moveTo(x + Math.cos(f + s * 0.6) * e.r * 0.8, y + Math.sin(f + s * 0.6) * e.r * 0.8 - e.r * 0.3);
      ctx.lineTo(x + Math.cos(f + s * 0.9) * e.r * 1.5, y + Math.sin(f + s * 0.9) * e.r * 1.5 - e.r * 0.9);
      ctx.lineTo(x + Math.cos(f + s * 1.1) * e.r * 0.8, y + Math.sin(f + s * 1.1) * e.r * 0.8 - e.r * 0.3);
      ctx.fill();
    }
    ctx.fillStyle = col;
  }
  if (e.type === 'imp') {
    ctx.beginPath();
    for (let i = 0; i < 5; i++) { const a = f + i / 5 * TAU; ctx.lineTo(x + Math.cos(a) * e.r * (i % 2 ? 0.8 : 1.15), y + Math.sin(a) * e.r * (i % 2 ? 0.8 : 1.15)); }
    ctx.closePath(); ctx.fill(); ctx.stroke();
  } else {
    ctx.beginPath(); ctx.arc(x, y, e.r, 0, TAU); ctx.fill(); ctx.stroke();
  }
  if (e.type === 'archer') {
    ctx.strokeStyle = '#7a5a30'; ctx.lineWidth = 2.5;
    ctx.beginPath(); ctx.arc(x + Math.cos(f) * 6, y + Math.sin(f) * 6, e.r + 2, f - 1.1, f + 1.1); ctx.stroke();
  } else if (e.type === 'shaman') {
    ctx.strokeStyle = '#5a4020'; ctx.lineWidth = 3;
    const sx = x + Math.cos(f + 0.8) * e.r, sy = y + Math.sin(f + 0.8) * e.r;
    ctx.beginPath(); ctx.moveTo(sx, sy + 8); ctx.lineTo(sx, sy - 18); ctx.stroke();
    ctx.fillStyle = e.windup > 0 ? '#bff' : '#5ad8e8'; ctx.beginPath(); ctx.arc(sx, sy - 20, 4, 0, TAU); ctx.fill();
  } else if (e.type === 'ghoul') {
    ctx.fillStyle = 'rgba(0,0,0,0.35)'; ctx.beginPath(); ctx.arc(x, y + 3, e.r * 0.6, 0, Math.PI); ctx.fill();
  }
  // eyes
  ctx.fillStyle = e.boss ? '#ff3' : e.type === 'archer' ? '#4ff' : '#ffda4a';
  for (const s of [-0.45, 0.45]) {
    ctx.beginPath(); ctx.arc(x + Math.cos(f + s) * e.r * 0.6, y + Math.sin(f + s) * e.r * 0.6 - 2, Math.max(1.6, e.r * 0.12), 0, TAU); ctx.fill();
  }
}

function drawColossus(ctx, e, x, y, col) {
  const r = e.r, f = e.face, pulse = 0.6 + Math.sin(G.time * 4) * 0.25 + (e.enraged ? 0.3 : 0);
  // rocky body made of overlapping boulders
  ctx.fillStyle = col;
  for (const [ox, oy, s] of [[-0.55, 0.15, 0.55], [0.55, 0.15, 0.55], [0, -0.2, 0.8], [0, 0.35, 0.6]]) {
    ctx.beginPath(); ctx.arc(x + ox * r, y + oy * r, s * r, 0, TAU); ctx.fill(); ctx.stroke();
  }
  // molten cracks
  ctx.strokeStyle = `rgba(255,${120 + pulse * 60 | 0},40,${pulse})`; ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(x - r * 0.5, y - r * 0.4); ctx.lineTo(x - r * 0.1, y - r * 0.05); ctx.lineTo(x - r * 0.3, y + r * 0.4);
  ctx.moveTo(x + r * 0.2, y - r * 0.6); ctx.lineTo(x + r * 0.35, y - r * 0.1); ctx.lineTo(x + r * 0.6, y + r * 0.25);
  ctx.moveTo(x - r * 0.1, y - r * 0.05); ctx.lineTo(x + r * 0.35, y - r * 0.1);
  ctx.stroke();
  // fists
  for (const s of [-1, 1]) {
    const fx = x + Math.cos(f + s * 1.1) * r * 1.05, fy = y + Math.sin(f + s * 1.1) * r * 1.05;
    ctx.fillStyle = '#5a2a18'; ctx.beginPath(); ctx.arc(fx, fy, r * 0.32, 0, TAU); ctx.fill(); ctx.stroke();
  }
  // burning eyes
  ctx.fillStyle = '#ffe070';
  for (const s of [-0.35, 0.35]) {
    ctx.beginPath(); ctx.arc(x + Math.cos(f + s) * r * 0.45, y - r * 0.25 + Math.sin(f + s) * r * 0.3, 4, 0, TAU); ctx.fill();
  }
  if (Math.random() < 0.4) G.particles.push({ x: x + rand(-r, r) * 0.6, y: y - r * 0.4, vx: rand(-10, 10), vy: -rand(30, 70), t: 0, max: 0.7, size: 3, color: '#ff8a30', glow: true });
}

function drawWitch(ctx, e, x, y, col) {
  const r = e.r, f = e.face, t = G.time;
  // orbiting ice crystals
  for (let i = 0; i < (e.enraged ? 5 : 3); i++) {
    const a = t * 2 + i / (e.enraged ? 5 : 3) * TAU, cx = x + Math.cos(a) * r * 1.6, cy = y + Math.sin(a) * r * 1.1 - 6;
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
  const sx = x + Math.cos(f + 0.9) * r, sy = y + Math.sin(f + 0.9) * r * 0.6;
  ctx.strokeStyle = '#9ab0c0'; ctx.lineWidth = 3;
  ctx.beginPath(); ctx.moveTo(sx, sy + 14); ctx.lineTo(sx, sy - 30); ctx.stroke();
  ctx.fillStyle = e.windup > 0 ? '#ffffff' : '#9fe8ff';
  ctx.beginPath(); ctx.arc(sx, sy - 33, 5, 0, TAU); ctx.fill();
}

function drawMinimap() {
  const m = G.map, c = R.mctx, S = 2.6, p = G.player;
  const W = R.mini.width, H = R.mini.height;
  c.clearRect(0, 0, W, H);
  c.fillStyle = 'rgba(0,0,0,0.55)'; c.fillRect(0, 0, W, H);
  const cx = p.x / T, cy = p.y / T;
  const x0 = Math.floor(cx - W / S / 2), y0 = Math.floor(cy - H / S / 2);
  for (let ty = y0; ty < y0 + H / S + 1; ty++) for (let tx = x0; tx < x0 + W / S + 1; tx++) {
    if (tx < 0 || ty < 0 || tx >= m.w || ty >= m.h || !m.explored[m.idx(tx, ty)]) continue;
    if (m.isWall(tx, ty)) continue;
    c.fillStyle = 'rgba(190,170,140,0.55)';
    c.fillRect((tx - x0) * S, (ty - y0) * S, S, S);
  }
  const dot = (wx, wy, col, r) => {
    c.fillStyle = col; c.beginPath(); c.arc((wx / T - x0) * S, (wy / T - y0) * S, r, 0, TAU); c.fill();
  };
  for (const e of G.enemies) if (m.explored[m.idx(Math.floor(e.x / T), Math.floor(e.y / T))] && dist2(e.x, e.y, p.x, p.y) < 500 * 500) dot(e.x, e.y, e.elite ? '#6af' : '#d33', e.boss ? 4 : 1.6);
  if (G.boss && m.explored[m.idx(Math.floor(G.boss.x / T), Math.floor(G.boss.y / T))]) dot(G.boss.x, G.boss.y, '#f40', 4);
  if (G.portal) dot(G.portal.x, G.portal.y, '#b9f', 5);
  dot(p.x, p.y, '#fff', 3);
}
