# Publier Le Perchoir sur les stores

Toutes les commandes `flutter` se lancent depuis `app/`.

## Avant chaque envoi : numéro de build

Incrémenter le numéro de build (`+N`) dans `app/pubspec.yaml` à chaque envoi,
sur l'un ou l'autre store : `version: 1.0.0+1` → `1.0.0+2`. Les stores refusent
un numéro déjà envoyé. Changer `1.0.0` seulement pour une nouvelle version
visible des utilisateurs.

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

## iOS (App Store)

La signature est automatique (équipe `792WRWDFHZ`). Il faut un compte Apple
Developer connecté dans Xcode (Réglages → Comptes) ; Xcode crée lui-même le
certificat de distribution et les profils App Store de l'app et du widget au
premier export.

```bash
flutter build ipa
```

- Si l'export réussit, envoyer `build/ios/ipa/*.ipa` avec l'app **Transporter**
  (glisser-déposer).
- Sinon, ouvrir l'archive dans Xcode et passer par l'Organizer
  (Distribute App → App Store Connect → Upload) :

  ```bash
  open build/ios/archive/Runner.xcarchive
  ```

L'app est déclarée sans chiffrement soumis à l'export
(`ITSAppUsesNonExemptEncryption = false`) : pas de questionnaire à chaque envoi.

## Première soumission : ce qui reste à faire

État au 25 octobre 2026 : `flutter build appbundle` et
`flutter build ipa --no-codesign` passent ; textes prêts dans
`docs/store/app-store.md` et `docs/store/google-play.md` (longueurs
recomptées par `docs/store/compter.py`) ; captures dans `docs/store/visuels/`.
Le reste demande un compte ou une console, donc l'éditeur.

### Comptes et signature

- [ ] Apple Developer Program actif (99 €/an), compte connecté dans Xcode.
- [ ] Compte développeur Google Play (25 $, vérification d'identité).
- [ ] Android : clé d'upload et `app/android/key.properties` (voir plus
  haut), puis `flutter build appbundle` signé.
- [ ] iOS : `flutter build ipa` signé (certificat et profils créés par Xcode),
  envoi avec Transporter ou l'Organizer.

### App Store Connect

- [ ] Créer l'app : nom « Le Perchoir », langue principale français, bundle
  `com.lucasangoston.votedujour`, SKU au choix.
- [ ] Coller les textes de `docs/store/app-store.md` : sous-titre, texte
  promotionnel, description, mots-clés, URLs, copyright, catégories.
- [ ] Déposer les captures `ios-6.9/` et `ios-6.3/` (7 chacune, dans l'ordre
  des noms).
- [ ] Questionnaires : classification par âge, confidentialité de l'app
  (tableau de la fiche), droits sur le contenu, notes pour l'App Review.
- [ ] TestFlight : testeurs internes, puis soumettre la version 1.0.0.

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
