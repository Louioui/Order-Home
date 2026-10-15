import Foundation

enum HouseholdMode: String, Codable, CaseIterable, Identifiable {
    case family
    case couple

    var id: String { rawValue }
    var title: String { self == .family ? "Family Table" : "Table for Two" }
    var subtitle: String {
        self == .family ? "Find the meal your table loves." : "Find something you both love."
    }
}

enum DinnerStage: String, Codable, CaseIterable {
    case pitching
    case voting
    case ticketLocked
    case cooking
    case served

    var title: String {
        switch self {
        case .pitching: "Open for cravings"
        case .voting: "Taking your orders"
        case .ticketLocked: "Order confirmed"
        case .cooking: "In the kitchen"
        case .served: "Dinner is served"
        }
    }
}

struct Recipe: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var cuisine: String
    var category: String
    var minutes: Int
    var servings: Int
    var imageName: String
    var ingredients: [Ingredient]
    var steps: [RecipeStep]
    var sourceURL: URL?
}

struct Ingredient: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var amount: Double
    var unit: String

    /// Scales the complete ingredient quantity, including fractional servings.
    /// Common kitchen fractions stay readable; other values retain three decimals.
    func quantity(for diners: Int, baseServings: Int) -> String {
        let scaled = amount * Double(max(0, diners)) / Double(max(1, baseServings))
        let value = scaled.isFinite ? max(0, scaled) : 0
        let whole = value.rounded(.down)
        let wholeText = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), whole)
        let remainder = value - whole
        let fractions: [(Double, String)] = [
            (0.125, "⅛"), (0.25, "¼"), (1.0 / 3.0, "⅓"),
            (0.375, "⅜"), (0.5, "½"), (0.625, "⅝"),
            (2.0 / 3.0, "⅔"), (0.75, "¾"), (0.875, "⅞")
        ]
        let number: String
        if remainder < 0.000_01 {
            number = wholeText
        } else if let fraction = fractions.first(where: { abs($0.0 - remainder) < 0.000_01 }) {
            number = (whole == 0 ? "" : wholeText) + fraction.1
        } else {
            number = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
                .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        }
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

struct RecipeStep: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var instruction: String
    var timerSeconds: Int?
}

struct Member: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var emoji: String
    var role: String
    var dietaryNotes: String
    var attending: Bool
}

enum Reaction: Int, Codable, CaseIterable, Identifiable {
    case pass = 0
    case down = 1
    case love = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .pass: "Pass tonight"
        case .down: "I'm down"
        case .love: "Craving this"
        }
    }
    var emoji: String {
        switch self {
        case .pass: "✋"
        case .down: "👌"
        case .love: "🔥"
        }
    }
}

struct Vote: Codable, Hashable, Identifiable {
    var recipeID: String
    var memberID: String
    var reaction: Reaction
    var id: String { "\(memberID):\(recipeID)" }
}

struct DinnerSession: Codable, Equatable {
    var id: String
    var stage: DinnerStage
    var recipeIDs: [String]
    var winnerID: String?
    var deadline: Date
    var stepIndex: Int
    var checkedIngredientIDs: Set<String>
    var missingIngredientIDs: Set<String>
    var completedStepIDs: Set<String>
    var timerEnd: Date?
    var timerTitle: String?

    static func fresh(now: Date = Date()) -> DinnerSession {
        DinnerSession(
            id: UUID().uuidString,
            stage: .pitching,
            recipeIDs: [],
            winnerID: nil,
            deadline: now.addingTimeInterval(60 * 60),
            stepIndex: 0,
            checkedIngredientIDs: [],
            missingIngredientIDs: [],
            completedStepIDs: [],
            timerEnd: nil,
            timerTitle: nil
        )
    }
}

struct Household: Codable, Equatable {
    var name: String
    var mode: HouseholdMode
    var members: [Member]
}

/// One person's verdict on a dinner after eating it.
enum DinnerRating: String, Codable, CaseIterable, Identifiable {
    case loved
    case good
    case tweak

    var id: String { rawValue }
    var title: String {
        switch self {
        case .loved: "Loved it"
        case .good: "It was good"
        case .tweak: "Needs a tweak"
        }
    }
    var emoji: String {
        switch self {
        case .loved: "😍"
        case .good: "👍"
        case .tweak: "🔄"
        }
    }
}

/// A dinner that reached the table, kept so the House Menu can remember it.
/// The dish title and diner names are copied in, so an entry still reads
/// correctly if the recipe or the table later changes.
struct DinnerRecord: Identifiable, Codable, Equatable {
    /// The `DinnerSession` id. There is exactly one record per dinner.
    var id: String
    var recipeID: String
    var recipeTitle: String
    var servedAt: Date
    var dinerNames: [String]
    /// Ids of the people who were at the table, so only they can rate this dinner
    /// even if the household changes afterwards. Optional so records saved before
    /// this field existed still load; those fall back to who is attending now.
    var dinerIDs: [String]?
    /// Member id to `DinnerRating.rawValue`. Raw strings, so a rating a future
    /// version adds is ignored here instead of failing the whole save file.
    var ratings: [String: String]

    func rating(for memberID: String) -> DinnerRating? {
        ratings[memberID].flatMap(DinnerRating.init(rawValue:))
    }
    var allRatings: [DinnerRating] {
        ratings.values.compactMap(DinnerRating.init(rawValue:))
    }
}

/// Decodes the entries it can read and drops the rest. One damaged entry, or a
/// value that is not a list at all, must never cost someone their saved kitchen.
struct LossyList<Element: Codable>: Codable {
    var elements: [Element]

    init(_ elements: [Element]) { self.elements = elements }

    init(from decoder: Decoder) throws {
        guard var container = try? decoder.unkeyedContainer() else { elements = []; return }
        var decoded: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) { decoded.append(element) }
            // A failed decode does not advance the container, so consume the entry.
            else { _ = try? container.decode(Skipped.self) }
        }
        elements = decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for element in elements { try container.encode(element) }
    }

    private struct Skipped: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
