'use strict';
let last = performance.now(), saveT = 0;

function startGame(fromSave) {
  const save = fromSave ? loadSave() : null;
  if (save) applySave(save);
  else { G.player = new Player(); G.floor = 1; G.shop = null; G.atlas = newAtlas(); }
  UI.buildSkillbar();
  $('title').classList.add('hidden');
  Atlas.show();
  if (!save) showMsg('遠征図から行き先を選んで出撃しよう', '#e8d8b0');
}

function panelKeys() {
  if (Input.pressed.KeyI || Input.pressed.Tab) UI.toggle('inventory');
  if (Input.pressed.KeyT) UI.toggle('talents');
  if (Input.pressed.KeyC) UI.toggle('status');
  if (Input.pressed.KeyK) UI.toggle('skills');
  if (Input.pressed.KeyL) UI.toggle('filter');
  if (Input.pressed.KeyP) UI.toggle('apassive');
}

function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (G.state === 'play') {
    const p = G.player;
    panelKeys();
    if (Input.pressed.Escape) UI.toggle(UI.open ? UI.open : 'pause');
    if (!UI.open) updateWorld(dt);
    if (G.state === 'play') {
      render(UI.open ? 0 : dt);
      UI.update();
    }
    saveT += dt;
    if (saveT > 20 && !p.dead) { saveT = 0; saveGame(); }
  } else if (G.state === 'atlas') {
    panelKeys();
    if (Input.pressed.Escape && UI.open) UI.toggle(UI.open);
    Atlas.draw();
  }
  Input.endFrame();
  requestAnimationFrame(frame);
}

addEventListener('load', () => {
  Input.init($('game'));
  R.init();
  UI.init();
  Atlas.init();
  const save = loadSave();
  if (save) {
    $('continueBtn').classList.remove('hidden');
    $('continueBtn').textContent = `続きから（Lv ${save.level}）`;
  }
  $('continueBtn').addEventListener('click', () => startGame(true));
  $('newBtn').addEventListener('click', () => {
    if (save && !confirm('セーブデータを上書きして最初から始めますか？')) return;
    startGame(false);
  });
  $('retryBtn').addEventListener('click', () => {
    $('death').classList.add('hidden');
    const p = G.player;
    p.xp = Math.floor(p.xp * 0.7);
    spawnFloor();
    saveGame();
  });
  $('deathAtlasBtn').addEventListener('click', () => {
    G.player.xp = Math.floor(G.player.xp * 0.7);
    abandonMap();
  });
  $('abandonBtn').addEventListener('click', () => abandonMap());
  $('quitBtn').addEventListener('click', () => { saveGame(); location.reload(); });
  requestAnimationFrame(frame);
});
