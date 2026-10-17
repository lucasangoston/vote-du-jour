/// Contrat de données entre le job de publication et l'app.
///
/// Le job écrit un [DecisionIndex] en JSON dans le bucket public, l'app le
/// relit. Toute évolution non rétrocompatible du format incrémente
/// [schemaVersion] et se publie sous un nouveau chemin ([indexPath]), pour que
/// les anciennes versions de l'app continuent de lire l'ancien format.
library;

export 'src/decision.dart';
export 'src/decision_index.dart';
export 'src/paths.dart';
