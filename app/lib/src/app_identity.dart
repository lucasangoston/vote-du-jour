/// Identité de l'app, centralisée ici.
///
/// [appName] : « Le Perchoir » (#36), le siège du président de l'Assemblée,
/// d'où l'on voit tout l'hémicycle. Les noms affichés par les systèmes
/// (CFBundleDisplayName dans `ios/Runner/Info.plist` et
/// `ios/DecisionWidget/Info.plist`, `android:label` dans
/// `AndroidManifest.xml`) ne peuvent pas lire cette constante : les aligner à
/// la main en cas de renommage. L'identifiant `com.lucasangoston.votedujour`
/// et l'App Group, eux, ne changent pas.
const appName = 'Le Perchoir';
