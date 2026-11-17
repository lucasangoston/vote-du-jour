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
import 'in_debate/in_debate_page.dart' show finalVoteLabel;
import 'in_debate/in_debate_route.dart';
import 'provisional_badge.dart';
import 'relative_date.dart';
import 'rubric.dart';
import 'skeleton.dart';
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

/// Le texte en débat dans l'hémicycle (#77) : ouvert depuis la notification,
/// il se retrouve ensuite sur l'accueil.
class InDebateCard extends HomeCard {
  const InDebateCard(this.inDebate);

  final InDebate inDebate;
}

/// Cartes de l'accueil : le texte en débat, tant que son vote sur
/// l'ensemble n'est pas publié ; le prochain vote solennel (s'il y en a un à
/// l'ordre du jour) ; puis les [homeDecisionCount] dernières décisions, une
/// par texte (la plus récente : l'index est trié du plus récent au plus
/// ancien).
List<HomeCard> homeCards(DecisionIndex index, {required DateTime now}) {
  final debate = index.inDebate;
  final debating =
      debate != null &&
      !index.decisions.any(
        (d) =>
            d.dossierUrl == debate.dossierUrl &&
            d.type == DecisionType.ensembleTexte &&
            !d.date.isBefore(
              DateTime.utc(
                debate.startsAt.year,
                debate.startsAt.month,
                debate.startsAt.day,
              ),
            ),
      );
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
    if (debating) InDebateCard(debate),
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

  /// Détails déjà lus, par décision, pour leurs sièges.
  final _details = <String, DecisionDetail>{};
  final _pendingDetails = <String>{};

  /// Détails introuvables : la carte garde l'arc de l'index.
  final _missingDetails = <String>{};

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
  /// En attendant, la carte est un squelette ([_waitsForSeats]) ; s'il
  /// manque, elle garde l'arc de l'index.
  void _loadSeats(DecisionIndex index) {
    final repository =
        widget.detailRepository ?? defaultDecisionDetailRepository;
    for (final card in homeCards(index, now: _now)) {
      if (card case DecisionCard(
        :final decision,
      ) when _waitsForSeats(decision) && _pendingDetails.add(decision.id)) {
        repository
            .fetch(decision.id)
            .then((detail) {
              if (mounted) setState(() => _details[decision.id] = detail);
            })
            .catchError((Object e) {
              debugPrint('Accueil : sièges de ${decision.id} absents : $e');
              if (mounted) setState(() => _missingDetails.add(decision.id));
            })
            .whenComplete(() => _pendingDetails.remove(decision.id));
      }
    }
  }

  /// La carte de [decision] attend-elle son fichier de détail ? Rien ne
  /// s'affiche à moitié (l'arc puis l'hémicycle) : squelette, puis la carte
  /// complète.
  bool _waitsForSeats(DecisionSummary decision) =>
      decision.voteMode == VoteMode.scrutinPublic &&
      !_details.containsKey(decision.id) &&
      !_missingDetails.contains(decision.id);

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
        // Le contenu ne passe jamais sous la barre d'état (heure, réseau) ni
        // sous l'encoche, même en défilant.
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, viewport) => RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    // Les cartes prennent toute la hauteur libre ; sur un
                    // écran trop court, l'accueil défile.
                    child: SizedBox(
                      height: math.max(viewport.maxHeight, homeMinHeight),
                      child: _page(context, padding),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(BuildContext context, EdgeInsets padding) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 4),
      const BrandBar(),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Semantics(
          header: true,
          child: Text(
            formatFrenchWeekdayDay(_now),
            style: HemicycleText.displayLg.copyWith(color: context.colors.ink),
          ),
        ),
      ),
      // Les cartes, de la date jusqu'au bouton.
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(child: _body(context)),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + padding.bottom),
        child: _PrimaryButton(
          label: 'Toutes les décisions',
          onPressed: _openList,
        ),
      ),
    ],
  );

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
      // Les cartes à leur place, en attendant l'index.
      return Semantics(
        label: 'Chargement des décisions',
        container: true,
        excludeSemantics: true,
        child: CardDeck(
          count: homeDecisionCount,
          itemBuilder: (context, i, width) => _SkeletonCard(width: width),
        ),
      );
    }
    final cards = homeCards(index, now: _now);
    if (cards.isEmpty) {
      return const _Message(text: 'Aucune décision publiée pour le moment.');
    }
    return CardDeck(
      count: cards.length,
      itemBuilder: (context, i, width) => switch (cards[i]) {
        InDebateCard(:final inDebate) => _InDebateCard(
          inDebate,
          upcoming: index.upcoming,
          width: width,
          now: _now,
        ),
        UpcomingVoteCard(:final item) => _VoteCard(
          item,
          width: width,
          now: _now,
        ),
        DecisionCard(:final decision) when _waitsForSeats(decision) =>
          Semantics(
            label: 'Chargement de la décision',
            container: true,
            excludeSemantics: true,
            child: _SkeletonCard(width: width),
          ),
        DecisionCard(:final decision) => _DecisionCard(
          decision,
          detail: _details[decision.id],
          width: width,
          now: _now,
        ),
      },
    );
  }
}

/// Hauteur de l'accueil en dessous de laquelle il défile plutôt que de
/// tasser les cartes.
const homeMinHeight = 600.0;

/// Largeur visible de la carte suivante, pour montrer qu'il y en a d'autres.
const deckPeek = 28.0;

/// Hauteur des points de la pile, écart compris.
const _pagerHeight = 18.0 + 7 * 1.15;

/// Rapport hauteur / largeur maximal d'une carte : sur tablette, une carte
/// de téléphone plutôt qu'une colonne étirée.
const _maxCardAspect = 1.75;

/// Marge des cartes et écart entre deux cartes.
const _deckMargin = 20.0;
const _deckGap = 12.0;

/// Pile de cartes qui défile de côté, une carte à la fois, avec les points
/// de la carte en cours dessous. Les cartes prennent toute la hauteur
/// donnée (jusqu'à [_maxCardAspect] fois leur largeur) ; la suivante dépasse
/// de [deckPeek].
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
    final pager = widget.count > 1 ? _pagerHeight : 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(
          constraints.maxHeight - pager,
          width * _maxCardAspect,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: _CardSnapPhysics(extent: width + _deckGap),
              padding: const EdgeInsets.symmetric(horizontal: _deckMargin),
              child: Row(
                children: [
                  for (var i = 0; i < widget.count; i++) ...[
                    if (i > 0) const SizedBox(width: _deckGap),
                    SizedBox(
                      width: width,
                      height: height,
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
      },
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

  // Ressort raide, sans rebond : la carte se cale en 0,2 s environ. Le
  // ressort par défaut traînait près d'une seconde, et un défilement en
  // cours ignore les touchers : il fallait appuyer deux fois sur une carte.
  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 600, ratio: 1);

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

/// Carte de l'accueil, aux couleurs de sa rubrique ([Rubric]) : bandeau
/// (pictogramme, nom, [detail]), cadre de la même couleur, feuille teintée
/// jusqu'en bas de la pile. Sous le bandeau, la figure ([children]) puis le
/// [title] dans toute la place qui reste. Elle s'ouvre au toucher.
class _RubricCard extends StatelessWidget {
  const _RubricCard({
    required this.rubric,
    required this.onTap,
    required this.semanticsLabel,
    required this.children,
    required this.title,
    this.explanation,
    this.detail,
    this.link = false,
  });

  /// Titre court, sous la figure.
  final String title;

  /// Phrase d'explication du résumé, sous le titre si la place le permet.
  final String? explanation;

  final Rubric rubric;

  /// Précision à droite du bandeau (date d'une décision).
  final String? detail;

  final VoidCallback? onTap;

  /// Description de toute la carte pour les lecteurs d'écran.
  final String semanticsLabel;

  /// Vrai si la carte ouvre une page web (le dossier législatif).
  final bool link;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Semantics(
      button: !link && onTap != null,
      link: link,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      // Feuille à angle droit, sans ombre.
      child: Material(
        color: rubric.sheet(context),
        shape: Border.all(color: rubric.fill(b), width: 3),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RubricBand(rubric, detail: detail),
              Expanded(
                child: _CardBody(
                  head: children,
                  title: title,
                  explanation: explanation,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Largeur de la figure (hémicycle, arc) d'une carte de largeur [card].
double _figureWidth(double card) => math.min(300, card - 32);

/// Marges du texte d'une carte.
const _textPadding = EdgeInsets.fromLTRB(22, 18, 22, 22);

/// Écart entre le titre et l'explication.
const _explanationGap = 10.0;

/// Tailles du titre, de la plus grande à la plus petite : il prend la plus
/// grande qui le montre en entier.
const titleSizes = [32.0, 29.0, 26.0, 23.0, 20.0, 18.0];

/// Lignes de titre toujours gardées sous la figure : si la place manque
/// (petit écran, grand texte), la figure se réduit d'abord.
const _titleMinLines = 3;

/// Lignes d'explication en dessous desquelles elle n'est pas montrée.
const _explanationMinLines = 2;

/// Plus petite taille du titre à côté d'une explication : le titre reste
/// le plus visible, l'explication ne le fait pas rapetisser au-delà.
const _titleSizeWithExplanation = 26.0;

TextStyle _titleStyle(BuildContext context, double size) =>
    HemicycleText.displaySm.copyWith(fontSize: size, color: context.colors.ink);

TextStyle _explanationStyle(BuildContext context) =>
    HemicycleText.bodySerif.copyWith(color: context.colors.body);

/// Corps d'une carte : la figure et ses chiffres ([head]) en haut, à leur
/// taille tant que [_titleMinLines] lignes de titre tiennent dessous, puis
/// le texte ([_CardText]).
class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.head,
    required this.title,
    required this.explanation,
  });

  final List<Widget> head;
  final String title;
  final String? explanation;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final line = _lineHeights(
        'X',
        _titleStyle(context, titleSizes.last),
        maxWidth: double.infinity,
        textScaler: MediaQuery.textScalerOf(context),
      ).first;
      final reserve = _textPadding.vertical + line * _titleMinLines;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(0, constraints.maxHeight - reserve),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: head,
                ),
              ),
            ),
          ),
          Expanded(
            child: _CardText(title: title, explanation: explanation),
          ),
        ],
      );
    },
  );
}

/// Texte d'une carte, sous la figure, dans toute la place qui reste : le
/// titre court, puis l'explication du résumé s'il y en a une ([fitCardText]).
class _CardText extends StatelessWidget {
  const _CardText({required this.title, required this.explanation});

  final String title;
  final String? explanation;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _textPadding,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final fit = fitCardText(
          title: title,
          explanation: explanation,
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          titleStyle: (size) => _titleStyle(context, size),
          explanationStyle: _explanationStyle(context),
          textScaler: MediaQuery.textScalerOf(context),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clamped(title, _titleStyle(context, fit.size), fit.titleLines),
            if (fit.showExplanation) ...[
              const SizedBox(height: _explanationGap),
              _clamped(
                explanation!,
                _explanationStyle(context),
                fit.explanationLines,
              ),
            ],
          ],
        );
      },
    ),
  );

  /// [text] sur [maxLines] lignes au plus, coupé par « … » ; sans limite,
  /// en entier (avec `overflow` mais sans `maxLines`, un texte tient sur une
  /// seule ligne).
  static Widget _clamped(String text, TextStyle style, int? maxLines) => Text(
    text,
    style: style,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
  );
}

/// Mise en page du texte d'une carte : taille du titre, explication montrée
/// ou non, et lignes du titre et de l'explication (`null` : en entier).
typedef CardTextFit = ({
  double size,
  int? titleLines,
  bool showExplanation,
  int? explanationLines,
});

/// Place le titre et l'explication dans une boîte de [maxWidth] ×
/// [maxHeight], dans cet ordre de préférence :
/// 1. le titre et l'explication en entier, titre à la plus grande des
///    [titleSizes] possible ;
/// 2. le titre en entier, l'explication coupée par « … » (au moins
///    [_explanationMinLines] lignes) ;
///
/// (avec l'explication, le titre garde au moins [_titleSizeWithExplanation]) ;
/// 3. le titre seul, en entier ;
/// 4. le titre seul à la plus petite taille, coupé à la dernière ligne qui
///    tient (au moins une).
CardTextFit fitCardText({
  required String title,
  required String? explanation,
  required double maxWidth,
  required double maxHeight,
  required TextStyle Function(double size) titleStyle,
  required TextStyle explanationStyle,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final titles = {
    for (final size in titleSizes)
      size: _lineHeights(
        title,
        titleStyle(size),
        maxWidth: maxWidth,
        textScaler: textScaler,
      ),
  };
  double total(List<double> lines) => lines.fold(0, (a, b) => a + b);
  final fitting = [
    for (final size in titleSizes)
      if (total(titles[size]!) <= maxHeight) size,
  ];
  if (explanation != null && fitting.isNotEmpty) {
    final body = _lineHeights(
      explanation,
      explanationStyle,
      maxWidth: maxWidth,
      textScaler: textScaler,
    );
    int linesIn(double height) {
      var count = 0;
      var bottom = 0.0;
      for (final line in body) {
        bottom += line;
        if (bottom > height) break;
        count++;
      }
      return count;
    }

    final room = {
      for (final size in fitting)
        if (size >= _titleSizeWithExplanation)
          size: linesIn(maxHeight - total(titles[size]!) - _explanationGap),
    };
    for (final size in room.keys) {
      if (room[size]! >= body.length) {
        return (
          size: size,
          titleLines: null,
          showExplanation: true,
          explanationLines: null,
        );
      }
    }
    for (final size in room.keys) {
      if (room[size]! >= _explanationMinLines) {
        return (
          size: size,
          titleLines: null,
          showExplanation: true,
          explanationLines: room[size],
        );
      }
    }
  }
  if (fitting.isNotEmpty) {
    return (
      size: fitting.first,
      titleLines: null,
      showExplanation: false,
      explanationLines: null,
    );
  }
  var count = 0;
  var bottom = 0.0;
  for (final line in titles[titleSizes.last]!) {
    bottom += line;
    if (bottom > maxHeight) break;
    count++;
  }
  return (
    size: titleSizes.last,
    titleLines: math.max(1, count),
    showExplanation: false,
    explanationLines: null,
  );
}

/// Hauteur de chaque ligne de [text] mis en page sur [maxWidth].
List<double> _lineHeights(
  String text,
  TextStyle style, {
  required double maxWidth,
  required TextScaler textScaler,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  final lines = [for (final l in painter.computeLineMetrics()) l.height];
  painter.dispose();
  return lines;
}

/// Carte du prochain vote solennel : l'arc vide (pas encore de résultat),
/// le jour en grand dans son creux, le mois, le jour et l'heure, le titre
/// court. Ouvre le dossier législatif.
class _VoteCard extends StatelessWidget {
  const _VoteCard(this.item, {required this.width, required this.now});

  final UpcomingItem item;
  final double width;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final figure = _figureWidth(width);
    final url = item.dossierUrl;
    return _RubricCard(
      rubric: Rubric.voteSolennel,
      link: url != null,
      // Sans dossier connu, la carte répond quand même : une grande carte
      // qui ne réagit pas au toucher a l'air cassée.
      onTap: url == null
          ? () => ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(content: Text(upcomingNoLinkNotice)),
              )
          : () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      semanticsLabel: [
        'Vote solennel',
        upcomingDayLabel(item.startsAt, now: now, long: true),
        'à partir de ${parisHourLabel(item.startsAt)}',
        item.shortTitle,
      ].join(', '),
      title: item.shortTitle,
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
                    // L'arc vide dans la couleur de la rubrique : un gris
                    // clair se perdrait sur la feuille teintée.
                    child: CustomPaint(
                      painter: _HollowArcPainter(
                        Color.lerp(
                          Rubric.voteSolennel.sheet(context),
                          Rubric.voteSolennel.fill(
                            Theme.of(context).brightness,
                          ),
                          0.22,
                        )!,
                      ),
                    ),
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
      ],
    );
  }
}

/// Message d'une carte de vote à venir dont le dossier n'est pas connu.
const upcomingNoLinkNotice = 'Le résultat s’affichera ici après le vote.';

/// Carte du texte en débat : l'hémicycle en attente (personne n'a encore
/// voté le texte), le vote final et les articles déjà votés, le titre
/// court. Ouvre l'écran « En débat ».
class _InDebateCard extends StatelessWidget {
  const _InDebateCard(
    this.inDebate, {
    required this.upcoming,
    required this.width,
    required this.now,
  });

  final InDebate inDebate;
  final List<UpcomingItem>? upcoming;
  final double width;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final summary = inDebate.summary;
    final title = capitalize(
      summary?.shortTitle ?? summary?.title ?? inDebate.shortTitle,
    );
    final finalVote = finalVoteLabel(inDebate, upcoming, now: now);
    final articles = inDebate.articles.length;
    return _RubricCard(
      rubric: Rubric.enDebat,
      onTap: () => Navigator.of(
        context,
      ).pushNamed(inDebateRouteName(inDebate.dossierRef)),
      semanticsLabel: ['En débat', finalVote, title].join(', '),
      title: title,
      explanation: summary?.explanation,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Center(child: WaitingHemicycle(width: _figureWidth(width))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            // « En débat » est déjà dans le bandeau : le vote final en grand.
            children: [
              Text(
                finalVote,
                style: HemicycleText.displaySm.copyWith(color: colors.ink),
              ),
            ],
          ),
        ),
        if (articles > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                articles > 1 ? '$articles articles votés' : '1 article voté',
                style: HemicycleText.meta.copyWith(color: colors.ink2),
              ),
            ),
          ),
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
/// sans fichier de détail ou sans sièges), « Adopté » ou « Rejeté » et les
/// trois chiffres avec leur symbole, le titre court. Ouvre le détail.
class _DecisionCard extends StatelessWidget {
  const _DecisionCard(
    this.decision, {
    required this.detail,
    required this.width,
    required this.now,
  });

  final DecisionSummary decision;

  /// Fichier de détail, s'il est arrivé.
  final DecisionDetail? detail;

  final double width;
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
    return _RubricCard(
      rubric: Rubric.decision,
      detail: formatShortFrenchDate(
        decision.date,
        withYear: decision.date.year != now.year,
      ),
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
      title: title,
      explanation: decision.explanation,
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
                : isProvisionalScrutin(decision)
                ? ProvisionalHemicycle(width: figure)
                // Même hauteur que l'hémicycle : toutes les cartes de la pile
                // gardent la même figure.
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
          )
        else if (isProvisionalScrutin(decision))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              provisionalGroupsNotice,
              style: HemicycleText.meta.copyWith(color: context.colors.ink2),
            ),
          ),
      ],
    );
  }
}

/// Squelette d'une carte de décision, aux mêmes places : bandeau,
/// hémicycle, résultat et chiffres, deux lignes de titre.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final figure = _figureWidth(width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 52,
          color: colors.raised,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          child: SkeletonBlock(width: 110, height: 16, color: colors.surface),
        ),
        Expanded(
          child: ColoredBox(
            color: colors.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: SkeletonBlock(
                      width: figure,
                      height: figure * HemicycleSeats.aspect,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SkeletonBlock(width: 96, height: 28),
                      SkeletonBlock(width: 120, height: 18),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBlock(width: width * 0.7, height: 22),
                        const SizedBox(height: 8),
                        SkeletonBlock(width: width * 0.45, height: 22),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
