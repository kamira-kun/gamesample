'use strict';
// ---- math helpers ----
const TAU = Math.PI * 2;
const rand = (a, b) => a + Math.random() * (b - a);
const randi = (a, b) => Math.floor(rand(a, b + 1));
const pick = arr => arr[Math.floor(Math.random() * arr.length)];
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const dist2 = (ax, ay, bx, by) => { const dx = ax - bx, dy = ay - by; return dx * dx + dy * dy; };
const dist = (ax, ay, bx, by) => Math.sqrt(dist2(ax, ay, bx, by));
function weighted(list) {
  let t = 0;
  for (const e of list) t += e.w;
  let r = Math.random() * t;
  for (const e of list) { r -= e.w; if (r <= 0) return e; }
  return list[list.length - 1];
}
function angleDiff(a, b) {
  let d = (b - a) % TAU;
  if (d > Math.PI) d -= TAU;
  if (d < -Math.PI) d += TAU;
  return d;
}
let uidCounter = Date.now();
const uid = () => ++uidCounter;

// ---- input ----
const Input = {
  keys: {}, pressed: {}, mx: 0, my: 0,
  mdown: [false, false, false],
  init(canvas) {
    addEventListener('keydown', e => {
      if (!e.repeat) this.pressed[e.code] = true;
      this.keys[e.code] = true;
      if (['Space', 'Tab'].includes(e.code)) e.preventDefault();
    });
    addEventListener('keyup', e => { this.keys[e.code] = false; });
    addEventListener('blur', () => { this.keys = {}; this.mdown = [false, false, false]; });
    addEventListener('mousemove', e => { this.mx = e.clientX; this.my = e.clientY; });
    canvas.addEventListener('mousedown', e => { this.mdown[e.button] = true; });
    addEventListener('mouseup', e => { this.mdown[e.button] = false; });
    addEventListener('contextmenu', e => e.preventDefault());
  },
  endFrame() { this.pressed = {}; },
};
