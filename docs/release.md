# Publier Le Perchoir sur les stores

Toutes les commandes `flutter` se lancent depuis `app/`.

## Avant chaque envoi : numéro de build

- **iOS** : rien à faire, le numéro de build est celui de l'exécution du
  workflow (voir plus bas).
- **Android** : incrémenter le numéro de build (`+N`) dans `app/pubspec.yaml`
  à chaque envoi : `version: 1.0.0+1` → `1.0.0+2`. Le Play Store refuse un
  numéro déjà envoyé.

Changer `1.0.0` seulement pour une nouvelle version visible des utilisateurs
(les deux stores).

## Android (Play Store)

### Une seule fois : clé d'upload

1. Générer la clé (hors du dépôt) :

   ```bash
   keytool -genkey -v -keystore ~/perchoir-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Créer `app/android/key.properties` (ignoré par git, **ne jamais le
   committer**) :

   ```properties
   storeFile=/Users/<vous>/perchoir-upload.jks
   storePassword=<mot de passe du keystore>
   keyAlias=upload
   keyPassword=<mot de passe de la clé>
   ```

   `storeFile` doit être un chemin absolu (`~` n'est pas développé).

3. Sauvegarder le fichier `.jks` et les deux mots de passe dans un gestionnaire
   de mots de passe : sans eux, plus de mise à jour possible avant une
   réinitialisation de la clé d'upload auprès de Google.

4. Dans la Play Console, à la création de l'app, garder **Play App Signing**
   activé : Google détient la clé de signature finale, la clé ci-dessus ne sert
   qu'à l'envoi.

Sans `key.properties`, la release est signée avec la clé de debug (pratique
pour `flutter run --release` et la CI), mais la Play Console refuse l'AAB.

### Construire et envoyer

```bash
flutter build appbundle
```

Envoyer `build/app/outputs/bundle/release/app-release.aab` dans la Play Console
(Tests internes d'abord).

## iOS (App Store) : par la CI

Le workflow `.github/workflows/ios.yml` (#124, #129) fait tout depuis GitHub,
sans Xcode : GitHub → Actions → « Envoi iOS sur TestFlight » → **Run
workflow** (avec le texte « À tester » montré aux testeurs), ou un tag `v*`
poussé.

1. Construit et signe l'app : signature automatique par la clé API App Store
   Connect (rôle Admin ; variables `ASC_KEY_ID`, `ASC_ISSUER_ID`, secret
   `ASC_KEY_P8`) avec le certificat de distribution géré par Apple. Version :
   `version:` de `app/pubspec.yaml` ; numéro de build : numéro d'exécution du
   workflow.
2. Envoie le build sur App Store Connect et attend son traitement (10 à
   30 min).
3. Le distribue au groupe externe **Public** de TestFlight et le soumet à la
   review bêta : les testeurs du lien public le reçoivent à l'approbation
   (souvent moins de 24 h). Apple n'accepte qu'un build en review bêta à la
   fois : si un autre y est encore, le run le signale par un avertissement et
   le build se soumet à la main depuis TestFlight.
4. Révoque le certificat de développement que `xcodebuild archive` crée à
   chaque passage (`app/ios/tool/revoke_ci_certificates.rb`).

Les scripts appellent l'API App Store Connect via `app/ios/tool/asc.rb`.

- Lien public des testeurs : https://testflight.apple.com/join/CAYBUgMY
- Un build TestFlight expire au bout de 90 jours.
- Publication sur l'App Store : dans App Store Connect, choisir le build dans
  la version, puis « Ajouter pour vérification ».

L'app est déclarée sans chiffrement soumis à l'export
(`ITSAppUsesNonExemptEncryption = false`) : pas de questionnaire à chaque envoi.

## Première soumission : ce qui reste à faire

État au 25 octobre 2026 : `flutter build appbundle` et
`flutter build ipa --no-codesign` passent ; textes prêts dans
`docs/store/app-store.md` et `docs/store/google-play.md` (longueurs
recomptées par `docs/store/compter.py`) ; captures dans `docs/store/visuels/`.
Le reste demande un compte ou une console, donc l'éditeur.

### Comptes et signature

- [x] Apple Developer Program actif (99 €/an).
- [ ] Compte développeur Google Play (25 $, vérification d'identité).
- [ ] Android : clé d'upload et `app/android/key.properties` (voir plus
  haut), puis `flutter build appbundle` signé.
- [x] iOS : envoi par la CI (`ios.yml`), builds 2 et 3 reçus le 15 novembre 2026.

### App Store Connect

- [x] Créer l'app : nom « Le Perchoir », langue principale français, bundle
  `com.lucasangoston.votedujour`, SKU `Votedujour`.
- [ ] Coller les textes de `docs/store/app-store.md` : sous-titre, texte
  promotionnel, description, mots-clés, URLs, copyright, catégories.
- [ ] Déposer les captures `ios-6.9/` et `ios-6.3/` (7 chacune, dans l'ordre
  des noms).
- [ ] Questionnaires : classification par âge, confidentialité de l'app
  (tableau de la fiche), droits sur le contenu, notes pour l'App Review.
- [x] TestFlight : groupe externe « Public » avec lien public, informations
  de test remplies, build 3 soumis à la review bêta (15 novembre 2026).
- [ ] Soumettre la version 1.0.0 à la review de l'App Store.

### Play Console

- [ ] Créer l'app (gratuite, application), coller les textes de
  `docs/store/google-play.md`, déposer icône, image de présentation et les
  7 captures `android/`.
- [ ] Contenu de l'application : accès, annonces, sécurité des données,
  public cible, classification IARC, déclaration « Actualités et magazines »,
  identifiant publicitaire.
- [ ] Tests internes, puis test fermé : au moins 12 testeurs inscrits
  14 jours d'affilée (compte personnel récent), puis demande d'accès à la
  production avec la note de version 1.0.0.

### Avant d'envoyer

- [x] GitHub Pages actif (`main`, `docs/`) : les pages d'assistance et de
  confidentialité des fiches répondent ; elles se mettent à jour au merge.
- [ ] Vérifier sur un vrai téléphone de chaque plateforme : lancement de la
  build release, notifications, widgets.
