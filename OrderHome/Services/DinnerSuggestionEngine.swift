import Foundation

// MARK: - Smart Family Recipe Suggestions Engine

struct DinnerSuggestion: Identifiable, Equatable {
    var id: String { recipe.id }
    var recipe: Recipe
    var score: Double
    var headline: String
    var reason: String
    var matchTag: String
}

enum DinnerSuggestionEngine {
    /// Generates intelligent meal suggestions based on the rolling 60-dinner history,
    /// day-of-the-week family traditions, table rating habits, and recency cooldowns.
    static func generateSuggestions(
        recipes: [Recipe],
        history: [DinnerRecord],
        favorites: Set<String>,
        now: Date = Date(),
        limit: Int = 3
    ) -> [DinnerSuggestion] {
        guard !recipes.isEmpty else { return [] }

        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: now)
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale.current
        let weekdaySymbols = weekdayFormatter.weekdaySymbols ?? [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
        ]
        let currentDayName = weekdaySymbols[(currentWeekday - 1) % 7]

        // Track stats per recipe from history
        var weekdayCounts: [String: Int] = [:]
        var totalCookCounts: [String: Int] = [:]
        var lovedCounts: [String: Int] = [:]
        var lastCookedDates: [String: Date] = [:]

        for record in history {
            let rid = record.recipeID
            totalCookCounts[rid, default: 0] += 1

            let recordWeekday = calendar.component(.weekday, from: record.servedAt)
            if recordWeekday == currentWeekday {
                weekdayCounts[rid, default: 0] += 1
            }

            if lastCookedDates[rid] == nil || record.servedAt > lastCookedDates[rid]! {
                lastCookedDates[rid] = record.servedAt
            }

            for rating in record.allRatings {
                if rating == .loved { lovedCounts[rid, default: 0] += 1 }
            }
        }

        var candidates: [DinnerSuggestion] = []

        for recipe in recipes {
            let rid = recipe.id
            var score = 10.0
            var headline = "Family Favorite"
            var reason = "A dependable weeknight classic for your table."
            var matchTag = "\(recipe.minutes) min prep"

            // 1. Day of week affinity
            let onThisDay = weekdayCounts[rid, default: 0]
            if onThisDay >= 2 {
                score += 45.0
                headline = "\(currentDayName) Tradition"
                reason = "Your table usually cooks \(recipe.title) on \(currentDayName)s."
                matchTag = "Table Habit"
            } else if onThisDay == 1 {
                score += 20.0
                headline = "Cooked on \(currentDayName)s"
                reason = "A proven fit for \(currentDayName) dinner."
            }

            // 2. High ratings & house favorites
            let loved = lovedCounts[rid, default: 0]
            if loved > 0 {
                score += Double(loved) * 15.0
                if onThisDay < 2 {
                    headline = "Loved by Your Table"
                    reason = "Scored high marks with everyone at dinner."
                    matchTag = "🔥 Highly Rated"
                }
            }

            if favorites.contains(rid) {
                score += 15.0
            }

            // 3. Recency cooldown: don't suggest what we ate yesterday or 2 days ago!
            if let lastCooked = lastCookedDates[rid] {
                let daysAgo = calendar.dateComponents([.day], from: lastCooked, to: now).day ?? 0
                if daysAgo <= 1 {
                    score -= 100.0 // Just ate this yesterday!
                } else if daysAgo <= 3 {
                    score -= 40.0 // Ate within 3 days
                } else if daysAgo >= 14 && (totalCookCounts[rid, default: 0] >= 2 || favorites.contains(rid)) {
                    score += 25.0 // Hasn't been cooked in two weeks; due for a comeback
                    if onThisDay < 2 && loved == 0 {
                        headline = "Time for a Comeback"
                        reason = "Haven't enjoyed this one in over two weeks."
                        matchTag = "Ready to Cook"
                    }
                }
            } else if favorites.contains(rid) {
                // Favorite never cooked yet
                score += 20.0
                headline = "Ready to Try"
                reason = "Saved on your House Menu, ready for tonight."
                matchTag = "House Menu"
            }

            candidates.append(DinnerSuggestion(
                recipe: recipe,
                score: score,
                headline: headline,
                reason: reason,
                matchTag: matchTag
            ))
        }

        return candidates
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}
