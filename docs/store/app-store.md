# Fiche App Store : Le Perchoir

Textes à coller dans App Store Connect (langue principale : français). Les
longueurs entre parenthèses sont comptées en caractères Unicode par
`docs/store/compter.py` ; limite Apple entre crochets.

## Informations de l'app

- **Nom** (11) [30] :

  ```text
  Le Perchoir
  ```

- **Sous-titre** (24) [30] :

  ```text
  Décisions de l'Assemblée
  ```

- **Catégorie principale** : Actualités. **Secondaire** : Référence.
- **Droits sur le contenu** : oui, l'app affiche du contenu de tiers ; elle en
  a le droit : données de l'Assemblée nationale sous Licence Ouverte Etalab
  (réutilisation libre avec mention de la source, faite dans l'app), logos des
  groupes issus de Wikimedia Commons (voir `app/assets/group_logos/SOURCES.md`).
- **Prix** : gratuit. Pas d'achat intégré.
- **Copyright** : `2026 Lucas Angoston`
- **URL d'assistance** : https://lucasangoston.github.io/vote-du-jour/support.html
- **URL marketing** (facultative) : https://lucasangoston.github.io/vote-du-jour/
- **URL de la politique de confidentialité** :
  https://lucasangoston.github.io/vote-du-jour/confidentialite.html

## Texte promotionnel (141) [170]

Modifiable sans nouvelle version.

```text
Chaque décision de l'Assemblée nationale en bref : le résultat, qui a voté quoi et les arguments pour et contre. Sans compte, sans publicité.
```

## Description (2239) [4000]

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

## Mots-clés (97) [100]

Séparés par des virgules, sans espace ; les mots du nom et du sous-titre sont
déjà indexés, inutile de les répéter.

```text
député,députés,loi,scrutin,vote,parlement,politique,censure,hémicycle,législatif,widget,France,AN
```

## Captures

- iPhone 6,9 pouces (1320 × 2868, iPhone 17/18 Pro Max) :
  `docs/store/visuels/ios-6.9/` (6 PNG).
- iPhone 6,3 pouces (1206 × 2622, iPhone 17/18 Pro) :
  `docs/store/visuels/ios-6.3/` (6 PNG), même ordre.

La page « Screenshot specifications » d'Apple
(https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/,
relue le 21 octobre 2026) se contredit : la section « Required device sizes »
demande au moins une capture « iPhone with Dynamic Island (medium display) »
(6,3"), tandis que le tableau ne rend obligatoire que le 6,9" (ou à défaut le
6,5"). Les deux jeux sont fournis : déposer le 6,9" et le 6,3".

Pas de captures iPad : l'app est déclarée iPhone seulement
(`TARGETED_DEVICE_FAMILY = 1`, #50).

## Classification par âge

Questionnaire App Store Connect (version 2025, tranches 4+, 9+, 13+, 16+,
18+) : répondre **Aucun / Non** partout.

| Question | Réponse |
| --- | --- |
| Contrôles parentaux, vérification de l'âge | Non |
| Accès Web non restreint (navigateur intégré) | Non : les liens s'ouvrent dans Safari (`LaunchMode.externalApplication`) |
| Contenu généré par les utilisateurs, messagerie, chat | Non |
| Publicité | Non |
| Violence, horreur, armes, contenu sexuel, nudité, grossièretés | Aucun |
| Thèmes matures ou suggestifs | Aucun (les titres peuvent nommer des sujets de société, par exemple « violences sexuelles », sans description) |
| Alcool, tabac, drogues, jeux d'argent, concours | Aucun |
| Contenu médical ou bien-être | Non |

Classification attendue : **4+**.

## Confidentialité de l'app (App Privacy)

Réponse précise, alignée sur les manifestes de confidentialité
(`PrivacyInfo.xcprivacy`) embarqués par les SDK Firebase de l'app ; Xcode les
agrège dans le rapport de confidentialité que l'App Review compare à la fiche.

**Collectez-vous des données ?** Oui (uniquement par le SDK Firebase des
notifications ; l'éditeur ne collecte rien lui-même).

| Type de données | Finalités | Lié à l'utilisateur | Suivi |
| --- | --- | --- | --- |
| Identifiants › Identifiant de l'appareil | Fonctionnalité de l'app | Non | Non |
| Diagnostics › Autres données de diagnostic | Fonctionnalité de l'app, Analyses | Non | Non |
| Autres données › Autres types de données | Analyses | Non | Non |

Sources :

- Manifeste de `FirebaseMessaging` (bundle `Firebase_FirebaseMessaging.bundle`
  de la build Release) : `DeviceID` (App Functionality, non lié, pas de
  suivi) ; `OtherDiagnosticData` (App Functionality) ; `OtherDataTypes`
  (Analytics) ; `NSPrivacyTracking = false`.
- Manifeste de `FirebaseInstallations` : `OtherDiagnosticData` (Analytics, non
  lié, pas de suivi).
- Doc Firebase « Apple App Store data collection »
  (https://firebase.google.com/docs/ios/app-store-data-collection, mise à jour
  le 21 octobre 2026) : FirebaseMessaging collecte toujours le jeton APNs
  associé à l'identifiant d'installation, et, pour l'abonnement aux sujets,
  modèle d'appareil, langue, fuseau horaire, version de l'OS, identifiant et
  version de l'app ; FirebaseInstallations et FirebaseMessaging collectent le
  « Firebase user agent », « never linked to a user or device identifier » ;
  FirebaseCore « Does not collect data ». La journalisation des interactions
  avec les notifications n'a lieu qu'avec Google Analytics, absent de l'app.
- Définitions Apple (https://developer.apple.com/app-store/app-privacy-details/) :
  « Collect » = transmettre hors de l'appareil et garder accessible au-delà du
  temps de la requête (le jeton reste chez Google pour l'abonnement au sujet) ;
  la collecte optionnelle n'est pas dispensée : « data collected on an ongoing
  basis after an initial request for permission must be disclosed ».

« Non lié » : le jeton n'est rattaché à aucun compte ni identité, l'éditeur ne
le stocke pas et ne le croise avec rien. « Pas de suivi » : aucune donnée
croisée avec des données tierces à des fins publicitaires, aucun courtier.

Pas d'ATT (App Tracking Transparency) : l'app ne suit pas.

## Notes pour l'App Review

Champ « Notes » (en anglais pour l'équipe de review). Pas de compte de
démonstration : aucune connexion.

```text
Le Perchoir is an independent, unofficial app that summarizes the decisions of the French National Assembly (Assemblée nationale). It is not affiliated with the Assembly, the Government or any political party; this is stated in the app (About screen) and in the description.

No account or login is required. All features are available immediately.

Data: public open data published by the Assemblée nationale (data.assemblee-nationale.fr) under the French "Licence Ouverte" (Etalab), which allows reuse with attribution; the source is credited on each decision and in the About screen. The app downloads static files that are identical for all users. No user data is sent to the developer.

AI-generated content: titles, one-line explanations, key points and arguments for/against are generated server-side, ahead of time, by Claude (Anthropic) from the official texts and debate transcripts, with a neutrality instruction. Users cannot prompt the AI. This is disclosed in the About screen and the store description; every decision links to the official vote and legislative file.

Notifications (optional): after the user opens a decision for the first time, the app asks for notification permission. If granted, the device subscribes to a single Firebase Cloud Messaging topic ("votes-importants": solemn votes, motions of censure, final readings, and the evening before a scheduled solemn vote), about 1 to 3 per week. They can be turned off in About > "Votes importants". No push token is sent to our server.

Home screen widget: long-press the Home Screen > Edit > Add Widget > "Le Perchoir" (small, medium and large sizes).

Content: the list starts with "À venir" (upcoming items of the official agenda, also from Assemblée nationale open data), then past decisions. Votes take place only when the Assembly sits; outside session weeks the list shows the latest decisions with their dates.

Contact: Lucas Angoston, lucasangostonpro@gmail.com
```
