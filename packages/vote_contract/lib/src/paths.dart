/// Version du schéma JSON produite par ce paquet.
///
/// Règle : ajouter un champ optionnel ne change pas la version (les lecteurs
/// ignorent les champs inconnus) ; supprimer, renommer ou changer le sens d'un
/// champ l'incrémente.
const int schemaVersion = 1;

/// Chemin de l'index des dernières décisions, relatif à l'URL publique.
const String indexPath = 'v$schemaVersion/latest.json';
