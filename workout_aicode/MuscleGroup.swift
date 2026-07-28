import Foundation

// MARK: - Muscle groups
//
// A closed set: the point is that every exercise maps onto the same small
// vocabulary, so sessions can be aggregated per muscle group (volume, time
// since last worked) across exercises — and, for shared data, across users.
//
// Raw values are stored and exported, so they must never change. Display
// labels can.
enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Hashable {
    case chest
    case back
    case traps
    case frontDelts
    case sideDelts
    case rearDelts
    case biceps
    case triceps
    case forearms
    case quads
    case hamstrings
    case glutes
    case calves
    case absCore
    case lowerBack

    var id: String { rawValue }

    /// Shown wherever a group is named. Quads and calves carry "/ul" and "/ll"
    /// — upper leg, lower leg — because on the diagram those groups cover the
    /// whole limb, and someone tapping their shin should not be told they
    /// picked "Calves". Abbreviated rather than spelled out: these labels sit
    /// in narrow buttons beside the figures.
    var label: String {
        switch self {
        case .chest:      return "Chest"
        case .back:       return "Back (lats/mid-back)"
        case .traps:      return "Traps"
        case .frontDelts: return "Front Delts"
        case .sideDelts:  return "Side Delts"
        case .rearDelts:  return "Rear Delts"
        case .biceps:     return "Biceps"
        case .triceps:    return "Triceps"
        case .forearms:   return "Forearms"
        case .quads:      return "Quads/ul"
        case .hamstrings: return "Hamstrings"
        case .glutes:     return "Glutes"
        case .calves:     return "Calves/ll"
        case .absCore:    return "Abs/Core"
        case .lowerBack:  return "Lower Back"
        }
    }

    /// Short label for tight spots (filter chips, list trailing text).
    var shortLabel: String {
        switch self {
        case .back:       return "Back"
        case .frontDelts: return "Front delts"
        case .sideDelts:  return "Side delts"
        case .rearDelts:  return "Rear delts"
        default:          return label
        }
    }

    /// Most exercises are chosen by the big movers first; this is the order the
    /// pickers and filters present, not the declaration order.
    static var displayOrder: [MuscleGroup] { allCases }

    /// A secondary list is capped so the field stays a quick choice rather than
    /// an anatomy exercise.
    static let maximumSecondary = 4
}
