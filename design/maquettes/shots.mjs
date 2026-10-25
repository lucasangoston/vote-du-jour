// Captures 390 px des maquettes, clair et sombre, dont chaque carte de l'accueil.
import { mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Browser, sleep } from '/Users/lucasangoston/.claude/skills/design-taste-frontend/scripts/lib/cdp.mjs';

const root = dirname(fileURLToPath(import.meta.url));
const dir = join(root, 'shots');
mkdirSync(dir, { recursive: true });
const only = process.argv[2];
const b = await Browser.launch();
const p = await b.newPage({ width: 390, height: 844, dsf: 2, mobile: true });
for (const theme of ['clair', 'sombre']) {
  for (const name of ['widgets', 'notif', 'debat', 'accueil', 'liste', 'detail-8706', 'detail-8610', 'apropos']) {
    if (only && !name.startsWith(only)) continue;
    const url = 'file://' + join(root, 'screens', `${name}-${theme}.html`);
    await p.goto(url, { settleMs: 1400 });
    if (name === 'accueil') {
      const n = await p.eval(() => document.querySelectorAll('.card').length);
      for (let i = 0; i < n; i++) {
        await p.eval((k) => { const d = document.getElementById('deck'); const c = d.children[k]; d.style.scrollSnapType = 'none'; d.scrollLeft = c.offsetLeft - 20; d.dispatchEvent(new Event('scroll')); }, i);
        await sleep(250);
        await p.screenshot({ path: join(dir, `${name}-${theme}-carte${i + 1}.jpg`), quality: 80 });
      }
    } else {
      await p.screenshot({ path: join(dir, `${name}-${theme}-fold.jpg`), quality: 80 });
      await p.screenshot({ path: join(dir, `${name}-${theme}-page.jpg`), quality: 80, fullPage: true });
    }
  }
}
await b.close();
console.log('shots in', dir);
