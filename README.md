# vote-du-jour

Widget iOS et Android qui résume les décisions votées à l'Assemblée nationale : un titre court, une phrase d'explication et le résultat (adopté ou rejeté). Un tap ouvre le détail de la décision dans l'app.

Nom de travail : le nom définitif de l'app n'est pas encore choisi.

Données : open data de l'Assemblée nationale (Licence Ouverte Etalab).

## Configuration

- Données publiées : `https://pub-51ad28220f184398acec4e2b145afd20.r2.dev` (bucket R2 `vote-du-jour`, domaine r2.dev réservé au développement).
- Identifiant de l'app (iOS et Android) : `com.lucasangoston.votedujour`.
- Team ID Apple : `792WRWDFHZ`.
- Secrets GitHub Actions : `R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `ANTHROPIC_API_KEY`.
- Variables GitHub Actions : `R2_PUBLIC_BASE_URL`, `APPLE_TEAM_ID`, `APP_ID`.
