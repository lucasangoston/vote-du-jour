import 'package:vote_contract/vote_contract.dart';

/// Mention d'une décision lue sur le site de l'Assemblée pendant la séance,
/// pas encore confirmée par le jeu de données officiel (ticket #10).
const provisionalLabel = 'provisoire';

/// Mention du statut à afficher, ou `null` pour une décision confirmée.
String? statusLabel(DecisionStatus status) => switch (status) {
  DecisionStatus.provisoire => provisionalLabel,
  DecisionStatus.confirmee => null,
};
