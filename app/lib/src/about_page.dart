import 'package:flutter/material.dart';

import 'app_identity.dart';
import 'hemicycle/external_link_row.dart';
import 'hemicycle/hemicycle_logo.dart';
import 'notifications/important_votes_notifications.dart';
import 'notifications/important_votes_setting.dart';
import 'theme.dart';

const _openDataUrl = 'https://data.assemblee-nationale.fr';
const _licenceUrl = 'https://www.etalab.gouv.fr/licence-ouverte-open-licence/';

const _firebaseNotice =
    'Les notifications passent par Firebase Cloud Messaging (Google).';

/// Page « À propos » : nature de l'app, source, licence, règles de
/// sélection, lecture de l'arc, délai de publication et résumés par IA.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Mention de Firebase seulement si les notifications sont disponibles.
    final notifications = NotificationsScope.maybeOf(context) != null;
    return HemicyclePage(
      title: 'À propos',
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
                'Les décisions de l\'Assemblée nationale, en bref.',
                style: TextStyle(fontSize: 16, height: 1.5, color: colors.body),
              ),
            ],
          ),
        ),
        const ImportantVotesSetting(),
        _Section(
          title: 'Application indépendante',
          children: [
            _Paragraph(
              'Application non officielle, liée ni à l\'Assemblée, ni au '
              'Gouvernement, ni à un parti. Aucun compte, aucune publicité, '
              'aucun suivi.${notifications ? ' $_firebaseNotice' : ''}',
            ),
          ],
        ),
        const _Section(
          title: 'Source des données',
          children: [
            _Paragraph(
              'Open data de l\'Assemblée nationale, sous Licence Ouverte '
              'Etalab.',
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
            _Bullet(
              'Vote sur l\'ensemble d\'un texte (y compris à main levée)',
            ),
            _Bullet('Motions de censure et déclarations du Gouvernement'),
            _Bullet('Rejets préalables et rejet de la 1re partie du budget'),
            _Bullet('Résolutions (sans valeur de loi)'),
            SizedBox(height: 4),
            _Paragraph(
              'Pas les amendements ni les articles. Adopté ne veut pas dire '
              'loi : le texte poursuit son parcours.',
            ),
          ],
        ),
        const _Section(
          title: 'L\'arc du vote',
          children: [
            _Paragraph(
              'Vert : pour · gris : abstention · brique : contre. '
              'Pointillés : vote à main levée.',
            ),
            _Paragraph(
              'Un groupe est classé selon le vote de la majorité de ses '
              'membres.',
            ),
          ],
        ),
        const _Section(
          title: 'Délai de publication',
          children: [
            _Paragraph(
              'Une décision apparaît 10 à 30 min après le vote, marquée '
              '« provisoire », puis est confirmée le lendemain (décompte '
              'complet, vote par groupe).',
            ),
          ],
        ),
        _Section(
          title: 'Résumés',
          children: [
            Text(
              'Titres, explications, points et arguments sont rédigés par une '
              'IA (Claude, d\'Anthropic) avec une consigne de neutralité, à '
              'partir des textes et des comptes rendus, sans relecture. Seuls '
              'le texte officiel et le résultat font foi.',
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
