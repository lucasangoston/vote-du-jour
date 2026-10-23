# Fiche Google Play : Le Perchoir

Textes à coller dans la Play Console (langue par défaut : français – fr-FR).
Les longueurs entre parenthèses sont comptées en caractères Unicode par
`docs/store/compter.py` ; limite Google entre crochets.

## Fiche principale

- **Nom de l'application** (11) [30] :

  ```text
  Le Perchoir
  ```

- **Description courte** (76) [80] :

  ```text
  Les décisions de l'Assemblée nationale en bref : résultat, votes, arguments.
  ```

- **Catégorie** : Actualités et magazines (application).
  Tags suggérés : Politique, Actualités.
- **Coordonnées** : e-mail lucasangostonpro@gmail.com ; site
  https://lucasangoston.github.io/vote-du-jour/
- **Règles de confidentialité** :
  https://lucasangoston.github.io/vote-du-jour/confidentialite.html

## Description complète (2239) [4000]

Même texte que l'App Store.

```text
Le Perchoir résume les décisions de l'Assemblée nationale : chaque vote sur l'ensemble d'un texte, chaque motion de censure, chaque résolution, en quelques mots.

POUR CHAQUE DÉCISION
• Un titre clair et une ligne d'explication
• Le résultat : adopté ou rejeté, avec le décompte des voix pour les scrutins publics
• Qui a voté quoi, groupe par groupe
• Ce que prévoit le texte, en quelques points
• Les principaux arguments pour et contre, tirés des débats
• Les liens vers le scrutin et le dossier législatif officiels

À VENIR ET EN DÉBAT
En tête de liste, les prochains points de l'ordre du jour de l'Assemblée, dont les votes solennels annoncés, et le texte en cours de débat avec ses derniers articles votés au scrutin public.

WIDGET
Les dernières décisions sur l'écran d'accueil, en trois tailles : la dernière décision, la dernière décision expliquée, ou les trois dernières.

NOTIFICATIONS, SI VOUS LE SOUHAITEZ
Une notification pour les votes importants seulement : votes solennels, motions de censure, textes de compromis et lectures définitives, et la veille au soir l'annonce d'un vote solennel. Une à trois par semaine environ, désactivables à tout moment.

DÉLAI
Une décision apparaît 10 à 30 minutes après le vote, marquée « provisoire », puis est confirmée le lendemain avec le décompte complet et le vote de chaque groupe. Les votes sur les amendements et les articles n'ont pas de fiche détaillée.

SANS COMPTE, SANS PUBLICITÉ, SANS SUIVI
Aucune inscription. Aucune mesure d'audience. Mode sombre inclus.

SOURCES ET RÉSUMÉS PAR IA
Les données viennent de l'open data de l'Assemblée nationale (Licence Ouverte Etalab). Les titres, explications, points clés et arguments sont rédigés automatiquement par une IA (Claude, d'Anthropic), avec une consigne de neutralité, à partir des textes et des comptes rendus des débats, sans relecture humaine. Ils peuvent contenir des erreurs : seuls le texte officiel et le résultat du vote font foi. Chaque décision renvoie vers les pages officielles.

APPLICATION NON OFFICIELLE
Le Perchoir est une application indépendante. Elle n'est liée ni à l'Assemblée nationale, ni au Gouvernement, ni à un parti politique.

Une question, une erreur dans un résumé ? lucasangostonpro@gmail.com
```

## Éléments graphiques

Specs relues le 21 octobre 2026 sur
https://support.google.com/googleplay/android-developer/answer/9866151 :

- **Icône** : `docs/store/visuels/icone-512.png` (512 × 512, PNG 32 bits,
  carré plein, Google applique le masque).
- **Image de présentation** : `docs/store/visuels/feature-graphic-1024x500.png`
  (1024 × 500, PNG 24 bits sans alpha).
- **Captures téléphone** : `docs/store/visuels/android/` (5 PNG, 1080 × 1920,
  9:16). Au moins 4 captures d'au moins 1080 px sont requises pour être
  éligible aux recommandations ; le côté long ne doit pas dépasser deux fois
  le côté court (d'où le recadrage des captures 1080 × 2400 de l'émulateur).

## Contenu de l'application (Règles › Contenu de l'application)

- **Accès à l'application** : toutes les fonctionnalités sont accessibles
  sans restriction (pas de connexion).
- **Annonces** : Non, l'application ne contient pas d'annonces.
- **Application gouvernementale** : Non (application indépendante, non
  officielle).
- **Fonctionnalités financières, santé** : aucune.
- **Public cible** : 18 ans et plus. Choisir une tranche de moins de 13 ans
  ferait entrer l'app dans le programme Familles ; 13+ resterait possible,
  18+ est le choix le plus simple pour un contenu politique.
- **L'app attire-t-elle les enfants ?** Non.

### Classification du contenu (questionnaire IARC)

- Adresse e-mail : lucasangostonpro@gmail.com
- Catégorie : **Référence, actualités ou enseignement**.
- Violence, sexualité, langage grossier, substances, humour cru, jeux
  d'argent, peur : **Non** partout (l'app affiche des titres et résumés de
  textes de loi ; aucun contenu graphique).
- Interactions entre utilisateurs, partage de contenu, partage de la
  position, achats numériques : **Non**.
- Navigateur Web non restreint : **Non** (les liens s'ouvrent dans le
  navigateur du téléphone).
- Si le questionnaire demande la présence de contenu généré par IA :
  **Oui**, généré à l'avance côté serveur, sans saisie de l'utilisateur
  (point non vérifié : la question n'apparaît qu'à la saisie).

Classification attendue : PEGI 3, USK 0, ESRB Everyone (Tout public).

### Sécurité des données (Data safety)

Réponses :

| Question | Réponse |
| --- | --- |
| L'app collecte-t-elle ou partage-t-elle des types de données requis ? | **Oui** |
| Toutes les données sont-elles chiffrées en transit ? | **Oui** (HTTPS) |
| Moyen de demander la suppression des données ? | **Non** (aucun compte ; voir plus bas) |
| Type collecté | **Identifiants de l'appareil ou autres** (Device or other IDs) |
| Collectée / partagée | Collectée : oui ; partagée : **non** |
| Traitée de façon éphémère ? | Non |
| Obligatoire ou facultative | **Facultative** (seulement si l'utilisateur autorise les notifications) |
| Finalité | **Fonctionnalité de l'application** |

Aucun autre type (position, informations personnelles, activité, infos et
performances de l'app, etc.).

Sources :

- Doc Firebase « Prepare your app for Google Play's Data safety section »
  (https://firebase.google.com/docs/android/play-data-disclosure, mise à jour
  le 21 octobre 2026) : `firebase-installations` collecte l'identifiant
  d'installation Firebase (FID) « for identifying app installations » ;
  `firebase-messaging` collecte la version de l'app « for topic subscription
  and unsubscription » et utilise ces données « to send messages to the client
  app » ; « Firebase encrypts the data in transit using HTTPS » ; les
  métriques de livraison vers BigQuery et les événements Analytics ne
  s'appliquent pas (désactivés, pas de Google Analytics).
- Définitions Google Play
  (https://support.google.com/googleplay/android-developer/answer/10787469) :
  « Device or other IDs » cite explicitement les « Firebase installation
  IDs » ; un transfert à un prestataire (« service provider ») qui traite les
  données pour le compte du développeur n'est pas un partage ; la collecte est
  « facultative » si tous les utilisateurs peuvent la refuser, ce qui est le
  cas (`firebase_messaging_auto_init_enabled = false` jusqu'à l'activation).

Suppression : l'éditeur ne détient rien ; le jeton disparaît en désinstallant
l'app ou en coupant les notifications (désabonnement du sujet). Le badge
« suppression sur demande » n'est donc pas revendiqué.

Point d'interprétation : le « Firebase user agent » (modèle, versions) et la
version de l'app accompagnent les requêtes Firebase ; la doc ne les rattache
à aucune catégorie Play. Ils ne sont pas déclarés séparément (métadonnées
techniques des requêtes vers le prestataire). Si la Console ou un contrôle
signale un écart, ajouter « Infos et performances de l'app › Autres données
de performances de l'app », finalité Fonctionnalité de l'app, non partagée.

### Applications d'actualités (déclaration « Actualités et magazines »)

Exigences relues le 21 octobre 2026 :
https://support.google.com/googleplay/android-developer/answer/16189314 et
https://support.google.com/googleplay/android-developer/answer/10523915.

La déclaration est obligatoire pour toute app de la catégorie Actualités et
magazines ou qui se présente comme une app d'actualités, y compris les
agrégateurs et les apps dont le contenu est généré par IA. Sans elle, plus
aucune mise à jour ne peut être envoyée en examen.

Réponses proposées :

- **Coordonnées** : URL https://lucasangoston.github.io/vote-du-jour/support.html
  (e-mail). Google exige que cette URL soit **accessible depuis l'app** :
  aujourd'hui la page À propos ne la contient pas. À ajouter avant la
  soumission (ligne « Assistance » vers cette URL dans `about_page.dart`).
  Des liens vers des réseaux sociaux seuls ne suffisent pas.
- **Type d'entité mère** : Autre, avec la description « Développeur
  indépendant (personne physique), sans lien avec l'Assemblée nationale ».
- **Agrégateur** : oui ; contenu généré par IA à partir d'une source
  publique unique (open data de l'Assemblée nationale). L'app cite la source
  sur chaque décision (« Source : Assemblée nationale (open data, Licence
  Ouverte) ») et renvoie vers le scrutin et le dossier officiels, comme
  l'exige la règle « source of each news article ».
- **Date de publication** : chaque décision affiche sa date (exigence de
  date claire).
- **Fraîcheur** : la règle attend un contenu de moins de 30 jours pour les
  apps d'actualité ; pendant l'intersession d'été, la dernière décision peut
  dater de plus d'un mois.
- Questions facultatives (orientation éditoriale, affiliations, chartes,
  récompenses) : orientation « Politique », pas d'affiliation, charte : la
  consigne de neutralité décrite sur la page d'accueil.

Alternative : catégorie **Éducation** sans se présenter comme une app
d'actualités ; la description emploie « décisions », pas « actualité ». La
catégorie Actualités reste la plus honnête : choisir et remplir la
déclaration.

### Publicité

Non. Aucun SDK publicitaire.

**Identifiant publicitaire** (déclaration obligatoire, cible Android 13+) :
« Non, l'app n'utilise pas l'identifiant publicitaire ». Vérifié sur le
manifeste fusionné de la build release (21 octobre 2026) : pas de permission
`com.google.android.gms.permission.AD_ID` (seulement INTERNET,
POST_NOTIFICATIONS, WAKE_LOCK, ACCESS_NETWORK_STATE, RECEIVE_BOOT_COMPLETED,
FOREGROUND_SERVICE, c2dm RECEIVE). À revérifier sur l'AAB final dans
l'« Explorateur d'app bundle ».

## Test fermé obligatoire (compte personnel récent)

Règle en vigueur (https://support.google.com/googleplay/android-developer/answer/14151465,
relue le 21 octobre 2026) : un compte développeur **personnel créé après le
13 novembre 2023** doit faire tourner un **test fermé avec au moins
12 testeurs inscrits sans interruption pendant au moins 14 jours** avant de
pouvoir demander l'accès à la production. La page ne mentionne ni fin de la
règle ni l'ancien seuil de 20 testeurs.

Étapes :

1. Créer une piste de test fermé, y publier l'AAB signé.
2. Ajouter au moins 12 adresses Google (liste d'e-mails ou groupe Google) ;
   chaque testeur accepte l'invitation (lien d'inscription) et installe l'app.
3. Garder 12 testeurs inscrits 14 jours d'affilée (prévoir 15 à 20 personnes
   pour absorber les désinscriptions).
4. Demander l'accès à la production (questionnaire sur le test).
