import 'package:vote_contract/vote_contract.dart';

/// Mention affichée à côté du badge d'une décision votée à main levée
/// (« Adopté à main levée ») : il n'y a ni décompte ni vote par groupe.
const mainLeveeLabel = 'à main levée';

/// Mention du mode de vote à afficher, ou `null` pour un scrutin public.
String? voteModeLabel(VoteMode mode) => switch (mode) {
  VoteMode.scrutinPublic => null,
  VoteMode.mainLevee => mainLeveeLabel,
};
