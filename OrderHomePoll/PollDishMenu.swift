import Foundation

/// The dishes someone can put on a chat poll. The Messages extension cannot see
/// the app's recipe catalog, so the ids, titles and times are copied here; a unit
/// test in the app's test target fails if they drift from `RecipeCatalog`.
enum PollDishMenu {
    struct Entry: Equatable, Identifiable {
        var dish: ChatPoll.Dish
        /// Shown beside the dish in the extension, where there are no photos.
        var emoji: String
        var id: String { dish.id }
    }

    static let all: [Entry] = [
        entry("bulgogi", "Weeknight bulgogi bowls", 35, "🍚"),
        entry("pasta", "Creamy tomato rigatoni", 25, "🍝"),
        entry("pizza", "Friday-night margherita", 30, "🍕"),
        entry("tacos", "Smoky chicken tacos", 25, "🌮"),
        entry("salmon", "Lemon-butter salmon", 30, "🐟"),
        entry("soup", "Cozy tortilla soup", 30, "🍲"),
        entry("salad", "Crispy chickpea bowls", 30, "🥗"),
        entry("curry", "Coconut chickpea curry", 30, "🍛")
    ]

    static func emoji(for dishID: String) -> String {
        all.first { $0.id == dishID }?.emoji ?? "🍽️"
    }

    private static func entry(_ id: String, _ title: String, _ minutes: Int, _ emoji: String) -> Entry {
        Entry(dish: ChatPoll.Dish(id: id, title: title, minutes: minutes), emoji: emoji)
    }
}
