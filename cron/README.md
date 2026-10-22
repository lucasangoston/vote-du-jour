# perchoir-declencheur

Worker Cloudflare qui lance `live.yml` et `publish.yml` à heure fixe (ticket #51) :
le cron de GitHub Actions ne passe en pratique que toutes les 3 à 5 heures sur ce
dépôt (spike #15). Le cron GitHub des workflows reste en filet de sécurité.

Crons et workflows : `wrangler.jsonc` et `src/index.js`.

## Jeton

`GITHUB_TOKEN`, secret du Worker : jeton à grain fin de lucasangoston, limité au
dépôt `vote-du-jour`, permission *Actions* en lecture et écriture, expiration
1 an. Pour le remplacer (depuis ce dossier) :

```bash
npx wrangler secret put GITHUB_TOKEN
```

## Déployer

```bash
npm install
npx wrangler login   # une fois
npx wrangler deploy
```

Journaux des passages : `npx wrangler tail`, ou le tableau de bord Cloudflare
(Workers → perchoir-declencheur → Logs).
