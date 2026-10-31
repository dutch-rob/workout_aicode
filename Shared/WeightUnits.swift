import Foundation

// A BYTE-IDENTICAL COPY of this file lives in the Watch target, which does not
// compile Shared/. Edit the two together: a Watch that disagreed with its
// phone about what a gram is would show the right number in the wrong unit.

// MARK: - Units, and what a stored weight means
//
// Until now a weight was a bare number: the wheels held integers and whether
// they meant kilograms or pounds was between the user and their gym. That was
// fine until the app had to do arithmetic across the two — body weight from
// Health against a machine set in pounds — and it produced a set logged at
// zero. See `BodyWeight`.
//
// WEIGHTS ARE NOW STORED IN GRAMS, as whole numbers, in the same `[Int]`
// fields as before. Grams because:
//
//   • it is unit-neutral, so switching between kg and lb re-presents the same
//     history rather than rewriting it;
//   • it is exact. A quarter of a pound is 113.398 grams and a quarter of a
//     kilogram is 250 — integers either way, with no floating-point drift
//     accumulating over a user's training history;
//   • it does not change the shape of a single model, which is what keeps this
//     out of the SwiftData trap described above WorkoutLogSchemaV6: the live
//     WorkoutLog class is V2's, and giving it differently-typed properties
//     would mean a new class of the same name, whose new properties SwiftData
//     silently drops.
//
// Nothing outside this file should do unit arithmetic. Read a stored value
// with `WeightUnit.current.display(grams:)` and write one back with
// `WeightUnit.current.grams(from:)`.

// Arithmetic on a number, and the unit a number is in. The project puts
// everything on the main actor unless it says otherwise, and this must say
// otherwise: the SwiftData models convert weights from their own methods,
// which are not on the main actor, and the conversion has nothing to be on
// an actor FOR — it reads a constant and multiplies.
nonisolated enum WeightUnit: String, CaseIterable, Identifiable {
    case kilograms
    case pounds

    var id: String { rawValue }

    /// What goes after a number on screen.
    var label: String {
        switch self {
        case .kilograms: return "kg"
        case .pounds:    return "lb"
        }
    }

    var gramsPerUnit: Double {
        switch self {
        case .kilograms: return 1000
        case .pounds:    return 453.59237
        }
    }

    static let key = "weightUnit"

    /// Pounds in the United States and Canada, kilograms everywhere else —
    /// which is what gym equipment is marked in, not what the country's
    /// official system is.
    static var regionDefault: WeightUnit {
        switch Locale.current.region?.identifier {
        case "US", "CA": return .pounds
        default:         return .kilograms
        }
    }

    static var current: WeightUnit {
        WeightUnit(rawValue: UserDefaults.standard.string(forKey: key) ?? "")
            ?? regionDefault
    }

    // MARK: Reading and writing stored weights

    /// A stored weight, in this unit, rounded to the nearest quarter.
    ///
    /// Quarters because that is the finest any plate or machine is marked in:
    /// half-pound increments on some machines, quarter-kilogram on others. A
    /// number that cannot be set on a machine is noise.
    func display(grams: Int) -> Double {
        Self.roundedToQuarter(Double(grams) / gramsPerUnit)
    }

    /// What to store for a number the user chose in this unit.
    func grams(from value: Double) -> Int {
        Int((value * gramsPerUnit).rounded())
    }

    static func roundedToQuarter(_ value: Double) -> Double {
        (value * 4).rounded() / 4
    }
}

// MARK: - Writing a weight down

// Formatting, in the same position as WeightUnit above it.
nonisolated enum WeightText {

    /// 130, 130¼, 130½, 130¾.
    ///
    /// Single characters for the quarters, which is the whole reason they are
    /// written this way: "130.25" is three characters wider than "130¼", and
    /// the wheels and log columns are already as tight as they go.
    static func string(_ value: Double) -> String {
        let quartered = WeightUnit.roundedToQuarter(value)
        let whole = quartered < 0 ? Int(quartered.rounded(.up)) : Int(quartered.rounded(.down))
        let fraction = abs(quartered - Double(whole))

        let glyph: String
        switch (fraction * 4).rounded() {
        case 1:  glyph = "¼"
        case 2:  glyph = "½"
        case 3:  glyph = "¾"
        default: glyph = ""
        }
        // "0½" rather than "½": a weight is a quantity, and a bare fraction
        // reads as a fraction OF something.
        return "\(whole)\(glyph)"
    }

    /// A stored weight, written in the unit the user reads.
    static func string(grams: Int, in unit: WeightUnit = .current) -> String {
        string(unit.display(grams: grams))
    }

    /// Reads back what `string` writes, and plain decimals besides: someone
    /// typing into the edit screen will write 130.5, not 130½.
    static func value(from text: String) -> Double? {
        var text = text.trimmingCharacters(in: .whitespaces)
        var fraction = 0.0
        for (glyph, amount) in [("¼", 0.25), ("½", 0.5), ("¾", 0.75)] where text.hasSuffix(glyph) {
            fraction = amount
            text.removeLast()
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return fraction > 0 ? fraction : nil }
        guard let whole = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return whole < 0 ? whole - fraction : whole + fraction
    }
}
