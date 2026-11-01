'use strict';
const T = 40;       // tile size in px
const WALL_H = 18;  // fake wall height for the 3/4 view

class Dungeon {
  constructor(w, h, floor) {
    this.w = w; this.h = h; this.floor = floor;
    this.tiles = new Uint8Array(w * h);       // 0 = wall, 1 = floor
    this.explored = new Uint8Array(w * h);
    this.noise = new Uint8Array(w * h);
    for (let i = 0; i < this.noise.length; i++) this.noise[i] = Math.random() * 256;
    this.flow = new Int16Array(w * h);
    this.queue = new Int32Array(w * h);
    this.rooms = [];
    this.generate();
  }

  idx(x, y) { return y * this.w + x; }
  isWall(tx, ty) { return tx < 0 || ty < 0 || tx >= this.w || ty >= this.h || this.tiles[ty * this.w + tx] === 0; }
  solidAt(x, y) { return this.isWall(Math.floor(x / T), Math.floor(y / T)); }
  carve(x, y) { if (x > 0 && y > 0 && x < this.w - 1 && y < this.h - 1) this.tiles[y * this.w + x] = 1; }

  generate() {
    const target = 9 + Math.min(6, Math.floor(this.floor / 2));
    for (let a = 0; a < 500 && this.rooms.length < target; a++) {
      const rw = randi(7, 13), rh = randi(6, 11);
      const x = randi(2, this.w - rw - 3), y = randi(2, this.h - rh - 3);
      if (this.rooms.some(o => x < o.x + o.w + 3 && x + rw + 3 > o.x && y < o.y + o.h + 3 && y + rh + 3 > o.y)) continue;
      const r = { x, y, w: rw, h: rh, cx: Math.floor(x + rw / 2), cy: Math.floor(y + rh / 2) };
      this.rooms.push(r);
      for (let yy = y; yy < y + rh; yy++) for (let xx = x; xx < x + rw; xx++) this.carve(xx, yy);
    }
    // connect every room to its nearest earlier room, then add a few loops
    for (let i = 1; i < this.rooms.length; i++) {
      let best = 0, bd = Infinity;
      for (let j = 0; j < i; j++) {
        const d = dist2(this.rooms[i].cx, this.rooms[i].cy, this.rooms[j].cx, this.rooms[j].cy);
        if (d < bd) { bd = d; best = j; }
      }
      this.corridor(this.rooms[i], this.rooms[best]);
    }
    for (let k = 0; k < 2; k++) this.corridor(pick(this.rooms), pick(this.rooms));

    // ragged edges so rooms don't look like boxes
    for (const r of this.rooms) {
      for (let n = 0; n < 6; n++) {
        const side = randi(0, 3);
        const x = side < 2 ? randi(r.x, r.x + r.w - 1) : side === 2 ? r.x - 1 : r.x + r.w;
        const y = side >= 2 ? randi(r.y, r.y + r.h - 1) : side === 0 ? r.y - 1 : r.y + r.h;
        this.carve(x, y);
      }
      // occasional pillars in big rooms
      if (r.w >= 10 && r.h >= 9 && Math.random() < 0.6) {
        for (const [px, py] of [[r.x + 2, r.y + 2], [r.x + r.w - 3, r.y + 2], [r.x + 2, r.y + r.h - 3], [r.x + r.w - 3, r.y + r.h - 3]])
          this.tiles[this.idx(px, py)] = 0;
      }
    }

    this.start = this.rooms[0];
    this.computeFlow(this.start.cx * T + T / 2, this.start.cy * T + T / 2, 9999);
    let far = this.rooms[1], fd = -1;
    for (const r of this.rooms.slice(1)) {
      const d = this.flow[this.idx(r.cx, r.cy)];
      if (d > fd) { fd = d; far = r; }
    }
    this.bossRoom = far;
  }

  corridor(a, b) {
    const w = randi(2, 3);
    const hFirst = Math.random() < 0.5;
    const hline = (x0, x1, y) => { for (let x = Math.min(x0, x1); x <= Math.max(x0, x1) + w - 1; x++) for (let k = 0; k < w; k++) this.carve(x, y + k); };
    const vline = (y0, y1, x) => { for (let y = Math.min(y0, y1); y <= Math.max(y0, y1) + w - 1; y++) for (let k = 0; k < w; k++) this.carve(x + k, y); };
    if (hFirst) { hline(a.cx, b.cx, a.cy); vline(a.cy, b.cy, b.cx); }
    else { vline(a.cy, b.cy, a.cx); hline(a.cx, b.cx, b.cy); }
  }

  randomFloorIn(room) {
    for (let i = 0; i < 40; i++) {
      const tx = randi(room.x + 1, room.x + room.w - 2), ty = randi(room.y + 1, room.y + room.h - 2);
      if (!this.isWall(tx, ty)) return { x: tx * T + T / 2, y: ty * T + T / 2 };
    }
    return { x: room.cx * T + T / 2, y: room.cy * T + T / 2 };
  }

  // BFS distance field from a world position; enemies walk downhill on it
  computeFlow(px, py, maxD = 45) {
    const { w, flow, queue } = this;
    flow.fill(-1);
    const sx = Math.floor(px / T), sy = Math.floor(py / T);
    if (this.isWall(sx, sy)) return;
    let head = 0, tail = 0;
    flow[sy * w + sx] = 0; queue[tail++] = sy * w + sx;
    while (head < tail) {
      const c = queue[head++], d = flow[c];
      if (d >= maxD) continue;
      const cx = c % w, cy = (c / w) | 0;
      const nb = [[cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]];
      for (const [nx, ny] of nb) {
        if (this.isWall(nx, ny)) continue;
        const ni = ny * w + nx;
        if (flow[ni] !== -1) continue;
        flow[ni] = d + 1; queue[tail++] = ni;
      }
    }
  }

  flowNext(x, y) {
    const tx = Math.floor(x / T), ty = Math.floor(y / T);
    const cur = this.flow[this.idx(tx, ty)];
    if (cur < 0) return null;
    let best = cur, bx = tx, by = ty;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      if (!dx && !dy) continue;
      const nx = tx + dx, ny = ty + dy;
      if (this.isWall(nx, ny)) continue;
      if (dx && dy && (this.isWall(tx + dx, ty) || this.isWall(tx, ty + dy))) continue;
      const v = this.flow[this.idx(nx, ny)];
      if (v >= 0 && v < best) { best = v; bx = nx; by = ny; }
    }
    if (bx === tx && by === ty) return null;
    return { x: bx * T + T / 2, y: by * T + T / 2 };
  }

  los(x0, y0, x1, y1) {
    const d = dist(x0, y0, x1, y1), steps = Math.ceil(d / (T / 3));
    for (let i = 1; i < steps; i++) {
      const t = i / steps;
      if (this.solidAt(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)) return false;
    }
    return true;
  }

  reveal(x, y, radius = 9) {
    const tx = Math.floor(x / T), ty = Math.floor(y / T);
    for (let yy = ty - radius; yy <= ty + radius; yy++) for (let xx = tx - radius; xx <= tx + radius; xx++) {
      if (xx < 0 || yy < 0 || xx >= this.w || yy >= this.h) continue;
      if ((xx - tx) ** 2 + (yy - ty) ** 2 <= radius * radius) this.explored[this.idx(xx, yy)] = 1;
    }
  }
}

function circleHits(map, x, y, r) {
  return map.solidAt(x - r, y - r) || map.solidAt(x + r, y - r) || map.solidAt(x - r, y + r) || map.solidAt(x + r, y + r);
}
function moveCircle(e, dx, dy) {
  const map = G.map;
  if (!circleHits(map, e.x + dx, e.y, e.r)) e.x += dx;
  if (!circleHits(map, e.x, e.y + dy, e.r)) e.y += dy;
}
