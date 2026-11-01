'use strict';
const $ = id => document.getElementById(id);

const UI = {
  open: null,
  selSlot: 0,
  slotEls: [],
  init() {
    addEventListener('mousemove', e => this.moveTip(e));
    $('buyPotion').addEventListener('click', () => {
      const p = G.player, cost = potionPrice();
      if (p.cur.ember < cost || p.potions >= maxPotions()) return;
      p.cur.ember -= cost; p.potions++;
      this.refresh();
    });
    $('rerollShop').addEventListener('click', () => {
      const p = G.player, cost = rerollPrice();
      if (p.cur.ember < cost) return;
      p.cur.ember -= cost; G.shop = genShop();
      this.refresh();
    });
    this.initPortrait();
    document.querySelectorAll('[data-close]').forEach(b => b.addEventListener('click', () => this.toggle(null)));
    document.querySelectorAll('.panel [data-open]').forEach(b => b.addEventListener('click', () => this.toggle(b.dataset.open)));
  },

  toggle(name) {
    for (const n of ['inventory', 'talents', 'status', 'skills', 'shop', 'filter', 'apassive', 'pause']) $(n).classList.toggle('hidden', n !== name || this.open === name);
    this.open = this.open === name ? null : name;
    this.craftKey = null;
    this.hideTip();
    Input.mdown = [false, false, false];
    this.refresh();
  },

  update() {
    const p = G.player, s = p.s;
    const lp = p.life / s.maxLife, mp = p.mana / s.maxMana;
    $('lifeFill').style.transform = `translateY(${(1 - lp) * 100}%)`;
    $('manaFill').style.transform = `translateY(${(1 - mp) * 100}%)`;
    $('lifeText').textContent = `${Math.ceil(p.life)} / ${Math.round(s.maxLife)}`;
    $('manaText').textContent = `${Math.floor(p.mana)} / ${Math.round(s.maxMana)}`;
    $('xpFill').style.width = (p.xp / xpNeed(p.level) * 100) + '%';
    for (const se of this.slotEls) {
      const sk = SKILLS[se.id];
      const max = sk.cd * (1 - s.cdr / 100), left = Math.max(0, p.cds[se.id] || 0);
      const v = left > 0 ? (left / max).toFixed(3) : '0';
      if (se.last !== v) { se.last = v; se.cd.style.background = `conic-gradient(rgba(0,0,0,.72) ${v}turn, transparent 0)`; }
      se.el.classList.toggle('oom', p.mana < sk.mana);
    }
    const info = `${G.area ? G.area.name : ''} エリアLv ${G.floor}　Lv ${p.level}　<span class="gold">◆ ${p.cur.ember}</span>`;
    if (this.lastInfo !== info) { this.lastInfo = info; $('topinfo').innerHTML = info; }
    const pot = `回復薬 <b>${p.potions}</b> <small>[F]</small>`;
    if (this.lastPot !== pot) { this.lastPot = pot; $('potion').innerHTML = pot; }
    $('talentHint').classList.toggle('hidden', p.talentPts <= 0);
    if (G.boss && this.boss) $('bossFill').style.width = Math.max(0, G.boss.life / G.boss.maxLife * 100) + '%';
  },

  setBoss(e) {
    this.boss = e;
    $('bossbar').classList.toggle('hidden', !e);
    if (e) $('bossName').textContent = e.name;
  },

  refresh() {
    if (this.open === 'inventory') this.renderInventory();
    if (this.open === 'talents') this.renderTalents();
    if (this.open === 'status') this.renderStatus();
    if (this.open === 'skills') this.renderSkills();
    if (this.open === 'shop') this.renderShop();
    if (this.open === 'filter') this.renderFilter();
    if (this.open === 'apassive') this.renderAtlasPassives();
    if (G.state === 'atlas') Atlas.renderDetail();
  },

  buildSkillbar() {
    const bar = $('skillbar'), p = G.player;
    bar.innerHTML = '';
    this.slotEls = SKILL_SLOTS.map((slot, i) => {
      const id = p.slots[i], sk = SKILLS[id], sup = slotSup(i);
      const el = document.createElement('div');
      el.className = 'skill';
      el.style.setProperty('--c', sk.color);
      const pips = sup.ids.map(g => `<i style="background:${SUPPORT_BY_ID[g].color}"></i>`).join('');
      el.innerHTML = `<span class="icon">${sk.icon}</span><span class="cd"></span><span class="key">${slot.short}</span>` +
        `${sk.mana ? `<span class="cost">${Math.round(sk.mana * sup.mana * (sup.totem ? 2.5 : 1))}</span>` : ''}<span class="pips">${pips}</span>`;
      el.addEventListener('mouseenter', ev => this.showTip(ev, this.skillTip(id, slot.label, i)));
      el.addEventListener('mouseleave', () => this.hideTip());
      el.addEventListener('click', () => { this.selSlot = i; if (this.open !== 'skills') this.toggle('skills'); else this.refresh(); });
      bar.appendChild(el);
      return { el, cd: el.querySelector('.cd'), id, last: null };
    });
  },

  skillTip(id, keyLabel, slot = null) {
    const sk = SKILLS[id], lines = [
      { t: sk.name, c: sk.color, big: true },
      { t: SKILL_TAGS[id].map(t => TAG_NAMES[t]).join('・'), c: '#9a9080' },
      { t: (keyLabel ? keyLabel + '　' : '') + `マナ ${sk.mana}` + (sk.cd ? `　CD ${sk.cd}秒` : ''), c: '#9a9080' },
      { t: sk.desc, c: '#ddd' },
      { t: `タレントランク ${G.player.talents[id]}`, c: '#8fb4ff' },
    ];
    if (slot !== null) {
      const sup = slotSup(slot);
      if (sup.ids.length) lines.push({ sep: true }, ...sup.ids.map(g => ({ t: `◆ ${SUPPORT_BY_ID[g].name}：${SUPPORT_BY_ID[g].desc}`, c: SUPPORT_BY_ID[g].color })));
    }
    return lines;
  },

  gemTip(g) {
    return [{ t: g.name, c: g.color, big: true }, { t: 'サポートジェム', c: '#9a9080' }, { t: g.desc, c: '#ddd' },
      { t: '対象：' + g.tags.map(t => TAG_NAMES[t]).join('・') + (g.not ? `（${g.not.map(t => TAG_NAMES[t]).join('・')}を除く）` : ''), c: '#8fb4ff' }];
  },

  renderSkills() {
    const p = G.player, sockets = linkSockets(p.level);
    const row = $('slotRow');
    row.innerHTML = '';
    SKILL_SLOTS.forEach((slot, i) => {
      const id = p.slots[i], sk = SKILLS[id], links = p.links[i];
      const el = document.createElement('div');
      el.className = 'slotcard' + (i === this.selSlot ? ' sel' : '');
      el.innerHTML = `<div class="k">${slot.label}</div><div class="i" style="color:${sk.color}">${sk.icon}</div><div class="n">${sk.name}</div><div class="sockets"></div>`;
      const sockEl = el.querySelector('.sockets');
      for (let k = 0; k < LINK_MAX; k++) {
        const g = SUPPORT_BY_ID[links[k]], s = document.createElement('span');
        const locked = k >= sockets, fits = g && supportFits(g, id);
        s.className = 'sock' + (locked ? ' locked' : '') + (g ? ' full' : '') + (g && !fits ? ' bad' : '');
        if (g) s.style.background = g.color;
        s.title = locked ? `Lv ${[1, 5, 10][k]} で開放` : g ? `${g.name}（クリックで外す）${fits ? '' : '：このスキルには無効'}` : '空きソケット';
        if (g) s.addEventListener('click', ev => { ev.stopPropagation(); links.splice(k, 1); this.linksChanged(); });
        sockEl.appendChild(s);
      }
      el.addEventListener('click', () => { this.selSlot = i; this.refresh(); });
      row.appendChild(el);
    });

    const pool = $('skillPool');
    pool.innerHTML = '';
    for (const id of SKILL_LIST) {
      const sk = SKILLS[id], locked = p.level < sk.lvl, at = p.slots.indexOf(id);
      const el = document.createElement('div');
      el.className = 'skillcard' + (locked ? ' locked' : '') + (at >= 0 ? ' inuse' : '');
      const tag = locked ? `Lv ${sk.lvl} で習得` : at >= 0 ? `装備中：${SKILL_SLOTS[at].label}` : '';
      el.innerHTML = `<div class="i" style="color:${sk.color}">${sk.icon}</div>
        <div class="n"><span style="color:${sk.color}">${sk.name}</span><span class="tag">${tag}</span></div>
        <div class="m">マナ ${sk.mana}${sk.cd ? `　CD ${sk.cd}秒` : ''}　${SKILL_TAGS[id].map(t => TAG_NAMES[t]).join('・')}</div>
        <div class="d">${sk.desc}</div>`;
      if (!locked) el.addEventListener('click', () => {
        const sel = this.selSlot;
        if (at >= 0) { [p.slots[at], p.slots[sel]] = [p.slots[sel], p.slots[at]]; [p.links[at], p.links[sel]] = [p.links[sel], p.links[at]]; }
        else p.slots[sel] = id;
        this.linksChanged();
      });
      pool.appendChild(el);
    }

    const gems = $('gemPool'), selId = p.slots[this.selSlot], selLinks = p.links[this.selSlot];
    $('gemHint').textContent = `「${SKILLS[selId].name}」に${sockets}個までリンクできます（Lv5・Lv10でソケット追加）`;
    gems.innerHTML = '';
    for (const g of SUPPORTS) {
      const owned = p.gems.includes(g.id), fits = supportFits(g, selId), linked = selLinks.includes(g.id);
      const el = document.createElement('div');
      el.className = 'gemcard' + (owned ? '' : ' locked') + (owned && !fits ? ' nofit' : '') + (linked ? ' linked' : '');
      el.style.setProperty('--c', g.color);
      el.innerHTML = `<div class="gn"><span>◇ ${g.name}</span><span class="tag">${!owned ? '未入手' : linked ? 'リンク中' : fits ? '' : '対象外'}</span></div><div class="d">${g.desc}</div>`;
      el.addEventListener('mouseenter', ev => this.showTip(ev, this.gemTip(g)));
      el.addEventListener('mouseleave', () => this.hideTip());
      el.addEventListener('click', () => {
        if (!owned) return;
        if (linked) { selLinks.splice(selLinks.indexOf(g.id), 1); this.linksChanged(); return; }
        if (!fits) return showMsg(`${g.name}は「${SKILLS[selId].name}」に使えない`, '#ff8080');
        if (selLinks.length >= sockets) return showMsg('空きソケットがない', '#ff8080');
        selLinks.push(g.id);
        this.linksChanged();
      });
      gems.appendChild(el);
    }
  },
  linksChanged() {
    this.buildSkillbar();
    saveGame();
    this.refresh();
  },

  renderShop() {
    const p = G.player;
    $('shopGold').textContent = `◆ ${p.cur.ember}`;
    const stock = $('shopStock');
    stock.innerHTML = '';
    for (const it of G.shop.items) {
      const cost = buyPrice(it);
      const wrap = document.createElement('div');
      wrap.className = 'stockitem';
      const el = this.itemEl(it, () => {
        if (p.cur.ember < cost) return showMsg('灰燼の欠片が足りない', '#ff8080');
        if (p.bag.length >= BAG_SIZE) return showMsg('インベントリが一杯です', '#ff8080');
        p.cur.ember -= cost;
        G.shop.items.splice(G.shop.items.indexOf(it), 1);
        p.bag.push(it);
        showMsg(`${it.name} を購入（${cost} 灰燼の欠片）`, RARITY[it.rarity].color);
        this.hideTip(); this.refresh();
      });
      el.addEventListener('mouseenter', ev => this.showTip(ev, [...this.itemTip(it, true), { sep: true }, { t: `価格 ${cost} 灰燼の欠片`, c: '#ffcf3a' }]));
      wrap.appendChild(el);
      const price = document.createElement('div');
      price.className = 'price' + (p.cur.ember < cost ? ' no' : '');
      price.textContent = `◆ ${cost}`;
      wrap.appendChild(price);
      stock.appendChild(wrap);
    }
    const pp = potionPrice(), rp = rerollPrice();
    $('buyPotion').textContent = `回復薬を買う（◆ ${pp}）　所持 ${p.potions}/${maxPotions()}`;
    $('buyPotion').disabled = p.cur.ember < pp || p.potions >= maxPotions();
    $('rerollShop').textContent = `品揃えを入れ替える（◆ ${rp}）`;
    $('rerollShop').disabled = p.cur.ember < rp;
    const bag = $('shopBag');
    bag.innerHTML = '';
    for (let i = 0; i < BAG_SIZE; i++) {
      const it = p.bag[i];
      if (!it) { const e = document.createElement('div'); e.className = 'slot empty'; bag.appendChild(e); continue; }
      const el = this.itemEl(it, () => this.sellItem(it));
      el.addEventListener('mouseenter', ev => this.showTip(ev, [...this.itemTip(it), { sep: true }, { t: `売却額 ${sellPrice(it)} 灰燼の欠片`, c: '#ffcf3a' }]));
      bag.appendChild(el);
    }
    $('shopBagCount').textContent = `${p.bag.length} / ${BAG_SIZE}`;
    this.renderBulk($('shopBulk'));
    const ex = $('shopCurrency');
    ex.innerHTML = '';
    for (const c of DROP_CURRENCIES) {
      const cost = currencyPrice(c), b = document.createElement('button');
      b.className = 'sbtn';
      b.disabled = p.cur.ember < cost;
      b.innerHTML = `<span style="color:${c.color}">${c.icon}</span> ${c.name} <span style="float:right;color:#ffb35a">◆${cost}</span>`;
      b.addEventListener('mouseenter', ev => this.showTip(ev, [{ t: c.name, c: c.color, big: true }, { t: c.desc, c: '#ddd' }, { t: `所持数 ${p.cur[c.k]}`, c: '#9a9080' }]));
      b.addEventListener('mouseleave', () => this.hideTip());
      b.addEventListener('click', () => {
        if (p.cur.ember < cost) return;
        p.cur.ember -= cost; p.cur[c.k]++;
        this.refresh();
      });
      ex.appendChild(b);
    }
    const gs = $('shopGems');
    gs.innerHTML = '';
    const missing = SUPPORTS.filter(g => !p.gems.includes(g.id));
    if (!missing.length) gs.innerHTML = '<div class="hint2">すべて入手済み</div>';
    for (const g of missing) {
      const cost = Math.round(300 * discount()), b = document.createElement('button');
      b.className = 'sbtn'; b.disabled = p.cur.ember < cost;
      b.innerHTML = `<span style="color:${g.color}">◇</span> ${g.name} <span style="float:right;color:#ffb35a">◆${cost}</span>`;
      b.addEventListener('mouseenter', ev => this.showTip(ev, this.gemTip(g)));
      b.addEventListener('mouseleave', () => this.hideTip());
      b.addEventListener('click', () => { if (p.cur.ember < cost) return; p.cur.ember -= cost; unlockGem(g.id); this.hideTip(); this.refresh(); });
      gs.appendChild(b);
    }
  },

  bulkRarity: 0,
  renderBulk(el) {
    const p = G.player, max = this.bulkRarity;
    const items = p.bag.filter(it => it.rarity <= max);
    const total = items.reduce((s, it) => s + sellPrice(it), 0);
    el.innerHTML = `<select>${RARITY.map((r, i) =>
      `<option value="${i}" style="color:${r.color}"${i === max ? ' selected' : ''}>${r.name}以下</option>`).join('')}</select>
      <button class="sbtn"${items.length ? '' : ' disabled'}>一括売却（${items.length}点 / ◆ ${total}）</button>`;
    const sel = el.querySelector('select');
    sel.style.color = RARITY[max].color;
    sel.addEventListener('change', () => { this.bulkRarity = +sel.value; this.refresh(); });
    el.querySelector('button').addEventListener('click', () => {
      if (!items.length) return;
      if (items.some(it => it.rarity === 3) && !confirm(`レジェンドを含む ${items.length} 点を売却します。よろしいですか？`)) return;
      p.bag = p.bag.filter(it => it.rarity > max);
      p.cur.ember += total;
      showMsg(`${RARITY[max].name}以下の ${items.length} 点を売却（${total} 灰燼の欠片）`, '#ffcf3a');
      this.hideTip(); this.refresh();
    });
  },

  renderFilter() {
    const f = G.player.filter;
    const opts = [['pick', '拾う'], ['sell', '拾って売却'], ['hide', '非表示（即売却）']];
    const rows = $('filterRarity');
    rows.innerHTML = '';
    RARITY.forEach((r, i) => {
      const row = document.createElement('div');
      row.className = 'frow';
      row.innerHTML = `<div style="color:${r.color}">${r.name}</div><div class="seg">${opts.map(([v, label]) =>
        `<button data-v="${v}" class="${f.rarity[i] === v ? 'on' : ''} ${v}">${label}</button>`).join('')}</div>`;
      row.querySelectorAll('button').forEach(b => b.addEventListener('click', () => {
        const v = b.dataset.v;
        if (i === 3 && v !== 'pick' && !confirm('レジェンドも自動で売却されるようになります。よろしいですか？')) return;
        f.rarity[i] = v;
        this.filterChanged();
      }));
      rows.appendChild(row);
    });
    const slots = $('filterSlots');
    slots.innerHTML = SLOTS.map(s => `<label><input type="checkbox" data-s="${s}"${f.slots[s] ? ' checked' : ''}>${SLOT_INFO[s].name}</label>`).join('');
    slots.querySelectorAll('input').forEach(cb => cb.addEventListener('change', () => {
      f.slots[cb.dataset.s] = cb.checked;
      this.filterChanged();
    }));
  },
  renderAtlasPassives() {
    const p = G.player, free = apFree(), rp = apResetPrice();
    $('apPoints').innerHTML = `残りポイント <b>${free}</b>　／　獲得合計 ${apTotal()}`;
    const reset = $('apReset');
    reset.textContent = `振り直す（◆ ${rp}）`;
    reset.disabled = !apSpent() || p.cur.ember < rp;
    reset.onclick = () => {
      if (!apSpent() || p.cur.ember < rp || !confirm('アトラスパッシブをすべて振り直しますか？')) return;
      p.cur.ember -= rp; G.atlas.passives = {};
      p.recalc(); saveGame(); this.refresh();
    };
    const tree = $('apTree');
    tree.innerHTML = '';
    for (const b of ATLAS_PASSIVES) {
      const col = document.createElement('div');
      col.className = 'ap-col';
      col.innerHTML = `<h3 style="color:${b.color}">${b.branch}</h3>`;
      for (const n of b.nodes) {
        const r = apRank(n.id), unlocked = apUnlocked(n.id);
        const el = document.createElement('div');
        el.className = 'ap-node' + (unlocked ? '' : ' locked') + (r ? ' has' : '') + (r >= n.max ? ' maxed' : '');
        el.style.setProperty('--c', b.color);
        if (r) el.style.setProperty('--lc', b.color);
        const cur = n.fmt.replace('{v}', r * n.per), next = n.fmt.replace('{v}', Math.min(n.max, r + 1) * n.per);
        el.innerHTML = `<div class="nm"><span>${n.name}</span><span class="rk">${r} / ${n.max}</span></div>
          <div class="ds">${r ? cur : n.fmt.replace('{v}', n.per)}${r && r < n.max ? `<br>次：${next}` : ''}</div>`;
        el.addEventListener('click', () => {
          if (!unlocked || r >= n.max || apFree() <= 0) return;
          G.atlas.passives[n.id] = r + 1;
          p.recalc(); saveGame(); this.refresh();
        });
        col.appendChild(el);
      }
      tree.appendChild(col);
    }
  },

  filterChanged() {
    if (G.state === 'play') sellHiddenGround();
    saveGame();
    this.refresh();
  },

  sellItem(it) {
    const p = G.player, g = sellPrice(it);
    p.bag.splice(p.bag.indexOf(it), 1);
    p.cur.ember += g;
    showMsg(`${it.name} を売却（${g} 灰燼の欠片）`, '#ffcf3a');
    this.hideTip(); this.refresh();
  },

  statRows() {
    const s = G.player.s;
    return [
      ['ダメージ', `${Math.round(s.dmgMin)}–${Math.round(s.dmgMax)}`], ['攻撃/秒', s.attackRate.toFixed(2)],
      ['ダメージ増加', s.incDmg + '%'], ['スキルダメージ', s.spellDmg + '%'],
      ['クリティカル', `${s.crit.toFixed(1)}% / ${s.critMulti}%`], ['詠唱速度', '+' + s.castSpd + '%'],
      ['火炎/冷気/雷', `${s.fireDmg}/${s.coldDmg}/${s.lightDmg}%`], ['アーマー', `${s.armor}（軽減 ${Math.round(s.dr * 100)}%）`],
      ['移動速度', '+' + s.moveSpd + '%'], ['クールダウン短縮', s.cdr + '%'],
      ['ライフ回復', s.lifeRegen.toFixed(1) + '/秒'], ['マナ回復', s.manaRegen.toFixed(1) + '/秒'],
    ];
  },

  renderStatus() {
    const p = G.player, s = p.s;
    const row = ([k, v]) => `<div><span>${k}</span><b>${v}</b></div>`;
    $('charLevel').textContent = `レベル ${p.level}　・　踏破 ${G.atlas.cleared.length}/${ATLAS_NODES.length}`;
    $('charXp').style.width = (p.xp / xpNeed(p.level) * 100) + '%';
    $('charXpText').textContent = `経験値 ${p.xp} / ${xpNeed(p.level)}`;
    $('charRes').innerHTML = `<div style="color:#ff7a6a">ライフ<b>${Math.ceil(p.life)}/${Math.round(s.maxLife)}</b></div>
      <div style="color:#7aa8ff">マナ<b>${Math.floor(p.mana)}/${Math.round(s.maxMana)}</b></div>
      <div style="color:#ffb35a">灰燼の欠片<b>${p.cur.ember}</b></div>`;
    const rows = this.statRows();
    $('charStats').innerHTML = '<div class="grp">攻撃</div>' + rows.slice(0, 7).map(row).join('') +
      '<div class="grp">防御・その他</div>' + rows.slice(7).map(row).join('') +
      row(['タレントポイント', p.talentPts]);
    $('charEquip').innerHTML = SLOTS.map(slot => {
      const it = p.equip[slot];
      return `<div><span>${SLOT_INFO[slot].name}</span><b style="color:${it ? RARITY[it.rarity].color : '#554a3a'}">${it ? it.name : '—'}</b></div>`;
    }).join('');
    $('charSkills').innerHTML = SKILL_SLOTS.map((slot, i) => {
      const id = p.slots[i], sk = SKILLS[id], r = p.talents[id];
      return `<div><span>${slot.short}　<span style="color:${sk.color}">${sk.icon}</span> ${sk.name}</span><b>ランク ${r}（+${r * 15}%）</b></div>`;
    }).join('');
  },

  initPortrait() {
    this.drawPortrait($('portraitCanvas'));
    // a custom portrait can be dropped in at assets/portrait.png
    const img = $('portraitImg');
    img.onload = () => { img.classList.remove('hidden'); $('portraitCanvas').classList.add('hidden'); };
    img.src = 'assets/portrait.png';
  },

  drawPortrait(c) {
    const ctx = c.getContext('2d'), W = c.width, H = c.height;
    const bg = ctx.createRadialGradient(W * 0.5, H * 0.55, 10, W * 0.5, H * 0.5, H * 0.75);
    bg.addColorStop(0, '#5a2a10'); bg.addColorStop(0.45, '#22100a'); bg.addColorStop(1, '#060406');
    ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H);
    // embers
    for (let i = 0; i < 70; i++) {
      const x = Math.random() * W, y = Math.random() * H, r = Math.random() * 2 + 0.5;
      ctx.fillStyle = `rgba(255,${120 + Math.random() * 100 | 0},40,${Math.random() * 0.7 + 0.2})`;
      ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill();
    }
    const cx = W / 2;
    // cape and shoulders
    ctx.fillStyle = '#120b0a';
    ctx.beginPath();
    ctx.moveTo(cx - 105, H); ctx.quadraticCurveTo(cx - 95, 190, cx - 40, 165);
    ctx.lineTo(cx + 40, 165); ctx.quadraticCurveTo(cx + 95, 190, cx + 105, H); ctx.fill();
    // hood
    ctx.beginPath();
    ctx.moveTo(cx - 52, 175); ctx.quadraticCurveTo(cx - 62, 70, cx, 58);
    ctx.quadraticCurveTo(cx + 62, 70, cx + 52, 175); ctx.closePath(); ctx.fill();
    // rim light
    ctx.strokeStyle = 'rgba(255,150,60,0.55)'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(cx + 52, 175); ctx.quadraticCurveTo(cx + 62, 70, cx, 58); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(cx + 40, 165); ctx.quadraticCurveTo(cx + 95, 190, cx + 105, H); ctx.stroke();
    // face shadow and eyes
    ctx.fillStyle = '#050304';
    ctx.beginPath(); ctx.ellipse(cx, 125, 30, 38, 0, 0, TAU); ctx.fill();
    for (const s of [-1, 1]) {
      const g = ctx.createRadialGradient(cx + s * 12, 120, 0, cx + s * 12, 120, 9);
      g.addColorStop(0, 'rgba(255,220,140,1)'); g.addColorStop(1, 'rgba(255,120,30,0)');
      ctx.fillStyle = g; ctx.fillRect(cx + s * 12 - 9, 111, 18, 18);
    }
    // sword hilt over the shoulder
    ctx.strokeStyle = '#8a8a96'; ctx.lineWidth = 5; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(cx - 70, 150); ctx.lineTo(cx - 100, 40); ctx.stroke();
    ctx.strokeStyle = '#6a4a22'; ctx.lineWidth = 9;
    ctx.beginPath(); ctx.moveTo(cx - 64, 172); ctx.lineTo(cx - 70, 150); ctx.stroke();
    ctx.strokeStyle = '#b08a40'; ctx.lineWidth = 4;
    ctx.beginPath(); ctx.moveTo(cx - 84, 154); ctx.lineTo(cx - 56, 146); ctx.stroke();
    // torch glow from below
    const tg = ctx.createRadialGradient(cx + 60, H, 0, cx + 60, H, 160);
    tg.addColorStop(0, 'rgba(255,140,40,0.45)'); tg.addColorStop(1, 'rgba(255,140,40,0)');
    ctx.fillStyle = tg; ctx.fillRect(0, 0, W, H);
  },

  itemEl(it, onClick, onRight) {
    const el = document.createElement('div');
    el.className = 'slot item r' + it.rarity;
    el.textContent = SLOT_INFO[it.slot].glyph;
    el.addEventListener('mouseenter', ev => this.showTip(ev, this.itemTip(it)));
    el.addEventListener('mouseleave', () => this.hideTip());
    el.addEventListener('click', ev => {
      if (this.craftKey && this.open === 'inventory') this.applyCraft(it, ev);
      else onClick(ev);
    });
    el.addEventListener('contextmenu', e => {
      e.preventDefault();
      if (this.craftKey) { this.craftKey = null; this.refresh(); }
      else if (onRight) onRight();
    });
    return el;
  },

  // ---- crafting ----
  craftKey: null,
  renderCurrencyBar() {
    const p = G.player, bar = $('currencyBar');
    bar.innerHTML = '';
    for (const c of CURRENCIES) {
      const n = p.cur[c.k] || 0, craft = !!CRAFT[c.k];
      const el = document.createElement('div');
      el.className = 'curcell' + (craft ? ' craft' : '') + (this.craftKey === c.k ? ' active' : '') + (n ? '' : ' empty');
      el.innerHTML = `<span class="ci" style="color:${c.color}">${c.icon}</span><b>${n}</b>`;
      el.addEventListener('mouseenter', ev => this.showTip(ev, [{ t: c.name, c: c.color, big: true }, { t: c.desc, c: '#ddd' }, { t: `所持数 ${n}`, c: '#9a9080' },
        ...(craft ? [{ t: 'クリックで使用 → 対象アイテムをクリック', c: '#8fb4ff' }] : [])]));
      el.addEventListener('mouseleave', () => this.hideTip());
      if (craft) el.addEventListener('click', () => {
        if (!n) return showMsg(`${c.name}を持っていない`, '#ff8080');
        this.craftKey = this.craftKey === c.k ? null : c.k;
        this.refresh();
      });
      bar.appendChild(el);
    }
    const banner = $('craftBanner');
    banner.classList.toggle('hidden', !this.craftKey);
    $('inventory').classList.toggle('crafting', !!this.craftKey);
    if (this.craftKey) {
      const c = CUR_BY_KEY[this.craftKey];
      banner.innerHTML = `<span style="color:${c.color}">${c.icon} ${c.name}</span> を使用中（残り ${p.cur[c.k]}）：アイテムをクリック。右クリックで解除`;
    }
  },
  applyCraft(it, ev) {
    const p = G.player, k = this.craftKey, c = CUR_BY_KEY[k];
    if (!p.cur[k]) { this.craftKey = null; this.refresh(); return; }
    const err = CRAFT[k](it);
    if (err) { showMsg(err, '#ff8080'); return; }
    p.cur[k]--;
    burstUI(ev, c.color);
    if (Object.values(p.equip).includes(it)) p.recalc();
    if (!p.cur[k]) this.craftKey = null;
    this.refresh();
    this.showTip(ev, this.itemTip(it));
  },

  itemTip(it, compare = G.player.bag.includes(it)) {
    const lines = itemLines(it);
    const p = G.player;
    const cur = p.equip[it.slot];
    if (cur && cur !== it && compare) {
      lines.push({ sep: true }, { t: '— 装備中 —', c: '#7a7266' }, ...itemLines(cur).slice(0, 1), ...itemLines(cur).slice(3));
    }
    return lines;
  },

  renderInventory() {
    const p = G.player;
    const eq = $('equip');
    eq.innerHTML = '';
    for (const slot of SLOTS) {
      const wrap = document.createElement('div');
      wrap.className = 'eqslot eq-' + slot;
      const it = p.equip[slot];
      if (it) wrap.appendChild(this.itemEl(it, () => {
        if (p.bag.length >= BAG_SIZE) return showMsg('インベントリが一杯です', '#ff8080');
        delete p.equip[slot]; p.bag.push(it); p.recalc(); this.hideTip(); this.refresh();
      }));
      else { const e = document.createElement('div'); e.className = 'slot empty'; e.textContent = SLOT_INFO[slot].name; wrap.appendChild(e); }
      eq.appendChild(wrap);
    }
    const bag = $('bag');
    bag.innerHTML = '';
    for (let i = 0; i < BAG_SIZE; i++) {
      const it = p.bag[i];
      if (!it) { const e = document.createElement('div'); e.className = 'slot empty'; bag.appendChild(e); continue; }
      bag.appendChild(this.itemEl(it, () => {
        const old = p.equip[it.slot];
        p.equip[it.slot] = it;
        p.bag.splice(p.bag.indexOf(it), 1);
        if (old) p.bag.push(old);
        p.recalc(); this.hideTip(); this.refresh();
      }, () => this.sellItem(it)));
    }
    $('stats').innerHTML = this.statRows().map(([k, v]) => `<div><span>${k}</span><b>${v}</b></div>`).join('');
    $('bagCount').textContent = `${p.bag.length} / ${BAG_SIZE}`;
    this.renderBulk($('invBulk'));
    this.renderCurrencyBar();
  },

  renderTalents() {
    const p = G.player, list = $('talentList');
    $('talentPts').textContent = p.talentPts;
    list.innerHTML = '';
    let lastSkill = false;
    for (const t of TALENTS) {
      if (t.skill && !lastSkill) { const h = document.createElement('h3'); h.textContent = 'スキル強化'; list.appendChild(h); }
      lastSkill = !!t.skill;
      const r = p.talents[t.k];
      const row = document.createElement('div');
      row.className = 'talent';
      row.innerHTML = `<div class="tname">${t.skill ? `<span style="color:${SKILLS[t.k].color}">${SKILLS[t.k].icon}</span> ` : ''}${t.name}</div>
        <div class="tdesc">${t.desc}</div><div class="trank">${r} / ${t.max}</div>`;
      const btn = document.createElement('button');
      btn.textContent = '+';
      btn.disabled = p.talentPts <= 0 || r >= t.max;
      btn.addEventListener('click', () => { p.talentPts--; p.talents[t.k]++; p.recalc(); this.refresh(); });
      row.appendChild(btn);
      list.appendChild(row);
    }
  },

  showTip(ev, lines) {
    const tip = $('tooltip');
    tip.innerHTML = lines.map(l => l.sep ? '<hr>' : `<div style="color:${l.c}" class="${l.big ? 'big' : ''}">${l.t}</div>`).join('');
    tip.classList.remove('hidden');
    this.moveTip(ev);
  },
  moveTip(ev) {
    const tip = $('tooltip');
    if (tip.classList.contains('hidden')) return;
    const w = tip.offsetWidth, h = tip.offsetHeight;
    let x = ev.clientX + 18, y = ev.clientY + 18;
    if (x + w > innerWidth - 8) x = ev.clientX - w - 18;
    if (y + h > innerHeight - 8) y = innerHeight - h - 8;
    tip.style.left = Math.max(8, x) + 'px'; tip.style.top = Math.max(8, y) + 'px';
  },
  hideTip() { $('tooltip').classList.add('hidden'); },

  showDeath() {
    $('death').classList.remove('hidden');
  },
};

// a small sparkle where a currency was applied
function burstUI(ev, color) {
  for (let i = 0; i < 10; i++) {
    const s = document.createElement('div'), a = Math.random() * TAU, d = 20 + Math.random() * 25;
    s.style.cssText = `position:fixed;z-index:60;left:${ev.clientX}px;top:${ev.clientY}px;width:5px;height:5px;border-radius:50%;
      background:${color};box-shadow:0 0 6px ${color};pointer-events:none;transition:transform .45s ease-out,opacity .45s;`;
    document.body.appendChild(s);
    requestAnimationFrame(() => { s.style.transform = `translate(${Math.cos(a) * d}px,${Math.sin(a) * d}px)`; s.style.opacity = '0'; });
    setTimeout(() => s.remove(), 500);
  }
}

function showMsg(text, color = '#eee') {
  const box = $('messages');
  const el = document.createElement('div');
  el.className = 'msg'; el.textContent = text; el.style.color = color;
  box.appendChild(el);
  while (box.children.length > 5) box.firstChild.remove();
  setTimeout(() => el.classList.add('fade'), 2600);
  setTimeout(() => el.remove(), 3400);
}
