import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vote_contract/vote_contract.dart';

import 'decision_detail/decision_detail_repository.dart';
import 'decision_detail/decision_route.dart';
import 'decision_list_page.dart';
import 'decisions_repository.dart';
import 'discovery_actions.dart';
import 'hemicycle/hemicycle_seats.dart';
import 'hemicycle/result_style.dart';
import 'hemicycle/vote_arc.dart';
import 'hemicycle/vote_glyph.dart';
import 'relative_date.dart';
import 'theme.dart';
import 'upcoming.dart';

/// Nombre de décisions de l'accueil, après le prochain vote solennel.
const homeDecisionCount = 3;

/// Une carte de la pile de l'accueil (#79).
sealed class HomeCard {
  const HomeCard();
}

/// Le prochain vote solennel de l'ordre du jour.
class UpcomingVoteCard extends HomeCard {
  const UpcomingVoteCard(this.item);

  final UpcomingItem item;
}

/// Une décision récente.
class DecisionCard extends HomeCard {
  const DecisionCard(this.decision);

  final DecisionSummary decision;
}

/// Cartes de l'accueil : le prochain vote solennel (s'il y en a un à
/// l'ordre du jour), puis les [homeDecisionCount] dernières décisions, une
/// par texte (la plus récente : l'index est trié du plus récent au plus
/// ancien). Pas de carte « En débat » : l'annonce passe par une
/// notification (#77).
List<HomeCard> homeCards(DecisionIndex index, {required DateTime now}) {
  final vote = upcomingToShow(
    index.upcoming,
    now: now,
  ).where((u) => u.kind == UpcomingKind.voteSolennel).firstOrNull;
  final texts = <String>{};
  final decisions = [
    for (final d in index.decisions)
      // Un texte = une carte ; une décision sans dossier est son propre texte.
      if (texts.add(d.dossierUrl ?? d.id)) d,
  ].take(homeDecisionCount);
  return [
    if (vote != null) UpcomingVoteCard(vote),
    for (final d in decisions) DecisionCard(d),
  ];
}

/// Accueil en pile de cartes (#79) : la date du jour, les cartes qu'on fait
/// défiler de côté, le bouton « Toutes les décisions ». Se rafraîchit à
/// l'ouverture et à chaque retour de l'app au premier plan.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    this.detailRepository,
    this.now,
  });

  final DecisionsRepository repository;

  /// Fichiers de détail, pour les sièges des cartes ; par défaut, l'URL
  /// publique des données.
  final DecisionDetailRepository? detailRepository;

  /// Instant de référence (tests) ; par défaut, l'heure courante.
  final DateTime? now;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppLifecycleListener _lifecycle;
  DecisionIndex? _index;
  Object? _error;
  bool _loading = false;

  /// Détails déjà lus, par décision : leurs sièges remplacent l'arc.
  final _details = <String, DecisionDetail>{};
  final _pendingDetails = <String>{};

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    // Hors ligne : afficher d'abord les dernières données connues.
    if (_index == null) {
      final cached = await widget.repository.readCached();
      if (mounted && cached != null && _index == null) {
        setState(() => _index = cached);
        _loadSeats(cached);
      }
    }
    try {
      final index = await widget.repository.fetchLatest();
      if (!mounted) return;
      setState(() {
        _index = index;
        _error = null;
      });
      _loadSeats(index);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      if (_index != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hors ligne : dernières données connues.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Lit le fichier de détail des décisions affichées, pour leurs sièges.
  /// En attendant, ou s'il manque, la carte garde l'arc de l'index.
  void _loadSeats(DecisionIndex index) {
    final repository =
        widget.detailRepository ?? defaultDecisionDetailRepository;
    for (final card in homeCards(index, now: _now)) {
      if (card case DecisionCard(:final decision)
          when decision.voteMode == VoteMode.scrutinPublic &&
              !_details.containsKey(decision.id) &&
              _pendingDetails.add(decision.id)) {
        repository
            .fetch(decision.id)
            .then((detail) {
              if (mounted) setState(() => _details[decision.id] = detail);
            })
            .catchError((Object e) {
              debugPrint('Accueil : sièges de ${decision.id} absents : $e');
            })
            .whenComplete(() => _pendingDetails.remove(decision.id));
      }
    }
  }

  void _openList() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          DecisionListPage(repository: widget.repository, initial: _index),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final padding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _refresh,
          edgeOffset: padding.top,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: padding.top + 4),
                    const BrandBar(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Semantics(
                        header: true,
                        child: Text(
                          formatFrenchWeekdayDay(_now),
                          style: HemicycleText.displayLg.copyWith(
                            color: context.colors.ink,
                          ),
                        ),
                      ),
                    ),
                    // Les cartes, centrées entre la date et le bouton.
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        child: Center(child: _body(context)),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        24 + padding.bottom,
                      ),
                      child: _PrimaryButton(
                        label: 'Toutes les décisions',
                        onPressed: _openList,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final index = _index;
    if (index == null) {
      if (_error != null && !_loading) {
        return _Message(
          text: 'Impossible de charger les décisions.',
          action: FilledButton(
            onPressed: _refresh,
            child: const Text('Réessayer'),
          ),
        );
      }
      return const CircularProgressIndicator();
    }
    final cards = homeCards(index, now: _now);
    if (cards.isEmpty) {
      return const _Message(text: 'Aucune décision publiée pour le moment.');
    }
    return CardDeck(
      count: cards.length,
      itemBuilder: (context, i, width) => switch (cards[i]) {
        UpcomingVoteCard(:final item) => _VoteCard(
          item,
          width: width,
          tab: _tabSides[i % _tabSides.length],
          now: _now,
        ),
        DecisionCard(:final decision) => _DecisionCard(
          decision,
          detail: _details[decision.id],
          width: width,
          tab: _tabSides[i % _tabSides.length],
          now: _now,
        ),
      },
    );
  }
}

/// Place des languettes, de carte en carte, comme des chemises rangées :
/// à gauche, à droite, au centre.
const _tabSides = [
  Alignment.centerLeft,
  Alignment.centerRight,
  Alignment.center,
];

/// Largeur visible de la carte suivante, pour montrer qu'il y en a d'autres.
const deckPeek = 28.0;

/// Marge des cartes et écart entre deux cartes.
const _deckMargin = 20.0;
const _deckGap = 12.0;

/// Pile de cartes qui défile de côté, une carte à la fois, avec les points
/// de la carte en cours dessous. Les cartes gardent leur hauteur, alignées
/// en haut ; la suivante dépasse de [deckPeek].
class CardDeck extends StatefulWidget {
  const CardDeck({super.key, required this.count, required this.itemBuilder});

  final int count;

  /// Construit la carte [index] de largeur [width].
  final Widget Function(BuildContext context, int index, double width)
  itemBuilder;

  @override
  State<CardDeck> createState() => _CardDeckState();
}

class _CardDeckState extends State<CardDeck> {
  final _scroll = ScrollController();
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double get _cardWidth {
    final screen = MediaQuery.sizeOf(context).width;
    // Sur tablette, des cartes de téléphone plutôt qu'une carte géante.
    return math.min(screen - _deckMargin - _deckGap - deckPeek, 420);
  }

  void _onScroll() {
    final position = _scroll.position;
    final extent = _cardWidth + _deckGap;
    // En butée à droite, la dernière carte est en cours même si elle n'est
    // pas alignée sur la marge.
    final i = position.pixels >= position.maxScrollExtent - 1
        ? widget.count - 1
        : (position.pixels / extent).round().clamp(0, widget.count - 1);
    if (i != _current) setState(() => _current = i);
  }

  @override
  Widget build(BuildContext context) {
    final width = _cardWidth;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: _CardSnapPhysics(extent: width + _deckGap),
          padding: const EdgeInsets.symmetric(horizontal: _deckMargin),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widget.count; i++) ...[
                if (i > 0) const SizedBox(width: _deckGap),
                SizedBox(
                  width: width,
                  child: widget.itemBuilder(context, i, width),
                ),
              ],
            ],
          ),
        ),
        if (widget.count > 1) ...[
          const SizedBox(height: 18),
          _Pager(count: widget.count, current: _current),
        ],
      ],
    );
  }
}

/// Défilement carte par carte : relâchée, la pile s'arrête sur le début
/// d'une carte (ou en butée), comme `scroll-snap` dans les maquettes.
class _CardSnapPhysics extends ScrollPhysics {
  const _CardSnapPhysics({required this.extent, super.parent});

  /// Pas entre le début de deux cartes.
  final double extent;

  @override
  _CardSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _CardSnapPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // En butée, le rebond ou l'arrêt de la physique de la plateforme.
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    var page = position.pixels / extent;
    // Un geste franc passe à la carte d'à côté.
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    final target = (page.roundToDouble() * extent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// Points de la carte en cours, décoratifs : chaque carte s'annonce déjà.
class _Pager extends StatelessWidget {
  const _Pager({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            AnimatedScale(
              scale: i == current ? 1.15 : 1,
              duration: const Duration(milliseconds: 200),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == current ? colors.ink : colors.dot,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Carte en chemise de dossier : languette en haut ([tab] : texte et
/// couleur), feuille qui s'ouvre au toucher.
class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.tab,
    required this.tabColor,
    required this.tabSide,
    required this.onTap,
    required this.semanticsLabel,
    required this.children,
    this.link = false,
  });

  final String tab;
  final Color tabColor;
  final Alignment tabSide;
  final VoidCallback? onTap;

  /// Description de toute la carte pour les lecteurs d'écran.
  final String semanticsLabel;

  /// Vrai si la carte ouvre une page web (le dossier législatif).
  final bool link;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: !link && onTap != null,
      link: link,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // La languette, en retrait du bord de la feuille.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _tabInset),
            child: Align(
              alignment: tabSide,
              child: ClipPath(
                clipper: const _TabClipper(),
                child: ColoredBox(
                  color: colors.surface,
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.fromLTRB(18, 7, 18, 0),
                    child: Text(
                      tab,
                      style: HemicycleText.metaStrong.copyWith(color: tabColor),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Feuille à angle droit, sans ombre.
          Material(
            color: colors.surface,
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Retrait de la languette depuis le bord de la feuille.
const _tabInset = 24.0;

/// Languette en trapèze, plus large à sa base, posée sur la feuille.
class _TabClipper extends CustomClipper<Path> {
  const _TabClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(10, 0)
    ..lineTo(size.width - 10, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_TabClipper old) => false;
}

/// Largeur de la figure (hémicycle, arc) d'une carte de largeur [card].
double _figureWidth(double card) => math.min(300, card - 32);

/// Titre court d'une carte, sous la figure.
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
    child: Text(
      text,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: HemicycleText.displaySm.copyWith(color: context.colors.ink),
    ),
  );
}

/// Carte du prochain vote solennel : l'arc vide (pas encore de résultat),
/// le jour en grand dans son creux, le mois, le jour et l'heure, le titre
/// court. Ouvre le dossier législatif.
class _VoteCard extends StatelessWidget {
  const _VoteCard(
    this.item, {
    required this.width,
    required this.tab,
    required this.now,
  });

  final UpcomingItem item;
  final double width;
  final Alignment tab;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final figure = _figureWidth(width);
    final url = item.dossierUrl;
    return _FolderCard(
      tab: 'Vote solennel',
      tabColor: colors.ink,
      tabSide: tab,
      link: url != null,
      onTap: url == null
          ? null
          : () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      semanticsLabel: [
        'Vote solennel',
        upcomingDayLabel(item.startsAt, now: now, long: true),
        'à partir de ${parisHourLabel(item.startsAt)}',
        item.shortTitle,
      ].join(', '),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Center(
            child: SizedBox(
              width: figure,
              height: figure * _HollowArcPainter.aspect,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _HollowArcPainter(colors.rule)),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${parisDay(item.startsAt).day}',
                          style: HemicycleText.displayXl.copyWith(
                            color: colors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          upcomingVoteLine(item.startsAt),
                          style: HemicycleText.bodySmall.copyWith(
                            color: colors.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _CardTitle(item.shortTitle),
      ],
    );
  }
}

/// L'arc vide des maquettes : deux demi-anneaux au filet, dans une boîte de
/// 300 × 162 unités mise à l'échelle.
class _HollowArcPainter extends CustomPainter {
  _HollowArcPainter(this.color);

  final Color color;

  /// Rapport hauteur / largeur de la boîte.
  static const aspect = 162 / 300;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 300;
    final center = Offset(150 * unit, 150 * unit);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16 * unit
      ..isAntiAlias = true;
    for (final radius in [128.0, 98.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * unit),
        math.pi,
        math.pi,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HollowArcPainter old) => old.color != color;
}

/// Carte d'une décision : l'hémicycle aux places réelles (l'arc de l'index
/// en attendant le détail, ou sans sièges), « Adopté » ou « Rejeté » et les
/// trois chiffres avec leur symbole, le titre court. Ouvre le détail.
class _DecisionCard extends StatelessWidget {
  const _DecisionCard(
    this.decision, {
    required this.detail,
    required this.width,
    required this.tab,
    required this.now,
  });

  final DecisionSummary decision;

  /// Fichier de détail, s'il est arrivé.
  final DecisionDetail? detail;

  final double width;
  final Alignment tab;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final figure = _figureWidth(width);
    final result = decision.result;
    final detail = this.detail;
    final tally = detail?.count?.tally ?? decision.count;
    final seats =
        detail != null &&
            decision.voteMode == VoteMode.scrutinPublic &&
            detail.count != null &&
            canDrawSeats(detail.seats)
        ? detail.seats
        : null;
    final height = figure * HemicycleSeats.aspect;
    final title = capitalize(decision.compactTitle);
    return _FolderCard(
      tab: formatShortFrenchDate(
        decision.date,
        withYear: decision.date.year != now.year,
      ),
      tabColor: resultColor(context, result),
      tabSide: tab,
      onTap: () => Navigator.of(
        context,
      ).pushNamed(decisionRouteName(decision.id), arguments: decision),
      semanticsLabel: [
        if (tally != null && decision.voteMode != VoteMode.mainLevee)
          hemicycleSeatsLabel(result, tally)
        else
          resultWord(result),
        formatFrenchDay(decision.date),
        title,
      ].join(', '),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Center(
            child: seats != null
                ? HemicycleSeats(
                    seats: seats,
                    groups: detail!.groups,
                    result: result,
                    count: detail.count!.tally,
                    width: figure,
                  )
                // Même hauteur que l'hémicycle : la carte ne saute pas quand
                // les sièges arrivent.
                : SizedBox(
                    width: figure,
                    height: height,
                    child: Center(
                      child: VoteArc(
                        result: result,
                        count: decision.count,
                        voteMode: decision.voteMode,
                        arc: decision.arc,
                        width: math.min(figure, height / VoteArc.aspect),
                      ),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // Les chiffres à droite du résultat ; dessous si la place manque
          // (grandes tailles de texte).
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                resultWord(result),
                style: HemicycleText.displaySm.copyWith(
                  color: resultColor(context, result),
                ),
              ),
              if (tally != null && decision.voteMode != VoteMode.mainLevee)
                _Tally(tally),
            ],
          ),
        ),
        if (seats != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: NoVoteNote(seats),
            ),
          ),
        _CardTitle(title),
      ],
    );
  }
}

/// Les trois chiffres, sans mots : le symbole de chaque vote (forme des
/// sièges), puis le chiffre.
class _Tally extends StatelessWidget {
  const _Tally(this.tally);

  final VoteTally tally;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final parts = [
      (VotePosition.pour, tally.pour, colors.pour),
      (VotePosition.contre, tally.contre, colors.contre),
      (VotePosition.abstention, tally.abstentions, colors.ink2),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (position, value, color)) in parts.indexed) ...[
          if (i > 0) const SizedBox(width: 14),
          VoteGlyph(position, color: color),
          const SizedBox(width: 6),
          Text('$value', style: HemicycleText.tally.copyWith(color: color)),
        ],
      ],
    );
  }
}

/// Bouton principal : pleine largeur, rectangle à l'encre (thème).
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      FilledButton(onPressed: onPressed, child: Text(label));
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: HemicycleText.bodySmall.copyWith(color: context.colors.ink2),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}
