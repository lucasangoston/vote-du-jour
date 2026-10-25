// Génère les maquettes HTML statiques de Perchoir (phase 1) à partir des données réelles
// (data/latest.json, data/<numero>.json). Une page par écran et par thème.
//   node build.mjs   → screens/*.html
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const read = (f) => JSON.parse(readFileSync(join(root, 'data', f), 'utf8'));
const latest = read('latest.json');
const details = { 8706: read('8706.json'), 8610: read('8610.json') };
const out = join(root, 'screens');
mkdirSync(out, { recursive: true });

// ---------- données ----------
const TODAY = new Date('2026-10-23T12:00:00+02:00');
const MONTHS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
const MONTHS_SHORT = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const DAYS = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];
const parisDate = (iso) => new Date(new Date(iso).toLocaleString('en-US', { timeZone: 'Europe/Paris' }));
const day = (s) => new Date(s + 'T12:00:00');
const cap = (s) => s[0].toUpperCase() + s.slice(1);
const longDate = (d) => `${DAYS[d.getDay()]} ${d.getDate() === 1 ? '1er' : d.getDate()} ${MONTHS[d.getMonth()]}`;
const shortDate = (d) => `${d.getDate()} ${MONTHS_SHORT[d.getMonth()]}`;
const nb = (n) => n.toLocaleString('fr-FR').replace(/ /g, ' ');
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const typo = (s) => esc(s).replace(/'/g, '’');

// Ordre des groupes dans l'hémicycle, de gauche à droite (vu du perchoir). Cohérent avec le champ
// `arc` publié (8706 : 66 abst. LFI, 382 pour, 1 abst. UDR, 121 pour RN ; 8610 : 187 contre de LFI
// à HOR, 151 pour de DR à RN).
const SEATING = ['LFI-NFP', 'GDR', 'EcoS', 'SOC', 'LIOT', 'Dem', 'EPR', 'HOR', 'DR', 'NI', 'UDR', 'RN'];
const LOGOS = { RN: 'rn', EPR: 'epr', 'LFI-NFP': 'lfi', SOC: 'soc', DR: 'dr', EcoS: 'ecos', Dem: 'dem', HOR: 'hor', LIOT: 'liot', GDR: 'gdr', UDR: 'udr' };
const POS = { pour: 'pour', contre: 'contre', abstention: 'abst' };
const RESULT = { adopte: 'Adopté', rejete: 'Rejeté' };
const TYPE_LABEL = {
  resolution: 'Résolution, sans valeur de loi',
  motion_de_censure: 'Motion de censure',
  rejet_prealable: 'Motion de rejet préalable',
  ensemble: null,
};
// Titres courts (≤ 35 car., deux lignes d'un petit widget). Échantillons : le backend devra les produire.
const SHORT = { 8706: 'Juges des violences sexuelles', 8610: 'Achats publics : priorité nationale', plf: 'Budget de l’État 2027', plfss: 'Sécurité sociale 2027' };
const shortTitle = (d) => SHORT[d.numero] || d.summary?.title || d.shortTitle;

// Séquence des sièges d'une décision détaillée : groupe par groupe dans l'ordre de l'hémicycle,
// la position majoritaire du groupe d'abord. Vérifiée contre le champ `arc` publié.
function seatSequence(detail) {
  const seq = [];
  for (const abbr of SEATING) {
    const g = detail.groups.find((x) => x.abbreviation === abbr);
    if (!g) continue;
    const parts = [['pour', g.count.pour], ['abstention', g.count.abstentions], ['contre', g.count.contre]].filter((p) => p[1] > 0);
    parts.sort((a, b) => b[1] - a[1]);
    for (const [pos, n] of parts) for (let i = 0; i < n; i++) seq.push({ pos, g: abbr });
  }
  const runs = [];
  for (const s of seq) { const last = runs.at(-1); if (last && last.position === s.pos) last.n++; else runs.push({ position: s.pos, n: 1 }); }
  const arc = detail.decision.arc;
  console.assert(JSON.stringify(runs) === JSON.stringify(arc), `séquence ≠ arc publié pour ${detail.decision.numero}: ${JSON.stringify(runs)} vs ${JSON.stringify(arc)}`);
  return seq;
}
const seqFromArc = (arc) => arc.flatMap((s) => Array.from({ length: s.n }, () => ({ pos: s.position })));

// Nature du texte, lue dans l'intitulé officiel (« la proposition de loi organique visant… »).
function textKind(t = '') {
  const m = t.match(/^(?:le |la |l['’])?(projet de loi organique|proposition de loi organique|projet de loi constitutionnelle|proposition de loi constitutionnelle|projet de loi|proposition de loi)/i);
  return m ? cap(m[1]) : null;
}

// ---------- hémicycle réel ----------
// Géométrie : plan SVG de l'hémicycle du site de l'Assemblée (assemblee-nationale.fr/dyn/vos-deputes/hemicycle),
// un chemin p<N> par place, centres relevés dans Chrome (data/an-seats.json, échelle 0.28 du plan).
// Places et votes : archive AMO (placeHemicycle) et Scrutins.json (decompteNominatif, numPlace) → data/seats.json.
const AN_SEATS = read('an-seats.json');
const SEATS = read('seats.json');
const VOTE_POS = { pour: 'pour', contre: 'contre', abst: 'abst', nv: 'nv', absent: 'absent' };
function checkSeats(num) {
  const S = SEATS[num], D = details[num];
  const byG = {}; S.seats.forEach((x) => { byG[x.g] = (byG[x.g] || 0) + 1; });
  for (const [g, n] of Object.entries(S.sizes)) console.assert(byG[g] === n, `${num} ${g}: ${byG[g]} sièges ≠ effectif ${n}`);
  console.assert(S.seats.length === Object.values(S.sizes).reduce((a, b) => a + b, 0), `${num} total`);
  const k = (v) => S.seats.filter((x) => x.v === v).length;
  console.assert(k('pour') === D.count.pour && k('contre') === D.count.contre && k('abst') === D.count.abstentions, `${num} formes ≠ décompte`);
  const xs = S.seats.map((x) => ({ g: x.g, x: AN_SEATS[x.place].x })).sort((a, b) => a.x - b.x);
  console.assert(xs[0].g === 'LFI-NFP' && xs.at(-1).g === 'RN', `${num} extrémités ${xs[0].g} / ${xs.at(-1).g}`);
  return { voters: k('pour') + k('contre') + k('abst'), nv: k('nv'), absent: k('absent'), seats: S.seats.length };
}
function realHemi(num, { label = '', id = 'h', labels = false } = {}) {
  const S = SEATS[num];
  const R0 = 2.15, SW = 1.05;
  const VB = labels ? { x: -30, y: -30, w: 297, h: 168 } : { x: 4, y: 3, w: 229, h: 128 };
  // Dôme, vu du perchoir : LFI-NFP à l'extrême gauche, RN à l'extrême droite.
  const fy = (y) => y;
  const circles = S.seats.map((x) => {
    const p = AN_SEATS[x.place];
    const v = x.v;
    const r = v === 'contre' ? R0 - SW / 2 : v === 'abst' ? R0 * 0.5 : R0;
    const cls = v === 'nv' || v === 'absent' ? 'seat s-off' : `seat s-${v}`;
    return `<circle cx="${p.x}" cy="${fy(p.y)}" r="${r.toFixed(2)}" class="${cls}"${v === 'contre' ? ` stroke-width="${SW}"` : ''} data-g="${x.g}"/>`;
  }).join('');
  let extra = '';
  if (labels) {
    const cx = 118.3, cy = 128;
    const groups = {};
    S.seats.forEach((x) => { const p = AN_SEATS[x.place]; const a = Math.atan2(cy - p.y, p.x - cx); (groups[x.g] ||= []).push(a); });
    const placed = [];
    for (const [g, as] of Object.entries(groups)) {
      if (g === 'NI') continue;
      as.sort((a, b) => a - b); const am = as[Math.floor(as.length / 2)];
      const lab = g === 'LFI-NFP' ? 'LFI' : g;
      let r = 136, x, y, box;
      for (let t = 0; t < 5; t++) { x = cx + (r + t * 12) * Math.cos(am); y = cy - (r + t * 12) * Math.sin(am); x = Math.max(VB.x + lab.length * 3.6 + 1, Math.min(VB.x + VB.w - lab.length * 3.6 - 1, x)); box = { x: x - lab.length * 3.6, y: y - 6, w: lab.length * 7.2, h: 12 }; if (!placed.some((q) => box.x < q.x + q.w + 1 && q.x < box.x + box.w + 1 && box.y < q.y + q.h + 1 && q.y < box.y + box.h + 1)) break; }
      placed.push(box);
      extra += `<text x="${x.toFixed(1)}" y="${(fy(y) + 4).toFixed(1)}" text-anchor="middle" class="ltext glogo" data-g="${g}"><title>${GROUP_NAMES[g] || g}</title>${lab}</text>`;
    }
  }
  return `<svg class="hemi real" id="${id}" viewBox="${VB.x} ${VB.y} ${VB.w} ${VB.h}" role="img" aria-label="${esc(label)}">${extra}${circles}</svg>`;
}

// ---------- dessins ----------
// Hémicycle en sièges : N sièges répartis en rangées concentriques, attribués de gauche à droite
// par angle (comme les groupes occupent des secteurs), la rangée intérieure laissant un creux.
// Couleurs officielles des groupes : champ `couleurAssociee` des organes GP de l'archive AMO de l'Assemblée
// (AMO10_deputes_actifs_mandats_actifs_organes, 17e législature, relevée le 23 octobre 2026).
const GROUP_COLORS = { 'LFI-NFP': '#C00D0D', GDR: '#830E21', EcoS: '#77AA79', SOC: '#F5B4CE', LIOT: '#FFD96F', Dem: '#F07E26', EPR: '#7B4591', HOR: '#B5E2F9', DR: '#8CB0DC', NI: '#8D949A', UDR: '#3367A7', RN: '#313567' };
const GROUP_NAMES = { NI: 'Non inscrits' };

// Hémicycle en sièges : N sièges répartis en rangées concentriques, attribués de gauche à droite
// par angle (comme les groupes occupent des secteurs), la rangée intérieure laissant un creux.
// `band` : un anneau extérieur segmenté aux couleurs officielles des groupes ; `logos` : le logo de
// chaque groupe posé dehors, au milieu de son secteur (rangs décalés quand deux logos se touchent).
function hemicycle(seq, { R = 150, inner = 0.44, label = '', id = 'h', band = false, logos = false } = {}) {
  const N = seq.length;
  const r0 = R * inner;
  let rows, s;
  for (rows = 3; rows < 30; rows++) {
    s = (R - r0) / (rows - 1);
    let capacity = 0;
    for (let i = 0; i < rows; i++) capacity += Math.floor((Math.PI * (r0 + s * i)) / s) + 1;
    if (capacity >= N * 1.02) break;
  }
  const radii = Array.from({ length: rows }, (_, i) => r0 + s * i);
  const total = radii.reduce((a, b) => a + b, 0);
  const counts = radii.map((r) => Math.floor((N * r) / total));
  let left = N - counts.reduce((a, b) => a + b, 0);
  const rema = radii.map((r, i) => [(N * r) / total - counts[i], i]).sort((a, b) => b[0] - a[0]);
  for (let k = 0; k < left; k++) counts[rema[k][1]]++;
  const BAND_GAP = 7, BAND_W = 7, TILE_H = 20; const short = (g) => (g === 'LFI-NFP' ? 'LFI' : g); const tileW = (g) => short(g).length * 9 + 8; const TILE_W = 40;
  const outer = R + s * 0.5 + (band ? BAND_GAP + BAND_W : 0);
  const padX = (logos ? 44 : 0) + s * 0.5 + 2 + (band ? BAND_GAP + BAND_W : 0);
  const padTop = (logos ? TILE_H * 4 + 14 : 0) + s * 0.5 + 2 + (band ? BAND_GAP + BAND_W : 0);
  const cx = R + padX, cy = R + padTop;
  const seats = [];
  radii.forEach((r, i) => {
    const n = counts[i];
    for (let j = 0; j < n; j++) {
      const t = n === 1 ? 0.5 : j / (n - 1);
      const a = Math.PI - Math.PI * t;
      seats.push({ a, r, x: cx + r * Math.cos(a), y: cy - r * Math.sin(a) });
    }
  });
  seats.sort((p, q) => q.a - p.a || p.r - q.r);
  const dot = s * 0.36;
  const circles = seats.map((p, i) => {
    const v = seq[i];
    // forme = vote : pour rond plein, contre anneau (centre vide), abstention petit point
    const sw = dot * 0.5;
    const r = v.pos === 'contre' ? dot - sw / 2 : v.pos === 'abstention' ? dot * 0.5 : dot;
    return `<circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="${r.toFixed(2)}" class="seat s-${POS[v.pos]}"${v.pos === 'contre' ? ` stroke-width="${sw.toFixed(2)}"` : ''}${v.g ? ` data-g="${v.g}"` : ''}/>`;
  }).join('');
  let extra = '';
  if (band || logos) {
    // secteurs : premier et dernier siège de chaque groupe dans l'ordre des angles
    const spans = [];
    seq.forEach((v, i) => { const last = spans.at(-1); if (last && last.g === v.g) { last.i1 = i; } else spans.push({ g: v.g, i0: i, i1: i }); });
    spans.forEach((sp, k) => {
      sp.a0 = k === 0 ? Math.PI : (seats[sp.i0].a + seats[spans[k - 1].i1].a) / 2;
      sp.a1 = k === spans.length - 1 ? 0 : (seats[sp.i1].a + seats[spans[k + 1].i0].a) / 2;
    });
    const rb = outer - BAND_W / 2;
    const pt = (a, r) => [cx + r * Math.cos(a), cy - r * Math.sin(a)];
    if (band) extra += spans.map((sp) => {
      const [x1, y1] = pt(sp.a0, rb), [x2, y2] = pt(sp.a1, rb);
      return `<path d="M${x1.toFixed(1)} ${y1.toFixed(1)}A${rb} ${rb} 0 0 1 ${x2.toFixed(1)} ${y2.toFixed(1)}" fill="none" stroke="${GROUP_COLORS[sp.g] || '#8D949A'}" stroke-width="${BAND_W}" class="gband" data-g="${sp.g}"><title>${GROUP_NAMES[sp.g] || sp.g}</title></path>`;
    }).join('');
    if (logos) {
      const placed = [];
      const hit = (b) => placed.some((q) => b.x < q.x + q.w + 3 && q.x < b.x + b.w + 3 && b.y < q.y + q.h + 3 && q.y < b.y + b.h + 3);
      for (const sp of spans) {
        const am = (sp.a0 + sp.a1) / 2;
        let box; const W = tileW(sp.g);
        for (let tier = 0; tier < 4; tier++) {
          const r = outer + 8 + (W * Math.abs(Math.cos(am)) + TILE_H * Math.abs(Math.sin(am))) / 2 + tier * (TILE_H + 2);
          const [x, y] = pt(am, r);
          box = { x: x - W / 2, y: y - TILE_H / 2, w: W, h: TILE_H, am, r, tier };
          if (!hit(box)) break;
        }
        placed.push(box);
        const [lx, ly] = pt(am, outer + 1), [tx, ty] = pt(am, box.r - (W * Math.abs(Math.cos(am)) + TILE_H * Math.abs(Math.sin(am))) / 2);
        const lead = box.tier > 0 ? `<path d="M${lx.toFixed(1)} ${ly.toFixed(1)}L${tx.toFixed(1)} ${ty.toFixed(1)}" class="lead"/>` : '';
        extra += `${lead}<text x="${(box.x + W / 2).toFixed(1)}" y="${(box.y + TILE_H / 2 + 5).toFixed(1)}" text-anchor="middle" class="ltext glogo" data-g="${sp.g}"><title>${GROUP_NAMES[sp.g] || sp.g}</title>${short(sp.g)}</text>`;
      }
    }
  }
  const w = 2 * (R + padX), h = R + padTop + dot + 1;
  return `<svg class="hemi${band ? ' banded' : ''}" id="${id}" viewBox="0 0 ${w.toFixed(0)} ${h.toFixed(0)}" role="img" aria-label="${esc(label)}">${extra}${circles}</svg>`;
}
// Revue ui-ux-pro-max : un siège doit tenir 3:1 contre le fond. De jour, les couleurs officielles plus claires
// (HOR, LIOT, SOC, DR, EcoS, Dem, NI) gardent leur remplissage et prennent un contour 35 % plus sombre.
const lum = (h) => { const c = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255).map((x) => (x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4)); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
const LIGHT_GROUPS = Object.entries(GROUP_COLORS).filter(([, c]) => 1.05 / (lum(c) + 0.05) < 3).map(([g]) => g);
const OUTLINE_CSS = LIGHT_GROUPS.map((g) => `:root:not([data-theme="dark"]) .hemi:not(.votes) .seat[data-g="${g}"]:not(.s-contre) { stroke: color-mix(in srgb, ${GROUP_COLORS[g]} 65%, #000); stroke-width: .55; }`).join('\n');
const PARTY_CSS = Object.entries(GROUP_COLORS).map(([g, c]) => `.hemi:not(.votes) .seat[data-g="${g}"] { fill: ${c}; stroke: ${c}; } .sw-g[data-g="${g}"] { background: ${c}; }`).join('\n');
// Nuit : les couleurs officielles très sombres (RN, GDR, UDR) disparaissent sur la surface #191C20 ; on les éclaircit de 30 % vers le blanc, teinte inchangée.
const PARTY_CSS_DARK = Object.entries(GROUP_COLORS).map(([g, c]) => `:root[data-theme="dark"] .hemi:not(.votes) .seat[data-g="${g}"] { fill: color-mix(in srgb, ${c} 70%, #ffffff); stroke: color-mix(in srgb, ${c} 70%, #ffffff); }`).join('\n');

// Arc du vote (charte) : demi-cercle dans une boîte 120 × 66, segments de gauche à droite.
function arcPath(a, b, r = 50, cx = 60, cy = 60) {
  const pt = (f) => [cx - r * Math.cos(f * Math.PI), cy - r * Math.sin(f * Math.PI)];
  const [x1, y1] = pt(a), [x2, y2] = pt(b);
  return `M${x1.toFixed(2)} ${y1.toFixed(2)} A${r} ${r} 0 0 1 ${x2.toFixed(2)} ${y2.toFixed(2)}`;
}
// Jauge de la liste : la part du camp gagnant parmi les votants, en vert si adopté, en rouge si rejeté ;
// le reste de l'arc en teinte neutre. Main levée, sans décompte : jauge pleine.
function miniArc(d, { w = 40, stroke = 16 } = {}) {
  const c = d.count;
  const won = d.result === 'adopte' ? 'pour' : 'contre';
  const f = c ? c[won] / (c.pour + c.contre + c.abstentions) : 1;
  const label = c ? `${RESULT[d.result]} : ${c.pour} pour, ${c.contre} contre, ${c.abstentions} abstentions` : `${RESULT[d.result]} à main levée`;
  const fill = f >= 0.999 ? `<path d="${arcPath(0, 1)}" class="k-${won}" stroke-width="${stroke}" fill="none"/>` : `<path d="${arcPath(0, 1)}" class="k-track" stroke-width="${stroke}" fill="none"/><path d="${arcPath(0, f)}" class="k-${won}" stroke-width="${stroke}" fill="none"/>`;
  return `<svg class="mini" width="${w}" height="${(w * 66) / 120}" viewBox="0 0 120 66" role="img" aria-label="${esc(label)}">${fill}</svg>`;
}
const LOGO = (w = 30, cls = '') => `<svg class="logo ${cls}" width="${w}" height="${((w * 58) / 104).toFixed(1)}" viewBox="8 34 104 58" aria-hidden="true"><path d="M14 86A46 46 0 0 1 106 86M32 86A28 28 0 0 1 88 86" fill="none" class="k-ink" stroke-width="13"/><path d="M47 86A13 13 0 0 1 73 86Z" class="f-pour"/></svg>`;
const ICON = {
  back: '<svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><path d="M15 5l-7 7 7 7" fill="none" class="k-ink" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  info: '<svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5" fill="none" class="k-ink" stroke-width="1.6"/><path d="M12 11v5.5M12 7.8v.4" fill="none" class="k-ink" stroke-width="1.8" stroke-linecap="round"/></svg>',
  widget: '<svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="7" height="7" rx="2" fill="none" class="k-ink" stroke-width="1.6"/><rect x="13" y="4" width="7" height="7" rx="2" fill="none" class="k-ink" stroke-width="1.6"/><rect x="4" y="13" width="7" height="7" rx="2" fill="none" class="k-ink" stroke-width="1.6"/><path d="M16.5 13.5v6M13.5 16.5h6" fill="none" class="k-ink" stroke-width="1.6" stroke-linecap="round"/></svg>',
  out: '<svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6h9v9M18 6L7 17" fill="none" class="k-ink2" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  chevron: '<svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6l6 6-6 6" fill="none" class="k-ink2" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
};

// Logo d'un groupe sur une tuile claire (même en sombre), sigle si le groupe n'a pas de logo.
const groupTile = (abbr, cls = '') => LOGOS[abbr]
  ? `<span class="gl ${cls}" title="${GROUP_NAMES[abbr] || abbr}"><img src="../assets/logos/${LOGOS[abbr]}.png" alt="${GROUP_NAMES[abbr] || abbr}" width="40" height="28"></span>`
  : `<span class="gl mark ${cls}" title="${GROUP_NAMES[abbr] || abbr}">${abbr}</span>`;
// Groupes rangés par position majoritaire, de gauche à droite : « Pour [logos] · Contre [logos] ».
function positionStrip(D) {
  const order = SEATING.map((a) => D.groups.find((g) => g.abbreviation === a)).filter((g) => g && g.position !== 'nonVotant');
  return `<div class="strips">${[['pour', 'Pour'], ['contre', 'Contre'], ['abstention', 'Abstention']].map(([k, w]) => {
    const gs = order.filter((g) => g.position === k);
    return gs.length ? `<div class="strip"><span class="lbl r-${POS[k]}">${w}</span><span class="tiles">${gs.map((g) => groupTile(g.abbreviation, 'xs')).join('')}</span></div>` : '';
  }).join('')}</div>`;
}

// Glyphes de la légende des formes (la couleur du groupe porte l'identité, la forme porte le vote).
const GLYPH = {
  pour: '<svg class="gly" width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><circle cx="6" cy="6" r="5" fill="currentColor"/></svg>',
  contre: '<svg class="gly" width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><circle cx="6" cy="6" r="4" fill="none" stroke="currentColor" stroke-width="2"/></svg>',
  abst: '<svg class="gly" width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><circle cx="6" cy="6" r="2.2" fill="currentColor"/></svg>',
};

// Décompte sans mots : la forme dit le vote (appris dans l'app), le chiffre suit.
const tallyLine = (c, cls = '') => `<p class="tally num ${cls}" aria-label="${c.pour} pour, ${c.contre} contre, ${c.abstentions} abstentions">${[['pour', c.pour], ['contre', c.contre], ['abst', c.abstentions]].map(([k, n]) => `<span class="t-${k}">${GLYPH[k]}${nb(n)}</span>`).join('')}</p>`;

// ---------- gabarit ----------
const FONTS = '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&family=Newsreader:opsz,wght@6..72,400;6..72,500;6..72,600&display=swap" rel="stylesheet">';
const BASE_CSS = readFileSync(join(root, 'perchoir.css'), 'utf8');
function page({ title, theme, body, css = '', script = '', cls = '' }) {
  return `<!doctype html>
<html lang="fr" data-theme="${theme}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="${theme}">
<title>${esc(title)}</title>
${FONTS}
<script>try{const q=new URLSearchParams(location.search).get('pal');if(q)document.documentElement.dataset.pal=q;}catch(e){}</script>
<script>try{const t=localStorage.getItem('perchoir-apparence');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t;else if(t==='auto')document.documentElement.dataset.theme=matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light';}catch(e){}</script>
<style>
${BASE_CSS}
${PARTY_CSS}
${PARTY_CSS_DARK}
${OUTLINE_CSS}
${css}
</style>
</head>
<body class="${cls}">
${body}
${script ? `<script>\n${script}\n</script>` : ''}
</body>
</html>
`;
}

// ---------- 1. Accueil : la séance du jour ----------
function homeCards() {
  const cards = [];
  // a) En séance aujourd'hui : le texte en débat et ses articles votés au scrutin public.
  const deb = latest.inDebate;
  const arts = [...deb.articles].reverse(); // de « liminaire » à 19
  const tally = { adopte: 0, rejete: 0, supprime: 0 };
  arts.forEach((a) => tally[a.outcome]++);
  const today = arts.filter((a) => a.date === '2026-10-23').length;
  const first = day(arts[0].date);
  console.assert(arts.length === tally.adopte + tally.rejete + tally.supprime);
  const n = arts.length;
  const R = 128, cx = 150, cy = 150;
  const dots = arts.map((a, i) => {
    const f = i / (n - 1);
    const x = cx - R * Math.cos(f * Math.PI), y = cy - R * Math.sin(f * Math.PI);
    const k = a.outcome === 'adopte' ? 'f-pour' : a.outcome === 'rejete' ? 'f-contre' : 'ring';
    const lab = a.number === 'liminaire' ? 'Article liminaire' : a.number === 'premier' ? 'Article 1er' : `Article ${a.number}`;
    const word = { adopte: 'adopté', rejete: 'rejeté', supprime: 'supprimé' }[a.outcome];
    return `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${a.outcome === 'supprime' ? 8.6 : 10}" class="${k}"><title>${lab} ${word}</title></circle>`;
  }).join('');
  // Annonce, pas un résultat : elle part en notification (écran notif) et n'est plus dans la pile.
  if (false) cards.push({
    tab: 'En débat', kind: 'debat', href: deb.dossierUrl,
    // Le texte n'est pas encore voté : l'hémicycle attend, tous les sièges en teinte neutre.
    figure: `<div class="fig">${realHemi(8706, { label: 'Vote final à venir', id: 'hwait' }).replace(/class="seat s-[a-z]+"/g, 'class="seat s-wait"').replace('class="hemi real"', 'class="hemi real votes"').replace(/ stroke-width="[^"]+"/g, '').replace(/r="[0-9.]+"/g, 'r="2.15"')}</div>
      <p class="wait">Vote final à venir</p>`,
    title: SHORT.plfss,
  });
  void first; void today; void dots;
  // b) Prochain vote solennel.
  const vote = latest.upcoming.find((u) => u.kind === 'vote_solennel');
  const reprise = latest.upcoming.find((u) => u.dossierRef === vote.dossierRef && u.kind === 'discussion');
  const vd = parisDate(vote.startsAt), rd = parisDate(reprise.startsAt);
  cards.push({
    tab: 'Vote solennel', kind: 'vote', href: vote.dossierUrl,
    figure: `<div class="fig"><svg class="fig-arc" viewBox="0 0 300 162" aria-hidden="true"><path d="M22 150A128 128 0 0 1 278 150M52 150A98 98 0 0 1 248 150" fill="none" class="k-rule" stroke-width="16"/></svg>
      <p class="hollow"><span class="big">${vd.getDate()}</span><span class="of">${cap(MONTHS[vd.getMonth()])} · ${DAYS[vd.getDay()]} ${vd.getHours()}&nbsp;h</span></p></div>`,
    title: SHORT.plf,
  });
  void rd;
  // c) et d) Décisions : la dernière adoptée, la dernière rejetée avec clivage.
  for (const num of [8706, 8610]) {
    checkSeats(num);
    const d = latest.decisions.find((x) => x.numero === num);
    const c = d.count;
    const word = RESULT[d.result];
    const parts = [`${nb(c.pour)} pour`, `${nb(c.contre)} contre`, ...(c.abstentions ? [`${nb(c.abstentions)} abstentions`] : [])];
    cards.push({
      tab: shortDate(day(d.date)), kind: d.result, href: `detail-${num}`,
      figure: `<div class="fig">${realHemi(num, { label: `${word} : ${parts.join(', ')}.`, id: 'h' + num })}
</div>
      <div class="resrow"><span class="word r-${d.result}">${word}</span>${tallyLine(c)}</div>`,
      title: shortTitle(d),
    });
  }
  return cards;
}

function home(theme) {
  const cards = homeCards();
  const tabsAt = ['l', 'r', 'c'];
  const body = `
<main class="screen home">
  <header class="bar">
    <a class="brand" href="#">${LOGO(30)}<span>Le Perchoir</span></a>
    <span class="acts"><a class="ib" href="#" aria-label="Ajouter le widget">${ICON.widget}</a><a class="ib" href="apropos-${theme}.html" aria-label="À propos">${ICON.info}</a></span>
  </header>
  <h1 class="serif day">${cap(longDate(TODAY))}</h1>
  <div class="deck" id="deck" tabindex="0" aria-label="La sélection du jour, ${cards.length} cartes">
${cards.map((c, i) => `    <article class="card k-${c.kind} tab-${tabsAt[i]}" aria-label="Carte ${i + 1} sur ${cards.length}">
      <span class="tab">${c.tab}</span>
      <a class="sheet" href="${c.href.startsWith('http') ? c.href : c.href + '-' + theme + '.html'}">
        <div class="figure" data-ui>${c.figure}</div>
        <div class="text">
          <h2 class="serif">${typo(c.title)}</h2>
          ${c.meta ? `<p class="meta">${c.meta}</p>` : ''}
          ${c.date ? `<p class="date">${c.date}</p>` : ''}
          ${c.legend || ''}
        </div>
      </a>
    </article>`).join('\n')}
  </div>
  <div class="pager" aria-hidden="true">${cards.map((_, i) => `<i class="${i ? '' : 'on'}"></i>`).join('')}</div>
  <a class="primary" href="liste-${theme}.html">Toutes les décisions</a>
</main>`;
  const script = `
const deck = document.getElementById('deck'), dots = [...document.querySelectorAll('.pager i')];
deck.addEventListener('scroll', () => {
  const cards = [...deck.children]; const x = deck.scrollLeft;
  let k = 0, best = 1e9; cards.forEach((c, i) => { const dist = Math.abs(c.offsetLeft - deck.offsetLeft - 20 - x); if (dist < best) { best = dist; k = i; } });
  if (x + deck.clientWidth >= deck.scrollWidth - 2) k = cards.length - 1;
  dots.forEach((d, i) => d.classList.toggle('on', i === k));
}, { passive: true });`;
  return page({ title: 'Le Perchoir, la séance du jour', theme, body, script, cls: 'is-home' });
}

// ---------- 2. Liste : toutes les décisions ----------
function list(theme) {
  const ds = latest.decisions;
  const kindOf = (d) => (d.type === 'ensemble' ? 'texte' : d.type === 'resolution' ? 'resolution' : 'motion');
  const counts = { texte: 0, resolution: 0, motion: 0 };
  ds.forEach((d) => counts[kindOf(d)]++);
  console.assert(counts.texte + counts.resolution + counts.motion === ds.length);
  const days = [];
  for (const d of ds) { const last = days.at(-1); if (last && last.date === d.date) last.items.push(d); else days.push({ date: d.date, items: [d] }); }
  const now = TODAY;
  const dayLabel = (s) => { const d = day(s); const y = d.getFullYear() !== now.getFullYear() ? ' ' + d.getFullYear() : ''; return cap(longDate(d)) + y; };
  const row = (d) => {
    const c = d.count;
    const res = `<b class="r-${d.result}">${RESULT[d.result]}</b>`;
    const href = details[d.numero] ? `detail-${d.numero}-${theme}.html` : '#';
    return `<li data-k="${kindOf(d)}"><a href="${href}">${miniArc(d)}<span class="rt"><span class="t">${typo(shortTitle(d))}</span><span class="m">${res}</span></span></a></li>`;
  };
  const body = `
<main class="screen app list">
  <header class="bar">
    <a class="ib back" href="accueil-${theme}.html" aria-label="Retour à la séance du jour">${ICON.back}</a>
    <span class="acts"><a class="ib" href="apropos-${theme}.html" aria-label="À propos">${ICON.info}</a></span>
  </header>
  <h1>Décisions</h1>
  <div class="chips" role="tablist" aria-label="Filtrer par type">
    <button role="tab" aria-selected="true" data-f="all" data-n="${ds.length}">Tout</button>
    <button role="tab" aria-selected="false" data-f="texte" data-n="${counts.texte}">Textes</button>
    <button role="tab" aria-selected="false" data-f="resolution" data-n="${counts.resolution}">Résolutions</button>
    <button role="tab" aria-selected="false" data-f="motion" data-n="${counts.motion}">Motions</button>
  </div>
${days.map((g) => `  <section class="dgroup" data-day>
    <h2>${dayLabel(g.date)}</h2>
    <ul class="rows">${g.items.map(row).join('')}</ul>
  </section>`).join('\n')}
</main>`;
  const script = `
const tabs = [...document.querySelectorAll('.chips button')];
tabs.forEach((b) => b.addEventListener('click', () => {
  tabs.forEach((t) => t.setAttribute('aria-selected', String(t === b)));
  const f = b.dataset.f;
  document.querySelectorAll('.rows li').forEach((li) => { li.hidden = f !== 'all' && li.dataset.k !== f; });
  document.querySelectorAll('[data-day]').forEach((s) => { s.hidden = ![...s.querySelectorAll('li')].some((li) => !li.hidden); });
}));`;
  return page({ title: 'Le Perchoir, toutes les décisions', theme, body, script });
}

// ---------- 3. Détail d'une décision ----------
function detail(num, theme) {
  const D = details[num];
  const d = D.decision;
  const c = D.count;
  const seq = seatSequence(D);
  const sc = checkSeats(num);
  const word = RESULT[d.result];
  const voters = c.pour + c.contre + c.abstentions;
  const dt = day(d.date);
  const groups = SEATING.map((a) => D.groups.find((g) => g.abbreviation === a)).filter(Boolean);
  const posWord = { pour: 'Pour', contre: 'Contre', abstention: 'Abstention', nonVotant: 'Non-votant' };
  const logo = groupTile;
  const maxTot = Math.max(...groups.map((g) => g.count.pour + g.count.contre + g.count.abstentions));
  const groupRow = (g) => {
    const k = g.count;
    const tot = k.pour + k.contre + k.abstentions;
    const bar = tot ? [['pour', k.pour], ['abst', k.abstentions], ['contre', k.contre]].filter((x) => x[1]).map(([p, n]) => `<i class="b-${p}" style="flex:${n}"></i>`).join('') : '';
    const main = g.position === 'nonVotant' || !tot ? `<span class="pv dash">—</span>` : `<span class="pv r-${POS[g.position]}">${posWord[g.position]}</span>`;
    const split = [k.pour && `${k.pour} pour`, k.contre && `${k.contre} contre`, k.abstentions && `${k.abstentions} abst.`].filter(Boolean).join(' · ') || 'Aucun vote';
    return `<li><button data-g="${g.abbreviation}" aria-pressed="false">${logo(g.abbreviation)}<span class="gn"><i class="sw-g" data-g="${g.abbreviation}" aria-hidden="true"></i><b>${g.abbreviation === 'NI' ? 'Non inscrits' : g.abbreviation}</b></span>${main}<span class="gbar"><span class="gfill" style="width:${((tot / maxTot) * 100).toFixed(1)}%">${bar}</span></span></button></li>`;
  };
  const args = D.arguments;
  const argBlock = (key, label) => {
    const list = args[key] || [];
    if (!list.length) return '';
    return `<section class="args a-${POS[key]}"><h3>${label}</h3><ul>${list.map((a) => `<li>${logo(a.group)}<p><b>${a.group}</b> ${typo(a.text)}</p></li>`).join('')}</ul></section>`;
  };
  const srcDate = day(args.source.date);
  const typeLine = [TYPE_LABEL[d.type] || 'Vote sur l’ensemble du texte', d.stage.replace(' à l’AN', '').replace(" à l'AN", ''), `${dt.getDate()} ${MONTHS[dt.getMonth()]} ${dt.getFullYear()}`].filter((x, i, a) => !(i === 1 && /Résolution/.test(x))).join(' · ');
  const body = `
<main class="screen app detail">
  <header class="bar">
    <a class="ib back" href="liste-${theme}.html" aria-label="Retour à la liste">${ICON.back}</a>
    <span class="bar-title">${shortDate(dt)}</span>
    <span class="ib-space"></span>
  </header>
  <section class="vote" aria-label="Résultat du vote">
    <div class="seg" role="radiogroup" aria-label="Couleurs des sièges"><button role="radio" aria-checked="true" data-mode="groups">Groupes</button><button role="radio" aria-checked="false" data-mode="votes">Vote</button></div>
    <div class="hemi-wrap">${realHemi(num, { labels: true, label: `${word} : ${c.pour} pour, ${c.contre} contre, ${c.abstentions} abstentions. ${voters} sièges, de gauche à droite.`, id: 'hemi' })}
    </div>
    <div class="resrow"><span class="word r-${d.result}">${word}</span>${tallyLine(c)}</div>
  </section>
  <h1 class="serif">${typo(d.summary.title)}</h1>
  <p class="lede">${typo(d.summary.explanation.split(/(?<=\.)\s/)[0])}</p>
  <section class="who">
    <h2>Qui a voté quoi</h2>
    <ul class="groups">${groups.map(groupRow).join('')}</ul>
  </section>
  <nav class="links" aria-label="Sources">
    <a href="${d.sourceUrl}">Voir sur le site de l’Assemblée${ICON.out}</a>
  </nav>
</main>`;
  void sc; void argBlock; void srcDate; void typeLine;
  const script = `
const svg = document.getElementById('hemi'); const btns = [...document.querySelectorAll('.groups button')];
btns.forEach((b) => b.addEventListener('click', () => {
  const on = b.getAttribute('aria-pressed') !== 'true';
  btns.forEach((x) => x.setAttribute('aria-pressed', String(x === b && on)));
  svg.classList.toggle('focus', on);
  svg.querySelectorAll('[data-g]').forEach((s) => s.classList.toggle('lit', on && s.dataset.g === b.dataset.g));
  if (on) svg.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
}));
const modes = [...document.querySelectorAll('.seg button')];
modes.forEach((m) => m.addEventListener('click', () => {
  modes.forEach((x) => x.setAttribute('aria-checked', String(x === m)));
  svg.classList.toggle('votes', m.dataset.mode === 'votes');
}));`;
  return page({ title: `Le Perchoir, ${d.summary.title}`, theme, body, script });
}

// ---------- 3. Détail : l'écran actuel de l'app, l'arc remplacé par le nouvel hémicycle ----------
function detailApp(num, theme) {
  const D = details[num], d = D.decision, c = D.count, dt = day(d.date);
  checkSeats(num);
  const word = RESULT[d.result];
  const stage = d.stage.replace(/ à l['’]AN/, '');
  const meta = [`Scrutin n°&nbsp;${num}`, `${shortDate(dt)} ${dt.getFullYear()}`, d.type === 'ensemble' ? stage : TYPE_LABEL[d.type].replace(', sans valeur de loi', '')].filter(Boolean).join(' · ');
  const order = SEATING.map((a) => D.groups.find((g) => g.abbreviation === a)).filter((g) => g && g.position !== 'nonVotant');
  const posBlock = (k, w) => {
    const gs = order.filter((g) => g.position === k);
    if (!gs.length) return '';
    const tile = (g) => `<li><button data-g="${g.abbreviation}" aria-pressed="false" aria-label="${g.abbreviation === 'NI' ? 'Non inscrits' : g.abbreviation}, ${w.toLowerCase()}, montrer ses sièges">${LOGOS[g.abbreviation] ? `<img src="../assets/logos/${LOGOS[g.abbreviation]}.png" alt="" width="96" height="48">` : `<span class="ni">${g.abbreviation}</span>`}<b>${g.abbreviation === 'NI' ? 'Non inscrits' : g.abbreviation}</b></button></li>`;
    return `<h3 class="pos r-${POS[k]}">${GLYPH[POS[k]]}${w}</h3><ul class="tiles3">${gs.map(tile).join('')}</ul>`;
  };
  const args = D.arguments;
  const argBlock = (key, label) => {
    const list = args[key] || [];
    return list.length ? `<section class="args a-${POS[key]}"><h3 class="r-${POS[key]}">${label}</h3><ul>${list.map((a) => `<li>${groupTile(a.group)}<p><b>${a.group}</b> ${typo(a.text)}</p></li>`).join('')}</ul></section>` : '';
  };
  const body = `
<main class="screen app detail detail-app">
  <header class="bar"><a class="ib back" href="liste-${theme}.html" aria-label="Retour à la liste">${ICON.back}</a></header>
  <section class="vote" aria-label="Résultat du vote">
    <div class="hemi-wrap">${realHemi(num, { label: `${word} : ${c.pour} pour, ${c.contre} contre, ${c.abstentions} abstentions.`, id: 'hemi' })}</div>
    <p class="verdict serif r-${d.result}">${word}</p>
    <dl class="figures num">
      <div><dt>${GLYPH.pour}pour</dt><dd class="t-pour">${nb(c.pour)}</dd></div>
      <div><dt>${GLYPH.contre}contre</dt><dd class="t-contre">${nb(c.contre)}</dd></div>
      <div><dt>${GLYPH.abst}abstentions</dt><dd class="t-abst">${nb(c.abstentions)}</dd></div>
    </dl>
  </section>
  <p class="kind">${meta}</p>
  <h1 class="serif">${typo(d.summary.title)}</h1>
  <p class="lede">${typo(d.summary.explanation)}</p>
  <section class="plan"><h2>Ce que prévoit le texte</h2><ul>${d.summary.points.map((x) => `<li>${typo(x)}</li>`).join('')}</ul></section>
  <section class="who"><h2>Qui a voté quoi</h2>${posBlock('pour', 'Pour')}${posBlock('contre', 'Contre')}${posBlock('abstention', 'Abstention')}</section>
  <section class="why"><h2>Pourquoi ils ont voté ainsi</h2>${argBlock('pour', 'Pour')}${argBlock('contre', 'Contre')}${argBlock('abstention', 'Abstention')}</section>
  <nav class="links" aria-label="Sources">
    <a href="${d.sourceUrl}">Voir le scrutin${ICON.out}</a>
    <a href="${d.dossierUrl}">Dossier législatif${ICON.out}</a>
  </nav>
  <p class="source">Source : Assemblée nationale, open data sous Licence Ouverte. Application non officielle.</p>
</main>`;
  const css = `
.detail-app .vote { padding: 22px 18px 20px; }
.detail-app .hemi-wrap .hemi { width: 100%; max-width: 340px; display: block; margin: 0 auto; }
.verdict { margin-top: 14px; text-align: center; font-size: 34px; font-weight: 600; letter-spacing: -0.01em; line-height: 1; }
.detail-app .figures { margin-top: 18px; text-align: center; }
.detail-app .figures dd { font-size: 26px; }
.detail-app .figures dt { gap: 5px; }
.plan { margin-top: 32px; } .plan h2, .who h2, .why h2 { font-size: 20px; font-weight: 600; letter-spacing: -0.01em; }
.plan ul { margin-top: 12px; display: flex; flex-direction: column; gap: 10px; }
.plan li { position: relative; padding-left: 18px; font-size: 16px; line-height: 1.55; color: var(--body); }
.plan li::before { content: ""; position: absolute; left: 2px; top: .7em; width: 5px; height: 5px; border-radius: 50%; background: var(--ink2); }
.pos { display: flex; align-items: center; gap: 8px; margin: 18px 0 10px; font-size: 17px; font-weight: 600; }
.tiles3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
.tiles3 button { width: 100%; height: 100px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; border: 0; border-radius: 14px; background: var(--surface); cursor: pointer; transition: background .15s, transform .1s; }
:root[data-theme="dark"] .tiles3 img { background: #fff; border-radius: 8px; padding: 3px 6px; }
.tiles3 img { width: 84px; height: 40px; object-fit: contain; }
.tiles3 b { font-size: 14px; font-weight: 600; }
.tiles3 .ni { width: 40px; height: 40px; border-radius: 10px; background: #4F5761; color: #fff; display: grid; place-items: center; font-size: 14px; font-weight: 600; }
.tiles3 button:active { transform: scale(.97); }
.tiles3 button[aria-pressed="true"] { background: var(--raised); }`;
  const script = `
const svg = document.getElementById('hemi'); const btns = [...document.querySelectorAll('.tiles3 button')];
btns.forEach((b) => b.addEventListener('click', () => {
  const on = b.getAttribute('aria-pressed') !== 'true';
  btns.forEach((x) => x.setAttribute('aria-pressed', String(x === b && on)));
  svg.classList.toggle('focus', on);
  svg.querySelectorAll('[data-g]').forEach((s) => s.classList.toggle('lit', on && s.dataset.g === b.dataset.g));
  if (on) svg.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
}));`;
  return page({ title: `Le Perchoir, ${d.summary.title}`, theme, body, css, script });
}

// ---------- 4. À propos ----------
function about(theme) {
  const ex = latest.decisions.find((x) => x.numero === 8610);
  const body = `
<main class="screen app about">
  <header class="bar">
    <a class="ib back" href="accueil-${theme}.html" aria-label="Retour">${ICON.back}</a>
  </header>
  <h1>À propos</h1>
  <section class="id">
    ${LOGO(88, 'big')}
    <p class="name">Le Perchoir</p>
  </section>
  <section class="group">
    <div class="panel pad">
      <div class="seg wide" role="radiogroup" aria-label="Apparence"><button role="radio" aria-checked="false" data-t="auto">Auto</button><button role="radio" aria-checked="${theme === 'clair'}" data-t="light">Jour</button><button role="radio" aria-checked="${theme === 'sombre'}" data-t="dark">Nuit</button></div>
    </div>
  </section>
  <section class="group">
    <div class="panel">
      <label class="switch-row"><span><b>Notifier les votes solennels</b></span><input type="checkbox" role="switch" checked><i class="sw-ui" aria-hidden="true"></i></label>
      <a class="link-row" href="widgets-${theme}.html">Ajouter le widget${ICON.chevron}</a>
    </div>
  </section>
  <section class="group">
    <div class="panel pad">
      <p class="keyline">${tallyLine({ pour: 'Pour', contre: 'Contre', abstentions: 'Abstention' }).replace(/<\/?p[^>]*>/g, '')}</p>
    </div>
  </section>
  <section class="group">
    <div class="panel">
      <a class="link-row" href="https://data.assemblee-nationale.fr">Données de l’Assemblée nationale${ICON.out}</a>
      <a class="link-row" href="#">Contact${ICON.out}</a>
      <a class="link-row" href="#">Confidentialité${ICON.out}</a>
    </div>
  </section>
  <p class="source">Résumés écrits par une IA. Seul le texte officiel fait foi. Application non officielle.</p>
</main>`;
  void ex;
  const script = `
const opts = [...document.querySelectorAll('[data-t]')];
try { const t = localStorage.getItem('perchoir-apparence'); if (t) opts.forEach((o) => o.setAttribute('aria-checked', String(o.dataset.t === t))); } catch (e) {}
opts.forEach((o) => o.addEventListener('click', () => {
  opts.forEach((x) => x.setAttribute('aria-checked', String(x === o)));
  const t = o.dataset.t;
  try { localStorage.setItem('perchoir-apparence', t); } catch (e) {}
  document.documentElement.dataset.theme = t === 'auto' ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : t;
}));`;
  return page({ title: 'Le Perchoir, à propos', theme, body, script });
}

// ---------- 5. Widgets : l'écran d'accueil du téléphone ----------
// Tailles iPhone 390 pt : petit 170, moyen 364 × 170, grand 364 × 382. Même dessin pour Glance (Android).
// Dans un widget, la forme d'un siège de 2 px ne se lit plus : les sièges y prennent la couleur du vote.
function widgets(theme) {
  const d8706 = latest.decisions.find((x) => x.numero === 8706), d8610 = latest.decisions.find((x) => x.numero === 8610);
  const vote = latest.upcoming.find((u) => u.kind === 'vote_solennel');
  const vd = parisDate(vote.startsAt);
  const hemi = (num) => realHemi(num, { id: 'w' + num + Math.random().toString(36).slice(2, 6), label: RESULT[details[num].decision.result] }).replace('class="hemi real"', 'class="hemi real votes"');
  const res = (d) => `<span class="w-res r-${d.result}">${RESULT[d.result]}</span>`;
  const emptyArc = `<svg class="w-arc" viewBox="0 0 300 162" aria-hidden="true"><path d="M22 150A128 128 0 0 1 278 150M52 150A98 98 0 0 1 248 150" fill="none" class="k-rule" stroke-width="18"/></svg>`;
  const when = `Vote · ${DAYS[vd.getDay()].slice(0, 3)}. ${vd.getHours()}&nbsp;h`;
  const small = (d) => `<a class="w w-s" href="detail-${d.numero}-${theme}.html">${hemi(d.numero)}${res(d)}<span class="w-t">${typo(shortTitle(d))}</span></a>`;
  const smallVote = `<a class="w w-s w-vote" href="#"><span class="w-fig">${emptyArc}<span class="w-day"><b class="serif">${vd.getDate()}</b><small>${MONTHS_SHORT[vd.getMonth()]}</small></span></span><span class="w-when">${when}</span><span class="w-t">${SHORT.plf}</span></a>`;
  const medium = (d) => `<a class="w w-m" href="detail-${d.numero}-${theme}.html"><span class="w-l">${hemi(d.numero)}${tallyLine(d.count, 'w-tally')}</span><span class="w-r">${res(d)}<span class="w-t serif">${typo(shortTitle(d))}</span><span class="w-date">${shortDate(day(d.date))}</span></span></a>`;
  const large = (d) => `<a class="w w-lg" href="detail-${d.numero}-${theme}.html">${hemi(d.numero)}<span class="w-row">${res(d)}${tallyLine(d.count, 'w-tally')}</span><span class="w-t serif">${typo(shortTitle(d))}</span>
    <span class="w-next"><span class="w-nd"><b class="serif">${vd.getDate()}</b><small>${MONTHS_SHORT[vd.getMonth()]}</small></span><span><b>${SHORT.plf}</b><span class="w-when">${when}</span></span></span></a>`;
  const label = (s) => `<span class="w-name">${s}</span>`;
  const body = `
<main class="springboard">
  <div class="sb-row"><figure>${small(d8706)}${label('Le Perchoir')}</figure><figure>${smallVote}${label('Le Perchoir')}</figure></div>
  <figure>${medium(d8610)}${label('Le Perchoir')}</figure>
  <figure>${large(d8706)}${label('Le Perchoir')}</figure>
</main>`;
  const css = `
body { background: var(--wall); }
:root, :root[data-theme="light"] { --wall: #C5CEC9; } :root[data-theme="dark"] { --wall: #08090A; }
.springboard { width: 390px; margin: 0 auto; padding: 56px 13px 40px; display: flex; flex-direction: column; gap: 18px; }
.sb-row { display: flex; gap: 24px; }
figure { margin: 0; display: flex; flex-direction: column; align-items: center; gap: 6px; }
.w-name { font-size: 12px; color: var(--ink); opacity: .8; }
.w { display: flex; flex-direction: column; background: var(--surface); border-radius: 22px; padding: 14px; overflow: hidden; color: var(--ink); transition: transform .15s; }
.w:active { transform: scale(.97); }
.w-s { width: 170px; height: 170px; }
.w-m { width: 364px; height: 170px; flex-direction: row; gap: 14px; align-items: stretch; }
.w-lg { width: 364px; height: 382px; padding: 18px; }
.w .hemi { display: block; width: 100%; height: auto; }
.w-res { font-family: "Newsreader", Georgia, serif; font-weight: 600; font-size: 20px; line-height: 1.1; letter-spacing: -0.01em; }
.w-t { font-size: 14px; font-weight: 500; line-height: 1.25; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.w-s .w-res { margin-top: 8px; }
.w-s .w-t { margin-top: 2px; }
.w-vote .w-fig { position: relative; display: block; }
.w-arc { display: block; width: 100%; }
.w-day { position: absolute; left: 0; right: 0; bottom: -4px; display: flex; flex-direction: column; align-items: center; line-height: 1; }
.w-day b { font-size: 40px; font-weight: 500; } .w-day small, .w-nd small { font-size: 12px; color: var(--ink2); }
.w-nd { display: flex; flex-direction: column; align-items: center; line-height: 1; min-width: 40px; } .w-nd b { font-size: 30px; font-weight: 500; }
.w-when { margin-top: 8px; font-size: 13px; color: var(--ink2); }
.w-vote .w-t { margin-top: 2px; }
.w-l { flex: 0 0 156px; display: flex; flex-direction: column; justify-content: center; }
.w-r { flex: 1; display: flex; flex-direction: column; min-width: 0; }
.w-m .w-t { margin-top: 4px; font-size: 19px; font-weight: 600; line-height: 1.15; -webkit-line-clamp: 3; }
.w-date { margin-top: auto; font-size: 13px; color: var(--ink2); }
.tally.w-tally { margin-top: 8px; gap: 10px; font-size: 13px; justify-content: center; }
.w-lg .w-row { display: flex; align-items: baseline; justify-content: space-between; margin-top: 10px; }
.w-lg .w-res { font-size: 24px; }
.w-lg .w-tally { margin-top: 0; }
.w-lg .w-t { margin-top: 6px; font-size: 22px; font-weight: 600; line-height: 1.15; }
.w-next { margin: auto -18px -18px; padding: 12px 18px 14px; background: var(--raised); display: flex; align-items: center; gap: 14px; }
.w-next b { display: block; font-size: 15px; font-weight: 600; }
.w-next .w-when { margin-top: 0; display: block; }
.r-adopte { color: var(--pour-ink); } .r-rejete { color: var(--contre-ink); }`;
  void d8610;
  return page({ title: 'Le Perchoir, widgets', theme, body, css });
}

for (const theme of ['clair', 'sombre']) {
  writeFileSync(join(out, `widgets-${theme}.html`), widgets(theme).replace(`data-theme="${theme}"`, `data-theme="${theme === 'clair' ? 'light' : 'dark'}"`).replace(`content="${theme}"`, `content="${theme === 'clair' ? 'light' : 'dark'}"`));
  const t = theme === 'clair' ? 'light' : 'dark';
  const fix = (html) => html.replace(`data-theme="${theme}"`, `data-theme="${t}"`).replace(`content="${theme}"`, `content="${t}"`);
  writeFileSync(join(out, `accueil-${theme}.html`), fix(home(theme)));
  writeFileSync(join(out, `liste-${theme}.html`), fix(list(theme)));
  for (const n of [8706, 8610]) writeFileSync(join(out, `detail-${n}-${theme}.html`), fix(detailApp(n, theme)));
  writeFileSync(join(out, `apropos-${theme}.html`), fix(about(theme)));
}
// ---------- 6. Notification « En débat » et l'écran qu'elle ouvre ----------
// Résumé d'exemple : le backend le fera rédiger par l'IA dès que le texte passe en séance
// (dossier législatif, exposé des motifs), comme pour une décision.
const DEBATE_SUMMARY = {
  explanation: 'Le texte fixe le budget de la Sécurité sociale pour 2027 : ce qu’elle prévoit de recevoir et de dépenser pour la santé, les retraites, la famille et l’autonomie.',
  points: [
    'Il prévoit les recettes de la Sécurité sociale, cotisations et impôts affectés.',
    'Il fixe l’objectif de dépenses de l’assurance maladie pour l’année.',
    'Il contient des mesures sur les retraites, les prestations familiales et la perte d’autonomie.',
  ],
};
function debateData() {
  const deb = latest.inDebate;
  const arts = deb.articles;
  const tally = { adopte: 0, rejete: 0, supprime: 0 };
  arts.forEach((a) => tally[a.outcome]++);
  return { deb, n: arts.length, tally };
}
const waitHemi = (id) => realHemi(8706, { label: 'Vote final à venir', id }).replace(/class="seat s-[a-z]+"/g, 'class="seat s-wait"').replace('class="hemi real"', 'class="hemi real votes"').replace(/ stroke-width="[^"]+"/g, '').replace(/r="[0-9.]+"/g, 'r="2.15"');
function notif(theme) {
  const body = `
<main class="lock">
  <p class="clock">09:41</p>
  <p class="lockdate">${cap(longDate(TODAY))}</p>
  <a class="notif" href="debat-${theme}.html">
    <span class="nicon">${LOGO(26)}</span>
    <span class="ntext"><span class="nhead"><b>Le Perchoir</b><span>maintenant</span></span>
      <b class="ntitle">En débat aujourd’hui</b>
      <span class="nbody">${SHORT.plfss} : les députés examinent le texte.</span></span>
  </a>
</main>`;
  const css = `
body { background: var(--wall); } :root, :root[data-theme="light"] { --wall: #C5CEC9; } :root[data-theme="dark"] { --wall: #08090A; }
.lock { width: 390px; min-height: 844px; margin: 0 auto; padding: 70px 10px; color: var(--ink); }
.clock { text-align: center; font-size: 84px; font-weight: 600; letter-spacing: -0.03em; line-height: 1; }
.lockdate { text-align: center; margin-top: 6px; font-size: 18px; font-weight: 500; }
.notif { margin-top: 360px; display: flex; gap: 12px; padding: 14px; border-radius: 22px; background: var(--surface); transition: transform .15s; }
.notif:active { transform: scale(.98); }
.nicon { flex: none; width: 38px; height: 38px; border-radius: 9px; background: var(--ground); display: grid; place-items: center; }
.ntext { flex: 1; display: flex; flex-direction: column; gap: 1px; font-size: 15px; line-height: 1.3; }
.nhead { display: flex; justify-content: space-between; font-size: 13px; color: var(--ink2); } .nhead b { font-weight: 600; color: var(--ink2); }
.ntitle { font-weight: 600; }
.nbody { color: var(--body); }`;
  return page({ title: 'Le Perchoir, notification', theme, body, css });
}
function debate(theme) {
  const { deb, n, tally } = debateData();
  const body = `
<main class="screen app detail detail-app">
  <header class="bar"><a class="ib back" href="accueil-${theme}.html" aria-label="Retour">${ICON.back}</a></header>
  <section class="vote" aria-label="Vote final à venir">
    <div class="hemi-wrap">${waitHemi('hdeb')}</div>
    <p class="verdict serif muted">En débat</p>
    <p class="wait">Vote final à venir</p>
  </section>
  <p class="kind">${typo(deb.shortTitle)}</p>
  <h1 class="serif">${SHORT.plfss}</h1>
  <p class="lede">${typo(DEBATE_SUMMARY.explanation)}</p>
  <section class="plan"><h2>Ce que prévoit le texte</h2><ul>${DEBATE_SUMMARY.points.map((x) => `<li>${typo(x)}</li>`).join('')}</ul></section>
  <section class="plan"><h2>Articles votés</h2>
    <dl class="figures num arts">
      <div><dt>adoptés</dt><dd class="t-pour">${tally.adopte}</dd></div>
      <div><dt>supprimés</dt><dd class="t-contre">${tally.supprime}</dd></div>
      <div><dt>rejetés</dt><dd class="t-contre">${tally.rejete}</dd></div>
    </dl>
  </section>
  <nav class="links" aria-label="Sources"><a href="${deb.dossierUrl}">Dossier législatif${ICON.out}</a></nav>
  <p class="source">Source : Assemblée nationale, open data sous Licence Ouverte. Application non officielle.</p>
</main>`;
  void n;
  const css = `
.detail-app .vote { padding: 22px 18px 20px; } .detail-app .hemi-wrap .hemi { width: 100%; max-width: 340px; display: block; margin: 0 auto; }
.verdict { margin-top: 14px; text-align: center; font-size: 34px; font-weight: 600; line-height: 1; } .verdict.muted { color: var(--ink); }
.plan { margin-top: 32px; } .plan h2 { font-size: 20px; font-weight: 600; letter-spacing: -0.01em; }
.plan ul { margin-top: 12px; display: flex; flex-direction: column; gap: 10px; }
.plan li { position: relative; padding-left: 18px; font-size: 16px; line-height: 1.55; color: var(--body); }
.plan li::before { content: ""; position: absolute; left: 2px; top: .7em; width: 5px; height: 5px; border-radius: 50%; background: var(--ink2); }
.arts { margin-top: 12px; padding: 16px 8px; background: var(--surface); border-radius: 16px; text-align: center; }
.arts dd { font-size: 26px; }`;
  return page({ title: `Le Perchoir, ${SHORT.plfss}`, theme, body, css });
}

for (const theme of ['clair', 'sombre']) {
  const t = theme === 'clair' ? 'light' : 'dark';
  const fix = (html) => html.replace(`data-theme="${theme}"`, `data-theme="${t}"`).replace(`content="${theme}"`, `content="${t}"`);
  writeFileSync(join(out, `notif-${theme}.html`), fix(notif(theme)));
  writeFileSync(join(out, `debat-${theme}.html`), fix(debate(theme)));
}
console.log('ok', out);
