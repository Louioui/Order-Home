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

    /// Combines the starter catalog with any custom or imported recipes saved
    /// in the shared House Menu so family members can pitch them in iMessage.
    static var allHouseholdDishes: [Entry] {
        var combined = all
        let custom = loadCustomRecipesFromSharedStore()
        for entry in custom {
            if !combined.contains(where: { $0.id == entry.id }) {
                combined.append(entry)
            }
        }
        return combined
    }

    static func emoji(for dishID: String) -> String {
        allHouseholdDishes.first { $0.id == dishID }?.emoji
            ?? all.first { $0.id == dishID }?.emoji
            ?? "🍽️"
    }

    private static func entry(_ id: String, _ title: String, _ minutes: Int, _ emoji: String) -> Entry {
        Entry(dish: ChatPoll.Dish(id: id, title: title, minutes: minutes), emoji: emoji)
    }

    private struct SharedSnapshotMini: Decodable {
        struct RecipeMini: Decodable {
            var id: String
            var title: String
            var minutes: Int
        }
        var customRecipes: [RecipeMini]?
    }

    private static func loadCustomRecipesFromSharedStore() -> [Entry] {
        let file = SharedKitchenContainer.kitchenFileURL
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(SharedSnapshotMini.self, from: data),
              let list = snapshot.customRecipes else { return [] }
        return list.map { recipe in
            Entry(
                dish: ChatPoll.Dish(
                    id: recipe.id,
                    title: recipe.title,
                    minutes: recipe.minutes > 0 ? recipe.minutes : 30
                ),
                emoji: "✨"
            )
        }
    }
}
