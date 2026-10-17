# vote_contract

Contrat de données partagé entre le job (`backend/`) et l'app (`app/`).

- `schemaVersion` : version du format JSON publié (actuellement 1).
- `indexPath` : chemin de l'index, `v1/latest.json`, relatif à l'URL publique.
- `DecisionIndex` / `DecisionSummary` : lecture et écriture du JSON.

Compatibilité : ajouter un champ optionnel garde la version ; tout changement
cassant incrémente `schemaVersion` et publie sous `v<N>/`, à côté de l'ancien
format tant que des versions de l'app le lisent. Une décision portant une valeur
d'énumération inconnue est ignorée par les lecteurs plus anciens.

Exemple de `v1/latest.json` :

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-10-17T10:17:00.000Z",
  "source": {
    "name": "Assemblée nationale — open data",
    "url": "https://data.assemblee-nationale.fr",
    "license": "Licence Ouverte / Open Licence (Etalab)",
    "licenseUrl": "https://www.etalab.gouv.fr/licence-ouverte-open-licence/"
  },
  "decisions": [
    {
      "id": "VTANR5L17V8706",
      "numero": 8706,
      "voteMode": "scrutin_public",
      "type": "ensemble",
      "status": "confirmee",
      "result": "adopte",
      "date": "2026-10-13",
      "officialTitle": "l'ensemble du projet de loi organique relatif à … (première lecture).",
      "sourceUrl": "https://www.assemblee-nationale.fr/dyn/17/scrutins/8706",
      "shortTitle": "Adapter l'autorité judiciaire à la lutte contre les violences sexuelles et intrafamiliales",
      "stage": "1re lecture à l'AN",
      "dossierUrl": "https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54777"
    },
    {
      "id": "L17-VD234087DEC",
      "voteMode": "main_levee",
      "type": "ensemble",
      "status": "confirmee",
      "result": "adopte",
      "date": "2026-10-07",
      "officialTitle": "projet de loi autorisant l'approbation de l'accord multilatéral entre autorités compétentes portant sur l'échange des informations GloBE",
      "sourceUrl": "https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54379",
      "shortTitle": "Projet de loi autorisant l’approbation de l’accord multilatéral entre autorités compétentes portant sur l’échange des informations GloBE",
      "stage": "1re lecture à l'AN",
      "dossierUrl": "https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54379"
    }
  ]
}
```

Valeurs :

- `type` : `ensemble` (vote sur un projet ou une proposition de loi),
  `motion_de_censure`, `declaration_gouvernement` (art. 50-1 ou déclaration de
  politique générale), `rejet_prealable` (motion de rejet préalable adoptée),
  `premiere_partie_budget` (rejet de la première partie d'une loi de finances,
  le texte tombe), `resolution` (proposition de résolution), `autre` (scrutin
  solennel dont l'intitulé n'est pas reconnu) ;
- `result` : `adopte`, `rejete` — l'issue à afficher pour le texte : pour
  `rejet_prealable`, la motion est adoptée donc `result` vaut `rejete` ;
- `status` : `provisoire`, `confirmee`.

Champs optionnels (ajoutés par le ticket #7, absents des index plus anciens ;
un lecteur doit prévoir leur absence) :

- `shortTitle` : titre court à afficher à la place de `officialTitle` dans la
  liste et les widgets (`DecisionSummary.displayTitle` fait le repli). Titre du
  dossier législatif sans la formule « Proposition de loi visant à » ; pour une
  motion de censure, « Motion de censure : <texte> » après un 49.3 ou
  « Motion de censure déposée par … » ; pour une déclaration,
  « Déclaration du Gouvernement sur … ».
- `stage` : étape de la procédure ou étiquette, prête à afficher. Lectures :
  `1re lecture à l'AN`, `2e lecture à l'AN`, `3e lecture à l'AN`,
  `Nouvelle lecture à l'AN`, `Lecture définitive à l'AN`,
  `Texte de compromis (CMP)`, `Lecture unique à l'AN` (ou
  `Vote sur l'ensemble du texte` si la lecture est inconnue). Étiquettes :
  `Résolution (sans valeur de loi)`, `Motion de censure`,
  `Déclaration du Gouvernement`, `Déclaration de politique générale`,
  `Motion de rejet préalable, <lecture>`,
  `Première partie du budget, <lecture>`, `Scrutin solennel`. Jamais « loi
  votée » : c'est l'étape du vote à l'Assemblée.
- `dossierUrl` : page officielle du dossier législatif, si la décision y est
  rattachée.

Textes adoptés à main levée (ticket #8) :

- `voteMode` (optionnel) : `scrutin_public` ou `main_levee`. Absent des index
  plus anciens, il vaut alors `scrutin_public`. Une valeur inconnue rend la
  décision illisible (elle est ignorée), comme pour les autres énumérations.
- Une décision `main_levee` n'a **pas de `numero`** (champ omis), ni décompte,
  ni vote par groupe : seuls les textes adoptés sont publiés (`result` vaut
  toujours `adopte`). Son `id` est l'identifiant de l'acte de décision du
  dossier législatif (`L17-VD…DEC`), stable d'une publication à l'autre ;
  `officialTitle` est l'intitulé du texte adopté (à défaut, le titre du
  dossier) et `sourceUrl` la page du dossier. `type` vaut `ensemble` ou
  `resolution`, `stage` suit les mêmes règles que pour un scrutin.
- `numero` reste obligatoire pour un `scrutin_public`.
- Une version de l'app antérieure à ce champ exige `numero` : elle ignore donc
  les décisions à main levée, sans erreur, et lit les autres (vérifié par
  `test/decision_test.dart`).
- À date égale, l'index place les scrutins publics (numéro décroissant) avant
  les votes à main levée (`id` décroissant) : l'open data ne donne pas
  l'heure.
