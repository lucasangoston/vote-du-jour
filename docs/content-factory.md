# Content factory : les décisions du jour en posts

Statut : spec validée en atelier le 11/11/2026, à découper en issues.
Prototype du visuel : branche `prototype/social-card` (commit `50e4307`).

## But

Publier chaque jour, sur un compte Le Perchoir, 1 à 3 posts factuels sur les
décisions de l'Assemblée. Le contenu vaut pour lui-même (un média citoyen) ;
l'app est en signature, jamais l'objet du post.

Règle éditoriale : strictement le ton de l'app. Aucune formulation d'accroche ;
l'intérêt vient du choix des décisions et de l'image. Aucune couleur choisie
par nous : la couleur vient des données (résultat, vote).

## Périmètre

v1 : Bluesky seul, une image et un texte par post, validés à la main dans une
issue GitHub.

Hors périmètre (tranches suivantes) : Threads, vidéo verticale 9:16 avec
l'hémicycle qui se remplit (TikTok, Reels, Shorts), fil avec les arguments
des deux camps, passage des données de `r2.dev` à `data.leperchoir.app`,
alignement de `docs/index.html` sur `DESIGN.md`.

## Vue d'ensemble

```
publish.yml (horaire) ──succès──▶ content.yml
                                   ├─ lit v1/latest.json + v1/decisions/<id>.json (contrat public)
                                   ├─ sélection déterministe (0 à 3 décisions)
                                   ├─ rend les cartes PNG (Flutter sans écran)
                                   ├─ écrit texte + texte alternatif (gabarit)
                                   └─ ouvre l'issue du jour (label `content`)

issue : label `publier` ──▶ content-publish.yml (issues: labeled)
                                   ├─ publie sur Bluesky les brouillons cochés et relus
                                   ├─ écrit le lien du post dans l'issue
                                   └─ ferme l'issue
```

La factory est un client du contrat publié, comme l'app : une panne de la
factory ou de Bluesky ne touche jamais la publication des données.

## Prérequis : contrat

- Champ facultatif `solennel` (booléen) sur la décision publiée, rempli depuis
  `codeTypeVote == 'SPS'` du jeu de données. Ajout de champ facultatif : on
  reste en `v1` (`paths.dart`).
- `isImportantDecision` (`backend/lib/src/notifications/notification_pass.dart`)
  passe dans `vote_contract`, avec ce qu'elle utilise (étapes « lecture
  définitive » et « CMP », aujourd'hui `Lecture` dans `dossier_index.dart`).
  Les notifications et la factory appellent la même fonction ; elle lit
  `solennel` au lieu du paramètre `codeTypeVote`.

## Sélection

Déterministe, en trois filtres. Rien n'est publié un jour sans décision
éligible : pas de post « rien voté aujourd'hui ».

1. Éligibilité, toutes requises :
   - `status: confirmee` (jamais de provisoire) ;
   - `summary` présent ;
   - `voteMode: scrutin_public`, avec `groups` et `seats` dans le détail ;
   - décision de 7 jours au plus ;
   - absente des issues `content` des 7 derniers jours (publiée ou jetée).
2. Classement :
   1. `isImportantDecision` (solennel, motion de censure, lecture définitive,
      CMP) ;
   2. les votes qui décident du sort d'un texte entier : `ensemble`,
      `rejet_prealable`, `premiere_partie_budget`,
      `declaration_gouvernement` ;
   3. `resolution` et `autre`.

   À priorité égale : écart serré (au plus 3 % des exprimés), puis
   configuration inhabituelle (unanimité quand au moins la moitié des
   sièges a voté, groupe partagé), puis présence
   d'`arguments`, puis la plus récente.
3. Diversité : une décision par `dossierUrl` et par jour (une décision sans
   `dossierUrl` est son propre dossier). On garde les 3 premières.

## Carte (image)

1080 × 1350, rendue par un outil Flutter sans écran qui réutilise le plan de
l'hémicycle (`hemicycle_places.dart`) et les polices de l'app (Geist,
Newsreader, chargées par `FontLoader`). Fond noir, angles droits, sans ombre
ni dégradé. Référence visuelle : `app/prototype/social_card/rendus/` sur
`prototype/social-card`.

Code : `app/lib/src/social_card/` (contenu, widget, polices). Rendu en ligne
de commande, depuis `app/` :

```bash
SOCIAL_CARD_DETAIL=<détail.json> SOCIAL_CARD_OUT=<carte.png> \
  [SOCIAL_CARD_TITLE=<titre écrit à la main>] \
  flutter test tool/social_card/render_social_card_test.dart
```

L'outil écrit aussi `<carte.png>.json` : `{"status": "ok", "title", "titleSize"}`,
`{"status": "titre_a_ecrire"}` (pas de PNG) ou `{"status": "pas_de_carte"}`.

De haut en bas :

1. Languette : étape raccourcie et date insécable, en capitales Geist
   (« 1RE PARTIE DU BUDGET · 1RE LECTURE · 4 NOV. 2026 »). Raccourcis :
   « Première partie du budget » → « 1re partie du budget », « à l'AN »
   retiré, « , » → « · ». Une seule ligne.
2. Titre, Newsreader 400 (axe `wght` fixé à 400), cascade :
   `summary.shortTitle`, sinon `summary.title`. Police réduite de 84 à 48 px
   pour tenir en 3 lignes ; jamais tronqué. S'il ne tient pas : brouillon
   « titre à écrire » (voir Validation). Jamais `decision.shortTitle` (titre
   du dossier, trop long).
3. Hémicycle, couleur = vote (palette vote sombre de `DESIGN.md` : pour
   `#4FB08F`, contre `#B5461F`, abstention `#9AA2AB`), absents et non-votants
   très atténués. Pas de sigles de groupes autour de l'arc. L'arc prend la
   place qui reste et rétrécit sous un titre et une légende longs.
   Motion de censure : les soutiens en encre neutre (`ink`), jamais le vert.
4. Légende sous l'arc : par camp, une pastille de la couleur de ses sièges,
   son nom et ses sigles (« ● Pour EPR, DR · ● Contre LFI-NFP · ● Abst. RN ·
   ○ Partagés NI »), dans l'ordre de `groups`. Tous les groupes du même
   avis : « Tous les groupes pour ». Motion de censure : « Pour la censure »
   et les soutiens. Les groupes sont ici, plus dans le texte du post.
5. Sous la légende, « N votants sur S » (S : sièges du scrutin) seulement
   si moins de la moitié des sièges a voté, et jamais pour une motion de
   censure.
6. Bandeau plein couleur du résultat (`#4FB08F` adopté, `#E07A58` rejeté) :
   « ADOPTÉ » / « REJETÉ » en Geist 700, et les chiffres sur une ligne
   (« 151 pour · 187 contre »). « 0 abst. » omis ; les autres zéros gardés.
   Motion de censure : « 132 pour · 289 requis ».
7. Pied : « Le Perchoir » et « Source : Assemblée nationale ».

## Texte du post (gabarit, sans modèle)

300 caractères au plus (limite Bluesky, lien compris). Lignes, dans cet
ordre ; si ça dépasse, les mots-dièse tombent d'abord, puis l'explication,
puis le fait saillant :

```
{Adopté|Rejeté}{ précision} — {titre}.
{chiffres, comme le bandeau}.
{fait saillant}                  ← s'il y en a un
{summary.explanation}
#AssembléeNationale {#MotionDeCensure|#Budget}
leperchoir.app
```

- Précision du verdict, ce qui le rend remarquable : « à l'unanimité »
  (aucun contre, aucune abstention), « sans voix contre », « sans voix
  pour », « à N voix près » (écart serré de la sélection), « à égalité des
  voix ». Jamais pour une motion de censure.
- Fait saillant, un seul, dans cet ordre : « Il manquait N voix sur les
  289 requises. » (motion de censure rejetée), « Plus d'abstentions (N) que
  de votes pour ou contre. », « N députés sur S ont voté. » (quand la carte
  affiche les votants), « Groupe partagé : {sigles}. » (hors NI).
- Les groupes ne sont plus dans le texte : ils sont dans la légende de la
  carte et dans son texte alternatif.
- Mots-dièse et liens sont cliquables (`richTextFacets`).

Espaces insécables avant « : ; ? ! » (`frenchTypography`), y compris dans un
titre écrit à la main.

## Fil de réponses (gabarit, sans modèle)

Publié en réponse au post, chaque réponse à la suite de la précédente,
300 caractères chacune :

- deux camps au moins ont des `arguments` : une réponse par camp avec son
  premier argument, attribué à son groupe (« Les arguments en séance. /
  Pour (DR) : … », puis « Contre (EcoS) : … ») ;
- sinon : « Ce que prévoit le texte : » et les `summary.points` qui
  tiennent dans une réponse ;
- le lien du scrutin officiel ferme le fil (« Scrutin officiel :
  assemblee-nationale.fr/dyn/17/scrutins/N », écrit sans `https://www.`,
  complété par la facette).

Dans l'issue, le fil est un troisième bloc modifiable ; une ligne `---`
sépare deux réponses ; bloc vidé : pas de fil. Le relecteur n'y vérifie que
la longueur : un argument porte les mots de son groupe.

## Texte alternatif (gabarit)

Toujours présent, avec les chiffres exacts des données :

« Carte Le Perchoir. {étape}, {date}. {titre}. Hémicycle coloré par le vote :
pour, {sigles} ; contre, {sigles} ; abstention, {sigles}. {Adopté|Rejeté},
{chiffres en toutes lettres}. {N votants sur S, si affiché}. »

Tous les groupes du même avis : « tous les groupes pour ». Motion de censure :
« Hémicycle : en blanc, les députés qui ont voté la motion ({sigles}) » et
« {N} pour, 289 requis ».

## Validation : l'issue du jour

- Une issue par jour (label `content`), créée seulement s'il y a au moins un
  brouillon, et pas avant 13 h (Paris) : le jeu de données des scrutins
  arrive vers 12 h 30.
- L'issue est verrouillée dès sa création (repo public) : seuls les
  collaborateurs la commentent ; les labels `content` et `publier` ne
  peuvent de toute façon être posés que par eux. Un bloc par brouillon : case à cocher, aperçu Bluesky (le post,
  sa carte et son fil), texte modifiable, texte alternatif, fil de
  réponses, id de la décision, lien vers la page officielle du
  scrutin (`sourceUrl`) pour vérifier les chiffres.
- Le texte d'origine est gardé en commentaire HTML caché dans le bloc.
- Brouillon « titre à écrire » : un champ titre vide ; non publiable tant
  qu'il n'est pas rempli.
- Valider : cocher, puis poser le label `publier`. `content-publish.yml`
  (`issues: labeled`) publie les blocs cochés, avec leur texte tel qu'édité,
  l'image (proportions 4:5) et son texte alternatif, puis le fil de
  réponses ; liens et mots-dièse sont cliquables. Un titre écrit à la main est rendu sur la carte à ce
  moment.
- Un bloc coché en échec du relecteur (#120), ou « titre à écrire » vide,
  n'est pas publié : l'issue reste ouverte, un commentaire dit quoi
  corriger et le label `publier` est retiré, à reposer après correction.
- Garde contre les doublons : un bloc qui porte déjà un lien de post n'est
  jamais republié ; le lien est écrit aussitôt chaque post publié, et un
  post déjà en ligne avec le même texte (panne entre le post et l'écriture
  du lien) est retrouvé parmi les 50 derniers au lieu d'être republié, les
  réponses du fil aussi. Le workflow peut être relancé sans risque.
- Après publication : lien de chaque post écrit dans son bloc, issue fermée
  quand tous les blocs cochés sont publiés.
  Une issue fermée sans `publier` = tout jeté.

## Audience

En tête de l'issue du jour, sous le compteur : j'aime, reposts, citations et
réponses des 10 derniers posts publiés, relevés sur l'API publique de
Bluesky depuis les liens des issues fermées (`content_stats.dart`). Une
panne de Bluesky laisse la section vide, sans bloquer l'issue.

## Passage en automatique

- Compteur recalculé à chaque passage depuis les issues `content` fermées :
  aucun état ailleurs. Comparaison texte publié / texte d'origine après
  normalisation (espaces, apostrophes ’ ‘ '). Un titre écrit à la main
  compte comme une correction.
- Par format (v1 : un seul, « carte Bluesky ») : après 30 posts publiés sans
  aucune correction, le format peut passer en publication automatique.
- Toujours validés à la main, quel que soit le compteur : votes solennels,
  motions de censure, et toute décision qui a des arguments (le fil de
  réponses les cite, résumés par un modèle : à relire).
- Le compteur est affiché en tête de chaque issue du jour (« Compteur :
  12 / 30 »). Le passage en automatique lui-même n'est pas encore branché :
  `canAutoPublish` dit si un post y aurait droit.

## Compte et domaine

- Domaine `leperchoir.app` enregistré chez IONOS, DNS confiés à Cloudflare.
- Compte Bluesky `@leperchoir.app`, vérifié par l'enregistrement DNS
  `_atproto`. Mot de passe d'application en secret GitHub
  `BLUESKY_APP_PASSWORD` ; le nom du compte en variable `BLUESKY_HANDLE`.
- `leperchoir.app` sert la page d'accueil (`docs/index.html`), lien de chaque
  post ; l'app n'est pas encore sur les stores.

## Points ouverts

- Titre des motions de censure : `summary.title` (« Motion de censure déposée
  par des députés ») répète la languette. Trouver un titre qui apprend
  quelque chose, sans nommer de personnes.
- `summary.shortTitle` n'existe que sur les résumés récents ; `summary.title`
  dépasse parfois 45 caractères (82 pour le titre-restaurant). À mesurer sur
  les issues : si les « titre à écrire » sont fréquents, ajouter un
  `socialTitle` produit par le job de résumé.

## Découpage proposé (issues)

1. Contrat : `solennel` et `isImportantDecision` dans `vote_contract`.
2. Sélection déterministe, avec tests.
3. Rendu de la carte en PNG (outil Flutter sans écran).
4. Gabarits du texte et du texte alternatif.
5. Issue du jour (`content.yml` après `publish.yml`).
6. Publication Bluesky au label `publier`, garde contre les doublons ;
   domaine et compte.
7. Compteur par format.
