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

    var youtubeVideoID: String? {
        guard let url = sourceURL else { return nil }
        return Self.extractYouTubeVideoID(from: url)
    }

    static func extractYouTubeVideoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let id = path.components(separatedBy: "/").first ?? ""
            return id.isEmpty ? nil : id
        }
        if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let v = components.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                    return v
                }
            }
            let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if let first = segments.first {
                if ["embed", "shorts", "v", "live"].contains(first), segments.count > 1 {
                    let id = segments[1]
                    return id.isEmpty ? nil : id
                }
            }
        }
        return nil
    }
}

enum UnitSystem: String, CaseIterable, Identifiable, Codable {
    case standard = "Recipe"
    case metric = "Metric"
    case imperial = "Imperial"

    var id: String { rawValue }
    var title: String { rawValue }

    static var regionalDefault: UnitSystem {
        if #available(iOS 16.0, macOS 13.0, *) {
            return Locale.current.measurementSystem == .metric ? .metric : .imperial
        } else {
            return Locale.current.usesMetricSystem ? .metric : .imperial
        }
    }
}

struct Ingredient: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var amount: Double
    var unit: String

    /// Formats a raw number into readable kitchen fractions or trimmed decimals.
    static func formatNumber(_ value: Double) -> String {
        let whole = value.rounded(.down)
        let wholeText = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), whole)
        let remainder = value - whole
        let fractions: [(Double, String)] = [
            (0.125, "⅛"), (0.25, "¼"), (1.0 / 3.0, "⅓"),
            (0.375, "⅜"), (0.5, "½"), (0.625, "⅝"),
            (2.0 / 3.0, "⅔"), (0.75, "¾"), (0.875, "⅞")
        ]
        if remainder < 0.000_01 {
            return wholeText
        } else if let fraction = fractions.first(where: { abs($0.0 - remainder) < 0.000_01 }) {
            return (whole == 0 ? "" : wholeText) + fraction.1
        } else {
            return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
                .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        }
    }

    /// Converts raw amount and unit according to the desired unit system.
    func converted(amount: Double, unit: String, system: UnitSystem) -> (Double, String) {
        guard system != .standard else { return (amount, unit) }
        let u = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        switch system {
        case .standard:
            return (amount, unit)

        case .metric:
            switch u {
            case "cup", "cups":
                let ml = amount * 240.0
                return ml >= 1000 ? (ml / 1000.0, "L") : (ml, "ml")
            case "tbsp", "tablespoon", "tablespoons":
                return (amount * 15.0, "ml")
            case "tsp", "teaspoon", "teaspoons":
                return (amount * 5.0, "ml")
            case "oz", "ounce", "ounces":
                return (amount * 28.3495, "g")
            case "lb", "lbs", "pound", "pounds":
                let g = amount * 453.592
                return g >= 1000 ? (g / 1000.0, "kg") : (g, "g")
            default:
                return (amount, unit)
            }

        case .imperial:
            switch u {
            case "g", "gram", "grams":
                let oz = amount / 28.3495
                return oz >= 16 ? (oz / 16.0, "lbs") : (oz, "oz")
            case "kg", "kilogram", "kilograms":
                return (amount * 2.20462, "lbs")
            case "ml", "milliliter", "milliliters":
                if amount >= 240 {
                    return (amount / 240.0, "cups")
                } else if amount >= 15 {
                    return (amount / 15.0, "tbsp")
                } else {
                    return (amount / 5.0, "tsp")
                }
            case "l", "liter", "liters":
                return (amount * 4.22675, "cups")
            default:
                return (amount, unit)
            }
        }
    }

    /// Scales the complete ingredient quantity, optionally converting between Metric and Imperial.
    /// Common kitchen fractions stay readable; other values retain three decimals.
    func quantity(for diners: Int, baseServings: Int, unitSystem: UnitSystem = .standard) -> String {
        let scaled = amount * Double(max(0, diners)) / Double(max(1, baseServings))
        let value = scaled.isFinite ? max(0, scaled) : 0

        let (convertedValue, convertedUnit) = converted(amount: value, unit: unit, system: unitSystem)

        let finalNumber: String
        let cleanUnit = convertedUnit.lowercased()
        if (cleanUnit == "g" || cleanUnit == "ml") && convertedValue >= 5.0 {
            finalNumber = "\(Int(convertedValue.rounded()))"
        } else {
            finalNumber = Self.formatNumber(convertedValue)
        }

        return convertedUnit.isEmpty ? finalNumber : "\(finalNumber) \(convertedUnit)"
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
