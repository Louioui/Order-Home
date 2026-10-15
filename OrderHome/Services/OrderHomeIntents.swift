import AppIntents
import Foundation

// MARK: - Intent 1: Pitch a Craving via Siri / Apple Intelligence

struct PitchCravingIntent: AppIntent {
    static var title: LocalizedStringResource = "Pitch Dinner Craving"
    static var description = IntentDescription("Nominates a dish for tonight's family dinner poll.")

    @Parameter(title: "Dish Name")
    var dishName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Pitch \(\.$dishName) for dinner")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = OrderHomeStore.shared
        let cleanName = dishName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            return .result(dialog: "Please provide a dish name to pitch for dinner.")
        }

        // If the dinner session is not in pitching stage, inform the user
        guard store.session.stage == .pitching else {
            return .result(dialog: "Tonight's dinner is already past the pitching stage. Start a new dinner in Order Home to nominate dishes.")
        }

        if let existing = store.recipes.first(where: { $0.title.localizedCaseInsensitiveContains(cleanName) }) {
            if store.session.recipeIDs.contains(existing.id) {
                return .result(dialog: "\(existing.title) is already on tonight's menu.")
            }
            if store.session.recipeIDs.count >= 5 {
                return .result(dialog: "Tonight's menu already has five choices. Remove one in Order Home first.")
            }
            store.nominate(existing)
            return .result(dialog: "Added \(existing.title) to tonight's dinner poll!")
        }

        let encoded = cleanName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanName
        guard let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)") else {
            return .result(dialog: "Could not create a link for \(cleanName).")
        }

        if store.session.recipeIDs.count >= 5 {
            return .result(dialog: "Tonight's menu already has five choices. Remove one in Order Home first.")
        }

        let saved = store.addRecipe(title: cleanName, url: url, minutes: 30)
        if saved, let added = store.recipes.first(where: { $0.title.caseInsensitiveCompare(cleanName) == .orderedSame }) {
            store.nominate(added)
            return .result(dialog: "Successfully pitched \(cleanName) for tonight's dinner poll!")
        }

        return .result(dialog: "Could not add \(cleanName) to tonight's menu.")
    }
}

// MARK: - Intent 2: Check Tonight's Dinner Status

struct CheckDinnerStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Tonight's Dinner"
    static var description = IntentDescription("Find out what won tonight's family vote or check poll status.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = OrderHomeStore.shared
        let stage = store.session.stage

        let message: String
        switch stage {
        case .pitching:
            if store.pitches.isEmpty {
                message = "The kitchen is open, but no dishes have been pitched yet. What are you craving tonight?"
            } else {
                let titles = store.pitches.map(\.title).joined(separator: ", ")
                message = "Pitches are open! Current choices: \(titles)."
            }
        case .voting:
            if let leader = store.leader {
                message = "Voting is live! \(leader.title) is currently leading with \(store.matchPercent(for: leader.id))% table match."
            } else {
                message = "Voting is live right now! Cast your votes to lock in tonight's winner."
            }
        case .ticketLocked:
            if let winner = store.winner {
                message = "Tonight's winner is \(winner.title)! The Kitchen Ticket is locked and ready."
            } else {
                message = "The votes are tallied and the Kitchen Ticket is locked."
            }
        case .cooking:
            if let winner = store.winner {
                let currentStep = store.session.stepIndex + 1
                let totalSteps = max(1, winner.steps.count)
                message = "Dinner is cooking in the Studio: \(winner.title), currently on step \(currentStep) of \(totalSteps)."
            } else {
                message = "Dinner is currently cooking in the Studio. Step-by-step mode is active."
            }
        case .served:
            if let winner = store.winner {
                message = "Dinner has been served! \(winner.title) is ready on the table."
            } else {
                message = "Dinner has been served! The dinner bell has already rung."
            }
        }

        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Intent 3: Toggle Dinner Attendance

struct ToggleDinnerAttendanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Dinner Attendance"
    static var description = IntentDescription("Switch whether you are eating at home tonight.")

    @Parameter(title: "Eating at Home")
    var eatingHome: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set my dinner attendance to eating at home: \(\.$eatingHome)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = OrderHomeStore.shared
        guard let member = store.household.members.first(where: { $0.id == store.selectedMemberID }) ?? store.household.members.first else {
            return .result(dialog: "No household member found.")
        }

        store.setAttendance(memberID: member.id, attending: eatingHome)
        let statusText = eatingHome ? "eating at home tonight" : "eating out or skipping tonight"
        return .result(dialog: "Updated \(member.name)'s attendance: marked as \(statusText).")
    }
}

// MARK: - App Shortcuts Provider (Exposes Verbs to Siri & Shortcuts App)

struct OrderHomeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckDinnerStatusIntent(),
            phrases: [
                "What's for dinner in \(.applicationName)?",
                "Check dinner status with \(.applicationName)",
                "What won dinner tonight on \(.applicationName)?"
            ],
            shortTitle: "Check Dinner Status",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: PitchCravingIntent(),
            phrases: [
                "Pitch a craving to \(.applicationName)",
                "Add dinner idea to \(.applicationName)"
            ],
            shortTitle: "Pitch Dinner Craving",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: ToggleDinnerAttendanceIntent(),
            phrases: [
                "Update dinner attendance with \(.applicationName)",
                "Set dinner status on \(.applicationName)"
            ],
            shortTitle: "Dinner Attendance",
            systemImageName: "person.crop.circle.badge.checkmark"
        )
    }
}
