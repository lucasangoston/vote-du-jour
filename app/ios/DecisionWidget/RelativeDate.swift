import Foundation

/// Dates relatives des décisions (« Aujourd'hui », « Hier », « Il y a 3 jours »),
/// calculées pour l'instant d'affichage de chaque entrée de la timeline. Mêmes
/// règles que l'app (`lib/src/relative_date.dart`) :
/// - l'écart se compte en jours de calendrier dans le fuseau du téléphone (un vote
///   du vendredi est « Il y a 3 jours » le lundi) ;
/// - au-delà de six jours, la date complète (« 13 octobre 2026 ») ;
/// - une date future (horloge décalée) est affichée comme « Aujourd'hui ».
///
/// Fonction pure, compilée aussi dans `RunnerTests` pour ses tests.
enum RelativeDate {
  private static let months = [
    "janvier", "février", "mars", "avril", "mai", "juin",
    "juillet", "août", "septembre", "octobre", "novembre", "décembre",
  ]

  /// Libellé du jour `day` (`AAAA-MM-JJ`) vu depuis `now`, dans le fuseau de
  /// `calendar`. Un jour illisible est rendu tel quel.
  static func label(day: String, now: Date, calendar: Calendar = .current) -> String {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]) else { return day }
    let today = calendar.dateComponents([.year, .month, .day], from: now)
    // Deux minuits UTC : pas de décalage d'heure d'été dans la différence.
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    guard
      let voteDay = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
      let todayDay = utc.date(
        from: DateComponents(year: today.year, month: today.month, day: today.day)),
      let days = utc.dateComponents([.day], from: voteDay, to: todayDay).day
    else { return day }
    switch days {
    case ...0: return "Aujourd'hui"
    case 1: return "Hier"
    case 2..<7: return "Il y a \(days) jours"
    default: return fullDate(year: parts[0], month: parts[1], day: parts[2])
    }
  }

  /// « 13 octobre 2026 » (« 1er » pour le premier du mois).
  static func fullDate(year: Int, month: Int, day: Int) -> String {
    "\(day == 1 ? "1er" : String(day)) \(months[month - 1]) \(year)"
  }
}
