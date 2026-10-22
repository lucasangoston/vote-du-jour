// Lance un workflow GitHub Actions par cron (ticket #51).
//
// Le jeton GITHUB_TOKEN (secret du Worker) est un jeton à grain fin limité
// au dépôt vote-du-jour, permission Actions en lecture et écriture : il ne
// peut que lancer les workflows de ce dépôt.

const REPO = 'lucasangoston/vote-du-jour';

/** Workflow lancé par chaque cron de wrangler.jsonc. */
const WORKFLOWS = {
  '3-59/10 7-22 * * 1-5': 'live.yml',
  '17 * * * *': 'publish.yml',
};

async function dispatch(workflow, token) {
  const response = await fetch(
    `https://api.github.com/repos/${REPO}/actions/workflows/${workflow}/dispatches`,
    {
      method: 'POST',
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${token}`,
        'User-Agent': 'perchoir-declencheur',
        'X-GitHub-Api-Version': '2022-11-28',
      },
      body: JSON.stringify({ ref: 'main' }),
    },
  );
  // 204 attendu ; sinon l'échec apparaît dans les journaux du Worker.
  if (response.status !== 204) {
    throw new Error(
      `${workflow} : HTTP ${response.status} ${await response.text()}`,
    );
  }
}

export default {
  async scheduled(controller, env) {
    const workflow = WORKFLOWS[controller.cron];
    if (!workflow) throw new Error(`cron inconnu : ${controller.cron}`);
    await dispatch(workflow, env.GITHUB_TOKEN);
  },
};
