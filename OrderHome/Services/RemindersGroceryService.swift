import EventKit
import Foundation

// MARK: - Reminders Grocery Sync Service (EventKit)

@MainActor
final class RemindersGroceryService {
    static let shared = RemindersGroceryService()

    private let eventStore = EKEventStore()
    static let listTitle = "Order Home: Tonight's Dinner"

    enum SupermarketAisle: String, CaseIterable {
        case produce = "Produce & Fresh Herbs"
        case meatSeafood = "Meat & Seafood"
        case dairyRefrigerated = "Dairy & Refrigerated"
        case bakery = "Bakery & Breads"
        case pantry = "Pantry, Grains & Spices"
        case other = "Other Essentials"

        static func classify(ingredientName: String) -> SupermarketAisle {
            let lower = ingredientName.lowercased()

            let produceKeywords = [
                "onion", "garlic", "shallot", "scallion", "chive", "tomato", "lemon", "lime",
                "cilantro", "parsley", "basil", "ginger", "lettuce", "spinach", "kale", "avocado",
                "pepper", "carrot", "celery", "potato", "mushroom", "herb", "cabbage", "cucumber",
                "apple", "jalapeno", "arugula", "mint", "rosemary", "thyme"
            ]
            if produceKeywords.contains(where: { lower.contains($0) }) {
                return .produce
            }

            let meatKeywords = [
                "chicken", "beef", "steak", "pork", "fish", "salmon", "shrimp", "bacon",
                "sausage", "turkey", "lamb", "tuna", "ground beef", "prawn", "ribeye", "thigh"
            ]
            if meatKeywords.contains(where: { lower.contains($0) }) {
                return .meatSeafood
            }

            let dairyKeywords = [
                "butter", "milk", "cream", "cheese", "parmesan", "cheddar", "mozzarella",
                "egg", "eggs", "yogurt", "sour cream", "ricotta", "feta"
            ]
            if dairyKeywords.contains(where: { lower.contains($0) }) {
                return .dairyRefrigerated
            }

            let bakeryKeywords = [
                "bread", "bun", "buns", "tortilla", "tortillas", "pita", "bagel", "roll", "rolls", "brioche"
            ]
            if bakeryKeywords.contains(where: { lower.contains($0) }) {
                return .bakery
            }

            let pantryKeywords = [
                "rice", "pasta", "flour", "sugar", "soy sauce", "vinegar",
                "broth", "stock", "noodles", "salt", "pepper", "cumin", "paprika", "spice",
                "sauce", "honey", "mustard", "bean", "beans", "sesame", "mayo", "yeast"
            ]
            if pantryKeywords.contains(where: { lower.contains($0) }) || lower.split(separator: " ").contains("oil") || lower.contains("olive oil") {
                return .pantry
            }

            return .other
        }
    }

    enum SyncResult: Equatable {
        case success(count: Int)
        case accessDenied
        case failure(String)
    }

    /// Requests reminder permission from the user.
    func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Locates or creates the dedicated Reminders list for Order Home.
    private func getOrCreateDinnerList() throws -> EKCalendar {
        let calendars = eventStore.calendars(for: .reminder)
        if let existing = calendars.first(where: { $0.title == Self.listTitle }) {
            return existing
        }

        let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
        newCalendar.title = Self.listTitle

        // Assign to default source (iCloud or local)
        if let defaultCal = eventStore.defaultCalendarForNewReminders() {
            newCalendar.source = defaultCal.source
        } else if let firstSource = eventStore.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) {
            newCalendar.source = firstSource
        } else if let anySource = eventStore.sources.first {
            newCalendar.source = anySource
        }

        try eventStore.saveCalendar(newCalendar, commit: true)
        return newCalendar
    }

    /// Syncs missing ingredients into Apple Reminders. Returns count of exported items.
    @discardableResult
    func exportMissingIngredients(
        ingredients: [Ingredient],
        recipeTitle: String,
        servings: Int,
        baseServings: Int,
        unitSystem: UnitSystem = .standard
    ) async -> Int {
        guard !ingredients.isEmpty else {
            return 0
        }

        let granted = await requestAccess()
        guard granted else {
            return 0
        }

        do {
            let calendar = try getOrCreateDinnerList()

            for ingredient in ingredients {
                let reminder = EKReminder(eventStore: eventStore)
                let quantityText = ingredient.quantity(for: servings, baseServings: baseServings, unitSystem: unitSystem)
                let itemTitle = "\(quantityText) \(ingredient.name)".trimmingCharacters(in: .whitespacesAndNewlines)
                reminder.title = itemTitle
                let aisle = SupermarketAisle.classify(ingredientName: ingredient.name)
                reminder.notes = "Tonight's dinner: \(recipeTitle)\nAisle: \(aisle.rawValue)"
                reminder.calendar = calendar
                try eventStore.save(reminder, commit: false)
            }

            try eventStore.commit()
            return ingredients.count
        } catch {
            return 0
        }
    }
}
