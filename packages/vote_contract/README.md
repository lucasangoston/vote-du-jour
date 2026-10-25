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
- `status` : `provisoire`, `confirmee` (voir ci-dessous).

Statut (ticket #10, détection en direct) :

- `status` vaut `provisoire` pour une décision lue sur le site de l'Assemblée
  pendant la séance, avant le jeu de données officiel, et `confirmee` une fois
  qu'elle y figure (même `id`, celui du scrutin). Une décision provisoire n'a
  ni dossier rattaché par référence ni vote par groupe ; son titre court et son
  étape peuvent changer à la confirmation.
- Le champ est optionnel à la lecture : absent, il vaut `confirmee`. Le job
  l'écrit toujours, car les versions de l'app antérieures au ticket #10
  l'exigent (elles connaissent déjà la valeur `provisoire`).
- Une valeur inconnue rend la décision illisible (elle est ignorée), comme
  pour les autres énumérations.

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

## Arc dans l'ordre de l'hémicycle (ticket #67)

Champ optionnel `arc` d'une décision (`DecisionSummary.arc`, liste de
`HemicycleSegment`), dans l'index et donc dans `decision` du fichier de
détail : l'arc du vote tel que dessiné par l'app et les widgets, de gauche à
droite, groupes de gauche à gauche.

```json
"count": { "pour": 503, "contre": 0, "abstentions": 67 },
"arc": [
  { "position": "abstention", "n": 66 },
  { "position": "pour", "n": 382 },
  { "position": "abstention", "n": 1 },
  { "position": "pour", "n": 121 }
]
```

- Chaque groupe politique occupe une part proportionnelle à ses voix
  exprimées (pour, abstentions, contre ; sans les non-votants), découpée selon
  les votes de ses membres. `position` : `pour`, `abstention` ou `contre` ;
  `n` : nombre de voix, strictement positif. Deux tronçons voisins de même
  sens sont fusionnés.
- Ordre des groupes : place moyenne de leurs députés dans l'hémicycle
  (`placeHemicycle` des mandats de l'archive AMO20 ; les sièges sont numérotés
  de la droite vers la gauche, voir le plan de l'hémicycle du site de
  l'Assemblée), table de repli par sigle sinon ; non-inscrits selon leur place
  moyenne, à droite sans place connue, comme un groupe inconnu
  (`backend/lib/src/hemicycle_arc.dart`).
- Dans un groupe, l'abstention reste entre pour et contre ; le sens (pour,
  abstention, contre ou l'inverse) place les voix à côté des voisins qui
  votent comme elles, pour un arc en aussi peu de morceaux que possible.
- Absent pour un vote à main levée, une décision provisoire (le site ne donne
  pas le vote par groupe) et dans les index plus anciens : l'arc se dessine
  alors par sens à partir de `count` (pour, abstentions, contre). Un seul
  tronçon illisible (sens inconnu, `n` nul, négatif ou non entier) rend tout
  l'arc illisible : il est ignoré, la décision reste lisible.
- La somme des tronçons de chaque sens est celle de `count` (vérifié sur
  tous les scrutins de la législature au 23/10/2026) ; les lecteurs dessinent
  l'arc proportionnellement à son propre total et le libellé accessible garde
  les totaux de `count`.
- Ajout rétrocompatible : même `schemaVersion`, les anciennes versions de
  l'app ignorent le champ.

## Fichier de détail (ticket #6)

Chaque décision de l'index a un fichier `v1/decisions/<id>.json`
(`decisionDetailPath(id)`, lu par `DecisionDetail`) : la décision telle
qu'elle figure dans l'index, plus le décompte et le vote par groupe. Le
fichier ne porte pas d'horodatage : tant que la décision ne change pas, il
reste identique octet pour octet et le job ne le réécrit pas.

```json
{
  "schemaVersion": 1,
  "source": { "name": "Assemblée nationale — open data", "…": "…" },
  "decision": { "id": "VTANR5L17V8706", "numero": 8706, "voteMode": "scrutin_public", "…": "mêmes champs que dans l'index" },
  "count": { "pour": 503, "contre": 0, "abstentions": 67, "nonVotants": 1 },
  "groups": [
    {
      "organeRef": "PO845401",
      "name": "Rassemblement National",
      "abbreviation": "RN",
      "position": "pour",
      "count": { "pour": 121, "contre": 0, "abstentions": 0, "nonVotants": 0 }
    }
  ]
}
```

- `count` est absent et `groups` vide pour un texte adopté à main levée.
- Une décision provisoire (détection en direct, #10) a le décompte lu sur le
  site (`nonVotants` à 0, le site ne le donne pas) et `groups` vide ; le
  passage en direct n'écrit que les détails des décisions provisoires, et la
  publication du jeu de données les réécrit, confirmés et complétés.
- `groups` suit l'ordre de l'open data (du plus grand au plus petit groupe).
  `name` est le libellé du groupe (organe de type `GP`) dans le jeu de données
  des acteurs et organes de la législature (AMO20, qui garde aussi les groupes
  dissous ou renommés) ; « Groupe non identifié » si la référence est
  inconnue. `abbreviation` (sigle d'usage) est optionnel.
- `position` : `pour`, `contre`, `abstention` (celle qui a recueilli le plus
  de voix parmi les membres du groupe), `partage` (égalité) ou `nonVotant`
  (aucun membre n'a voté). Elle est calculée sur le décompte du groupe : le
  champ `positionMajoritaire` de l'open data vaut « pour » quand aucun membre
  n'a voté et contredit le décompte dans environ 5 % des cas. Un groupe dont
  la position est inconnue d'un lecteur est ignoré.
- Ajouts rétrocompatibles : l'index n'a pas changé, les anciennes versions de
  l'app ignorent ces fichiers.

## Résumés (ticket #9)

Champ optionnel `summary` d'une décision, rédigé automatiquement par Claude
Haiku 5.5 avec une consigne de neutralité (`backend/lib/src/summary/summary_prompt.dart`),
sans relecture humaine :

```json
"summary": {
  "title": "Retour de l'âge légal de départ à 62 ans",
  "shortTitle": "Retraite à 62 ans",
  "explanation": "Le texte prévoit de ramener l'âge légal de départ à la retraite à 62 ans.",
  "points": ["…", "…", "…"],
  "promptVersion": 2
}
```

- Dans l'index : `title`, `shortTitle`, `explanation` et `promptVersion` seulement ; dans
  le fichier de détail (`decision.summary`), `points` en plus (3 ou 4 phrases ;
  liste vide quand le résumé ne s'appuie que sur l'intitulé : motion de
  censure, déclaration du Gouvernement, texte introuvable).
- `title` remplace `shortTitle` à l'affichage
  (`DecisionSummary.displayTitle` : résumé, sinon `shortTitle`, sinon
  `officialTitle`) ; `explanation` (`DecisionSummary.explanation`) s'affiche
  sous le titre dans la liste et le widget moyen.
- `shortTitle` (optionnel, #72) : titre de 35 caractères au plus
  (`shortTitleMaxLength`), pour la liste et les widgets
  (`DecisionSummary.compactTitle` : `summary.shortTitle`, sinon
  `displayTitle`). Absent des résumés antérieurs à la version 2 de la
  consigne ; vide ou trop long, il est ignoré et l'app se rabat sur le titre.
  À ne pas confondre avec le `shortTitle` de la décision (titre du dossier).
- Absent tant que la décision n'est pas résumée (texte pas encore en ligne,
  échec du modèle : la décision est « à régénérer » côté job) et dans les
  index plus anciens. Un résumé malformé (titre ou phrase vide, version
  absente) est ignoré : la décision reste lisible. Un point illisible est
  ignoré.
- `promptVersion` : version de la consigne qui a produit le résumé.
- Ajout rétrocompatible : les anciennes versions de l'app ignorent le champ.

## Arguments pour et contre (ticket #35)

Champ optionnel `arguments` du fichier de détail : les raisons données par
les groupes dans leurs explications de vote en séance, résumées
automatiquement par Claude Haiku 5.5 à partir du compte rendu, sans
relecture humaine (`DecisionArguments`).

```json
"arguments": {
  "pour": [
    { "group": "SOC", "organeRef": "PO845419", "text": "Le texte renforce la protection des victimes." }
  ],
  "contre": [],
  "abstention": [
    { "group": "LFI-NFP", "organeRef": "PO845413", "text": "Les moyens prévus ne suivent pas." }
  ],
  "source": {
    "date": "2026-10-13",
    "url": "https://www.assemblee-nationale.fr/dyn/17/comptes-rendus/seance/CRSANR5L17S2027O1N020"
  },
  "promptVersion": 1
}
```

- Un camp par position de groupe dans le scrutin (`pour`, `contre`,
  `abstention`), 0 à 3 arguments chacun ; liste vide quand aucun groupe de ce
  camp ne s'est exprimé. `group` est le sigle du groupe, comme
  `abbreviation` dans `groups` ; `organeRef` (optionnel) sa référence.
- `source` : jour de la séance et lien vers son compte rendu.
- `promptVersion` : version de la consigne
  (`backend/lib/src/arguments/arguments_prompt.dart`).
- Absent pour un vote sans explications de vote (main levée, petits textes,
  conventions), une décision provisoire ou pas encore rattachée à son compte
  rendu, et dans les fichiers plus anciens. Des arguments malformés (source
  ou version absente, aucun argument lisible) sont ignorés : le détail reste
  lisible. Un argument illisible est ignoré.
- Ajout rétrocompatible : les anciennes versions de l'app ignorent le champ.

## Ordre du jour : « À venir » (ticket #52)

Champ optionnel `upcoming` de l'index (`DecisionIndex.upcoming`, liste de
`UpcomingItem`) : les textes discutés et les votes solennels inscrits à
l'ordre du jour officiel des prochains jours, du plus proche au plus lointain.

```json
"upcoming": [
  {
    "id": "RUANR5L17S2027IDS30964PT53289",
    "kind": "vote_solennel",
    "startsAt": "2026-10-27T14:00:00.000Z",
    "seanceRef": "RUANR5L17S2027IDS30964",
    "label": "Vote solennel sur le projet de loi de financement de la sécurité sociale pour 2027",
    "shortTitle": "Projet de loi de financement de la sécurité sociale pour 2027",
    "dossierRef": "DLR5L17N54951",
    "dossierUrl": "https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54951"
  }
]
```

- `kind` : `discussion` (discussion d'un texte) ou `vote_solennel` (vote
  solennel ou par scrutin public). Un point de nature inconnue (ajoutée par un
  job plus récent) ou malformé est ignoré.
- `startsAt` : début de la séance, instant UTC (l'app l'affiche en heure de
  Paris) ; l'ordre du jour ne donne pas l'heure du point. `seanceRef` : la
  séance, celle que cite le scrutin (`seanceRef`) une fois le vote passé.
- `label` : libellé officiel du point ; `shortTitle` : titre à afficher (titre
  d'une décision déjà publiée du même dossier, sinon du dossier, sinon libellé
  nettoyé).
- `inProgress` (optionnel, absent vaut `false`) : discussion commencée avant
  la période couverte (« Suite de la discussion »).
- `dossierRef`, `dossierUrl` (optionnels) : dossier législatif, s'il est connu.
- `upcoming` absent : index antérieur au ticket, ou agenda jamais lu ; liste
  vide : rien d'inscrit.
- Ajout rétrocompatible : même `schemaVersion`, les anciennes versions de
  l'app ignorent le champ.

## Texte en débat : « En débat » (ticket #55)

Champ optionnel `inDebate` de l'index (`DecisionIndex.inDebate`, `InDebate`) :
le texte discuté lors de la séance en cours ou de la dernière séance des 7
derniers jours, et ses articles votés au scrutin public.

```json
"inDebate": {
  "dossierRef": "DLR5L17N54629",
  "shortTitle": "Projet de loi de finances pour 2027 (première partie)",
  "dossierUrl": "https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54629",
  "seanceRef": "RUANR5L17S2027IDS30951",
  "startsAt": "2026-10-19T19:30:00.000Z",
  "articles": [
    {"number": "40", "outcome": "rejete", "date": "2026-10-19", "scrutinRef": "VTANR5L17V8892"},
    {"number": "39", "outcome": "supprime", "date": "2026-10-19", "scrutinRef": "VTANR5L17V8889"},
    {"number": "38", "outcome": "adopte", "date": "2026-10-19", "scrutinRef": "VTANR5L17V8888"}
  ]
}
```

- `shortTitle` : même règle que `upcoming`. `seanceRef`, `startsAt` : séance
  en cours ou dernière séance (instant UTC de son début).
- `articles` : un par article (son dernier vote), du plus récent au plus
  ancien ; liste vide si aucun article n'a encore été voté. `number` : tel
  qu'écrit dans l'intitulé (« 4 », « liminaire », « 3 bis A », « premier »).
  `outcome` : `adopte`, `rejete`, ou `supprime` (amendement de suppression
  adopté). Un article de sort inconnu ou malformé est ignoré.
- `inDebate` absent : aucun texte en débat dans les 7 derniers jours, ou index
  antérieur au ticket. Un bloc malformé vaut absence.
- Ajout rétrocompatible : même `schemaVersion`, les anciennes versions de
  l'app ignorent le champ.
