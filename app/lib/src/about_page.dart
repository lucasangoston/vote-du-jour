import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_identity.dart';

final _openDataUri = Uri.parse('https://data.assemblee-nationale.fr');
final _licenceUri = Uri.parse(
  'https://www.etalab.gouv.fr/licence-ouverte-open-licence/',
);

/// Page « À propos / Méthode » : source, licence, règles de sélection, délai
/// de publication, génération des résumés par IA et nature de l'app.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('À propos et méthode')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '$appName résume les décisions votées à l\'Assemblée nationale : '
            'ce qui a été décidé et si le texte a été adopté ou rejeté.',
            style: theme.textTheme.bodyLarge,
          ),
          const _Section(
            icon: Icons.verified_user_outlined,
            title: 'Application indépendante',
            children: [
              _Paragraph(
                'Cette application n\'est pas une application officielle et '
                'n\'est liée ni à l\'Assemblée nationale, ni au Gouvernement, '
                'ni à aucun parti politique.',
              ),
              _Paragraph(
                'Elle ne demande aucun compte et ne collecte aucune donnée : '
                'ni publicité, ni outil de mesure d\'audience, ni suivi des '
                'plantages.',
              ),
            ],
          ),
          _Section(
            icon: Icons.dataset_outlined,
            title: 'Source des données',
            children: [
              const _Paragraph(
                'Les décisions proviennent de l\'open data de l\'Assemblée '
                'nationale, réutilisé sous Licence Ouverte Etalab. Chaque '
                'décision renvoie à sa page officielle.',
              ),
              _Link(label: 'data.assemblee-nationale.fr', uri: _openDataUri),
              _Link(label: 'Licence Ouverte Etalab', uri: _licenceUri),
            ],
          ),
          const _Section(
            icon: Icons.filter_list,
            title: 'Décisions retenues',
            children: [
              _Paragraph(
                'Seuls les votes qui tranchent sur un texte ou sur le '
                'Gouvernement sont retenus :',
              ),
              _Bullet('les votes sur l\'ensemble d\'un texte ;'),
              _Bullet('les motions de censure ;'),
              _Bullet('les votes sur une déclaration du Gouvernement ;'),
              _Bullet(
                'les motions de rejet préalable adoptées, qui rejettent le '
                'texte ;',
              ),
              _Bullet(
                'le rejet de la première partie d\'un budget (loi de finances '
                'ou de financement de la sécurité sociale), qui fait tomber '
                'tout le texte ;',
              ),
              _Bullet(
                'les propositions de résolution, qui expriment un avis de '
                'l\'Assemblée sans valeur de loi ;',
              ),
              _Bullet(
                'bientôt, les textes adoptés à main levée, sans décompte des '
                'voix.',
              ),
              _Paragraph(
                'Les votes sur les amendements et sur les articles ne sont pas '
                'retenus. Un texte adopté par l\'Assemblée n\'est pas encore '
                'une loi : il poursuit son parcours au Parlement.',
              ),
            ],
          ),
          const _Section(
            icon: Icons.schedule,
            title: 'Délai de publication',
            children: [
              _Paragraph(
                'Les décisions sont mises à jour une fois par jour, à partir '
                'du jeu de données publié par l\'Assemblée : un vote apparaît '
                'en général le lendemain.',
              ),
              _Paragraph(
                'Une publication plus rapide pendant les séances est à '
                'l\'étude : une décision y serait marquée provisoire jusqu\'à '
                'sa confirmation par les données officielles du lendemain.',
              ),
            ],
          ),
          _Section(
            icon: Icons.auto_awesome_outlined,
            title: 'Résumés',
            children: [
              Text(
                'Les résumés sont générés automatiquement par une '
                'intelligence artificielle, avec une consigne de neutralité, '
                'et ne sont pas relus. Seuls le texte officiel et le résultat '
                'du vote font foi.',
                style: muted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: style),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.uri});

  final String label;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: Text(label),
      ),
    );
  }
}
