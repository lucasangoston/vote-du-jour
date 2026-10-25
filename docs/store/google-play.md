# Fiche Google Play : Le Perchoir

Textes à coller dans la Play Console (langue par défaut : français – fr-FR).
Les longueurs entre parenthèses sont comptées en caractères Unicode par
`docs/store/compter.py` ; limite Google entre crochets.

## Fiche principale

- **Nom de l'application** (11) [30] :

  ```text
  Le Perchoir
  ```

- **Description courte** (77) [80] :

  ```text
  Les décisions de l'Assemblée nationale en bref : hémicycle, votes, arguments.
  ```

- **Catégorie** : Actualités et magazines (application).
  Tags suggérés : Politique, Actualités.
- **Coordonnées** : e-mail lucasangostonpro@gmail.com ; site
  https://lucasangoston.github.io/vote-du-jour/
- **Règles de confidentialité** :
  https://lucasangoston.github.io/vote-du-jour/confidentialite.html

## Description complète (3015) [4000]

Même texte que l'App Store.

```text
Le Perchoir résume les décisions de l'Assemblée nationale : chaque vote sur l'ensemble d'un texte, chaque motion de censure, chaque résolution, en quelques mots.

L'ACCUEIL EN CARTES
Chaque jour, des cartes à faire défiler : le prochain vote solennel inscrit à l'ordre du jour, puis les dernières décisions, chacune avec son résultat et son hémicycle. Le bouton « Toutes les décisions » ouvre la liste complète, jour par jour, filtrable : textes, résolutions, motions.

POUR CHAQUE DÉCISION
• L'hémicycle aux 574 places : chaque député à sa place réelle, à la couleur officielle de son groupe, et son vote d'un coup d'œil (rond plein pour, anneau contre, petit point abstention)
• Le résultat : adopté ou rejeté, avec le décompte des voix pour les scrutins publics
• Un titre clair et une ligne d'explication
• Ce que prévoit le texte, en quelques points
• Qui a voté quoi, groupe par groupe : touchez un groupe pour allumer ses sièges
• Pourquoi ils ont voté ainsi : les arguments des groupes, pour et contre, tirés des débats
• Les liens vers le scrutin et le dossier législatif officiels

EN DÉBAT
Le jour où un texte passe en séance, une notification (si vous les avez activées) l'annonce et ouvre l'écran « En débat » : ce que prévoit le texte, ses articles déjà votés au scrutin public et la date du vote final quand elle est connue.

WIDGETS
Les dernières décisions sur l'écran d'accueil, en trois tailles : la dernière décision avec son hémicycle coloré par le vote, et, en grand, le prochain vote solennel en bas. Sans décision récente, le petit et le moyen widget annoncent le prochain vote solennel.

NOTIFICATIONS, SI VOUS LE SOUHAITEZ
Une notification pour les votes importants seulement : votes solennels, motions de censure, textes de compromis et lectures définitives ; la veille au soir, l'annonce d'un vote solennel ; le jour même, le texte qui passe en débat. Désactivables à tout moment.

DÉLAI
Une décision apparaît 10 à 30 minutes après le vote, marquée « provisoire », puis est confirmée le lendemain avec le décompte complet et le vote de chaque groupe. Les votes sur les amendements et les articles n'ont pas de fiche détaillée.

JOUR OU NUIT
Apparence jour, nuit, ou celle du téléphone.

SANS COMPTE, SANS PUBLICITÉ, SANS SUIVI
Aucune inscription. Aucune mesure d'audience.

SOURCES ET RÉSUMÉS PAR IA
Les données viennent de l'open data de l'Assemblée nationale (Licence Ouverte Etalab). Les titres, explications, points clés et arguments sont rédigés automatiquement par une IA (Claude, d'Anthropic), avec une consigne de neutralité, à partir des textes et des comptes rendus des débats, sans relecture humaine. Ils peuvent contenir des erreurs : seuls le texte officiel et le résultat du vote font foi. Chaque décision renvoie vers les pages officielles.

APPLICATION NON OFFICIELLE
Le Perchoir est une application indépendante. Elle n'est liée ni à l'Assemblée nationale, ni au Gouvernement, ni à un parti politique.

Une question, une erreur dans un résumé ? lucasangostonpro@gmail.com
```

## Notes de version 1.0.0 (282) [500]

À coller dans la release (Tests internes, puis fermés, puis production), entre
les balises de langue proposées par la Console : `<fr-FR>` … `</fr-FR>`.

```text
Première version : les décisions de l'Assemblée nationale en bref. Accueil en cartes, hémicycle aux 574 places aux couleurs des groupes, « Qui a voté quoi » et les arguments de chaque groupe, écran « En débat », notifications des votes importants, widgets et apparence jour ou nuit.
```

## Éléments graphiques

Specs relues le 25 octobre 2026 sur
https://support.google.com/googleplay/android-developer/answer/9866151 :

- **Icône** : `docs/store/visuels/icone-512.png` (512 × 512, PNG 32 bits,
  carré plein, Google applique le masque).
- **Image de présentation** : `docs/store/visuels/feature-graphic-1024x500.png`
  (1024 × 500, PNG 24 bits sans alpha ; logo et nom « Le Perchoir » aux
  couleurs de DESIGN.md).
- **Captures téléphone** : `docs/store/visuels/android/` (7 PNG, 1080 × 1920,
  9:16, 24 bits sans alpha), même ordre et mêmes écrans que l'App Store :
  accueil en cartes, détail adopté, « Qui a voté quoi », « En débat »,
  liste, écran d'accueil avec le grand et le petit widget posés pour de vrai,
  détail rejeté en apparence nuit. Jusqu'à 8 captures par type d'appareil ;
  au moins 4 captures d'au moins 1080 px (portrait 1080 × 1920, 9:16) sont
  requises pour être éligible aux recommandations ; le côté long ne doit pas
  dépasser deux fois le côté court. Prises le 25 octobre 2026 sur l'émulateur
  (API 37) passé en 1080 × 1920 (`adb shell wm size 1080x1920`)
  plutôt que recadrées, barre d'état en mode démo (9:41).

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
performances de l'app, etc.). Revérifié le 25 octobre 2026 sur la nouvelle
app : mêmes dépendances Firebase (`firebase_core`, `firebase_messaging`, pas
d'Analytics ni de Crashlytics) ; préférences (`shared_preferences` :
notifications, apparence), cache des décisions et données des widgets
stockés sur l'appareil seulement, donc hors « collecte ».

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
  c'est le cas, ligne « Contact » de la page À propos (`about_page.dart`).
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
manifeste fusionné de la build release (21 octobre 2026, revérifié le
25 octobre 2026) : pas de permission
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
