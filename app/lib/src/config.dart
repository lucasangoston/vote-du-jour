/// URL publique des données (bucket R2), surchargeable à la compilation :
/// `flutter run --dart-define=DATA_BASE_URL=http://localhost:8080`.
const dataBaseUrl = String.fromEnvironment(
  'DATA_BASE_URL',
  defaultValue: 'https://pub-51ad28220f184398acec4e2b145afd20.r2.dev',
);
