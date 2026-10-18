import 'package:flutter/material.dart';

import 'app_identity.dart';
import 'hemicycle/external_link_row.dart';
import 'hemicycle/hemicycle_logo.dart';
import 'notifications/important_votes_setting.dart';
import 'theme.dart';

const _openDataUrl = 'https://data.assemblee-nationale.fr';
const _licenceUrl = 'https://www.etalab.gouv.fr/licence-ouverte-open-licence/';

/// Page « À propos / Méthode » : source, licence, règles de sélection, délai
/// de publication, génération des résumés par IA et nature de l'app.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HemicyclePage(
      title: 'À propos et méthode',
      children: [
        // Logo et promesse, comme sur la planche d'identité.
        Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HemicycleLogo.large(width: 96),
              const SizedBox(height: 14),
              Text(
                appName,
                style: HemicycleText.detailTitle.copyWith(color: colors.ink),
              ),
              const SizedBox(height: 6),
              Text(
                '$appName résume les décisions votées à l\'Assemblée '
                'nationale : ce qui a été décidé et si le texte a été adopté '
                'ou rejeté.',
                style: TextStyle(fontSize: 16, height: 1.5, color: colors.body),
              ),
            ],
          ),
        ),
        const ImportantVotesSetting(),
        const _Section(
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
        const _Section(
          title: 'Source des données',
          children: [
            _Paragraph(
              'Les décisions proviennent de l\'open data de l\'Assemblée '
              'nationale, réutilisé sous Licence Ouverte Etalab. Chaque '
              'décision renvoie à sa page officielle.',
            ),
            SizedBox(height: 4),
            ExternalLinkRow(
              label: 'data.assemblee-nationale.fr',
              url: _openDataUrl,
            ),
            SizedBox(height: 8),
            ExternalLinkRow(label: 'Licence Ouverte Etalab', url: _licenceUrl),
          ],
        ),
        const _Section(
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
              'les textes adoptés à main levée, sans scrutin public : ils '
              'sont repérés dans les dossiers législatifs et signalés « à '
              'main levée », sans décompte des voix ni vote par groupe.',
            ),
            SizedBox(height: 4),
            _Paragraph(
              'Les votes sur les amendements et sur les articles ne sont pas '
              'retenus. Un texte adopté par l\'Assemblée n\'est pas encore '
              'une loi : il poursuit son parcours au Parlement.',
            ),
          ],
        ),
        const _Section(
          title: 'L\'arc du vote',
          children: [
            _Paragraph(
              'L\'arc se remplit de gauche à droite : les voix pour (en vert), '
              'les abstentions (en gris), puis les voix contre (en brique), '
              'en proportion des votants. Pour un vote à main levée, l\'arc '
              'est en pointillés, de la couleur du résultat.',
            ),
          ],
        ),
        const _Section(
          title: 'Délai de publication',
          children: [
            _Paragraph(
              'Pendant les séances, le site de l\'Assemblée est consulté '
              'régulièrement : une décision apparaît, marquée « provisoire », '
              'environ 10 à 30 minutes après le vote.',
            ),
            _Paragraph(
              'Elle est confirmée le lendemain par le jeu de données officiel '
              'publié par l\'Assemblée, qui complète le décompte et le vote '
              'par groupe. Le titre court peut alors être précisé.',
            ),
          ],
        ),
        _Section(
          title: 'Résumés',
          children: [
            Text(
              'Le titre, la phrase d\'explication et les points « Ce que '
              'prévoit le texte » sont rédigés automatiquement par une '
              'intelligence artificielle (Claude, d\'Anthropic), à partir de '
              'l\'exposé des motifs du texte, sinon de ses articles, avec '
              'une consigne de neutralité. Les arguments de « Pourquoi ils '
              'ont voté ainsi » sont résumés automatiquement de la même '
              'façon, à partir des explications de vote des groupes dans '
              'les comptes rendus de séance. Ils ne sont pas relus. Tant '
              'qu\'un texte n\'est pas résumé, son titre officiel est '
              'affiché. Seuls le texte officiel et le résultat du vote font '
              'foi.',
              style: TextStyle(fontSize: 14, height: 1.5, color: colors.ink2),
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: HemicycleText.heading.copyWith(color: context.colors.ink),
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

TextStyle _bodyStyle(BuildContext context) =>
    TextStyle(fontSize: 15, height: 1.5, color: context.colors.body);

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: _bodyStyle(context)),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = _bodyStyle(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 18, child: Text('•', style: style)),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
