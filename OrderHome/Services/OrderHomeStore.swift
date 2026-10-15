import Foundation
import Observation

/// The complete local dinner workflow. Each person can take a turn on this
/// device; profiles do not imply an authenticated or remotely synced account.
@MainActor
@Observable
final class OrderHomeStore {
    var household: Household
    var session: DinnerSession
    var recipes: [Recipe]
    var selectedMemberID: String
    var favoriteIDs: Set<String>
    var hasOnboarded: Bool
    var toast: String?
    var persistenceError: String?
    /// Dinners that reached the table, newest first. Belongs to the local
    /// kitchen only: it is stashed while a shared kitchen is shown.
    private(set) var history: [DinnerRecord] = []

    static let historyLimit = 60

    private(set) var isSharedPresentation = false
    private var sharedSubmittedMemberIDs: Set<String> = []
    private var localStateBeforeShared: Snapshot?

    private var storedVotes: [Vote]
    private var storedOrders: [String: String]
    private let persistenceURL: URL

    var currentMember: Member {
        household.members.first(where: { $0.id == selectedMemberID })
            ?? household.members.first
            ?? Self.owner()
    }
    var activeMembers: [Member] { household.members.filter(\.attending) }
    var dinerCount: Int { activeMembers.count }
    var pitches: [Recipe] {
        session.recipeIDs.compactMap { id in recipes.first(where: { $0.id == id }) }
    }
    var winner: Recipe? { recipes.first(where: { $0.id == session.winnerID }) }
    var leader: Recipe? { rankedPitches.first }
    var votes: [Vote] { storedVotes }
    var orders: [String: String] { storedOrders }
    var completedVoterCount: Int {
        guard !pitches.isEmpty else { return 0 }
        if isSharedPresentation { return activeMembers.filter { sharedSubmittedMemberIDs.contains($0.id) }.count }
        return activeMembers.filter { hasReactedToAll(memberID: $0.id) }.count
    }

    init(persistenceURL: URL? = nil, now: Date = Date()) {
        let owner = Self.owner()
        self.household = Household(name: "Our kitchen", mode: .family, members: [owner])
        self.session = .fresh(now: now)
        self.recipes = RecipeCatalog.all
        self.selectedMemberID = owner.id
        self.favoriteIDs = []
        self.hasOnboarded = false
        self.storedVotes = []
        self.storedOrders = [:]
        self.persistenceURL = persistenceURL ?? Self.defaultPersistenceURL
        self.toast = nil
        self.persistenceError = nil
        restore()
    }

    func reaction(for recipeID: String, memberID: String? = nil) -> Reaction? {
        storedVotes.first { $0.recipeID == recipeID && $0.memberID == (memberID ?? selectedMemberID) }?.reaction
    }

    func hasReactedToAll(memberID: String) -> Bool {
        !session.recipeIDs.isEmpty && session.recipeIDs.allSatisfy {
            reaction(for: $0, memberID: memberID) != nil
        }
    }

    /// Called while the app is active and when it returns to the foreground.
    /// There is no implied background service or remote deadline processing.
    func checkDeadline(now: Date = Date()) {
        guard !isSharedPresentation, session.stage == .voting, session.deadline <= now else { return }
        if household.mode == .couple {
            if let match = mutualMatch { confirm(match); save() }
        } else {
            let activeIDs = Set(activeMembers.map(\.id))
            if storedVotes.contains(where: { activeIDs.contains($0.memberID) && session.recipeIDs.contains($0.recipeID) }),
               let recipe = leader {
                confirm(recipe)
                save()
            }
        }
    }

    func score(for recipeID: String) -> Int {
        let attendingIDs = Set(activeMembers.map(\.id))
        return storedVotes.filter { $0.recipeID == recipeID && attendingIDs.contains($0.memberID) }
            .reduce(0) { $0 + $1.reaction.rawValue }
    }

    func matchPercent(for recipeID: String) -> Int {
        guard dinerCount > 0 else { return 0 }
        return Int((Double(score(for: recipeID)) / Double(dinerCount * 2) * 100).rounded())
    }

    func nominate(_ recipe: Recipe) {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard session.stage == .pitching else { show("Start a new dinner to change the menu."); return }
        guard recipes.contains(where: { $0.id == recipe.id }) else { return }
        guard !session.recipeIDs.contains(recipe.id) else { show("Already on tonight's menu."); return }
        guard session.recipeIDs.count < 5 else { show("Five choices is a full menu. Remove one to add another."); return }
        session.recipeIDs.append(recipe.id)
        show("Added to tonight's menu.")
        save()
    }

    func removePitch(_ id: String) {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard session.stage == .pitching else { return }
        session.recipeIDs.removeAll { $0 == id }
        storedVotes.removeAll { $0.recipeID == id }
        save()
    }

    func vote(_ reaction: Reaction, for recipeID: String) {
        guard session.stage == .voting, session.recipeIDs.contains(recipeID) else { return }
        guard activeMembers.contains(where: { $0.id == selectedMemberID }) else {
            show("Join tonight's table before placing an order.")
            return
        }
        storedVotes.removeAll { $0.recipeID == recipeID && $0.memberID == selectedMemberID }
        storedVotes.append(Vote(recipeID: recipeID, memberID: selectedMemberID, reaction: reaction))
        if !isSharedPresentation { evaluateCompletion() }
        save()
    }

    func startVoting() {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard session.stage == .pitching else { return }
        guard pitches.count >= 2 else { show("Add at least two dishes to open the vote."); return }
        guard !activeMembers.isEmpty else { show("Add someone to tonight's table first."); return }
        guard household.mode != .couple || dinerCount == 2 else {
            show("Table for Two needs two people eating at home.")
            return
        }
        session.stage = .voting
        storedVotes = []
        if session.deadline <= Date() { session.deadline = Date().addingTimeInterval(60 * 60) }
        save()
    }

    /// Family chefs may close a partially completed vote. Couple mode can only
    /// confirm a dish both attending partners explicitly love.
    func lockWinner() {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard session.stage == .voting, !activeMembers.isEmpty else { return }
        if household.mode == .couple {
            guard let match = mutualMatch else {
                show("Keep looking for a dish you both love. You can change your reactions.")
                return
            }
            confirm(match)
        } else {
            let activeIDs = Set(activeMembers.map(\.id))
            guard storedVotes.contains(where: { activeIDs.contains($0.memberID) && session.recipeIDs.contains($0.recipeID) }),
                  let recipe = leader else {
                show("Place at least one reaction before confirming dinner.")
                return
            }
            confirm(recipe)
        }
        save()
    }

    func startCooking() {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard session.stage == .ticketLocked, let winner, !winner.steps.isEmpty, dinerCount > 0 else { return }
        session.stage = .cooking
        session.stepIndex = 0
        save()
    }

    func advanceStep() {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard session.stage == .cooking, let winner,
              winner.steps.indices.contains(session.stepIndex) else { return }
        session.completedStepIDs.insert(winner.steps[session.stepIndex].id)
        if session.stepIndex < winner.steps.count - 1 { session.stepIndex += 1 }
        save()
    }

    func ringDinnerBell() {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard session.stage == .cooking, let winner else { return }
        session.completedStepIDs.formUnion(winner.steps.map(\.id))
        session.stepIndex = max(0, winner.steps.count - 1)
        session.stage = .served
        session.timerEnd = nil
        session.timerTitle = nil
        recordServedDinner()
        show("Order up! Dinner is on the table.")
        save()
    }

    func toggleIngredient(_ id: String) {
        guard winner?.ingredients.contains(where: { $0.id == id }) == true else { return }
        if session.checkedIngredientIDs.contains(id) { session.checkedIngredientIDs.remove(id) }
        else { session.checkedIngredientIDs.insert(id); session.missingIngredientIDs.remove(id) }
        save()
    }

    func toggleMissing(_ id: String) {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard winner?.ingredients.contains(where: { $0.id == id }) == true else { return }
        if session.missingIngredientIDs.contains(id) { session.missingIngredientIDs.remove(id) }
        else { session.missingIngredientIDs.insert(id); session.checkedIngredientIDs.remove(id) }
        save()
    }

    func toggleStep(_ id: String) {
        guard session.stage == .cooking, winner?.steps.contains(where: { $0.id == id }) == true else { return }
        if session.completedStepIDs.contains(id) { session.completedStepIDs.remove(id) }
        else { session.completedStepIDs.insert(id) }
        save()
    }

    func startTimer(seconds: Int, title: String) {
        guard session.stage == .cooking, seconds > 0 else { return }
        session.timerEnd = Date().addingTimeInterval(TimeInterval(seconds))
        session.timerTitle = title
        save()
    }

    func cancelTimer() {
        session.timerEnd = nil
        session.timerTitle = nil
        save()
    }

    func toggleFavorite(_ id: String) {
        guard recipes.contains(where: { $0.id == id }) else { return }
        if favoriteIDs.contains(id) { favoriteIDs.remove(id) }
        else { favoriteIDs.insert(id) }
        save()
    }

    // MARK: Dinner history

    /// The record for the dinner on the table, once it has been served.
    var currentDinnerRecord: DinnerRecord? {
        history.first { $0.id == session.id }
    }

    func rating(for memberID: String) -> DinnerRating? {
        currentDinnerRecord?.rating(for: memberID)
    }

    func servedCount(of recipeID: String) -> Int {
        history.filter { $0.recipeID == recipeID }.count
    }

    func lastServed(_ recipeID: String) -> Date? {
        history.first { $0.recipeID == recipeID }?.servedAt
    }

    /// Records how one person who ate felt about tonight's dinner. Tapping the
    /// rating someone already gave takes it back. When the ratings become strong
    /// enough (see `HouseFavoritePolicy`) the dish joins the House Menu; a
    /// rating never removes a favorite.
    func rateDinner(_ rating: DinnerRating, memberID: String) {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard session.stage == .served, activeMembers.contains(where: { $0.id == memberID }),
              let winner, let index = recordServedDinner() else { return }
        let wasKeeper = isKeeper(history[index])
        if history[index].ratings[memberID] == rating.rawValue {
            history[index].ratings.removeValue(forKey: memberID)
        } else {
            history[index].ratings[memberID] = rating.rawValue
        }
        if !wasKeeper, isKeeper(history[index]), !favoriteIDs.contains(winner.id) {
            favoriteIDs.insert(winner.id)
            show("\(winner.title) joined your House Menu.")
        }
        save()
    }

    private func isKeeper(_ record: DinnerRecord) -> Bool {
        HouseFavoritePolicy.shouldSave(ratings: record.allRatings, dinerCount: record.dinerNames.count)
    }

    /// Makes sure the served dinner has exactly one record and returns its index.
    /// Ringing the bell and rating both call this, so neither can duplicate it,
    /// and a dinner served before history existed is recorded when first rated.
    @discardableResult
    private func recordServedDinner() -> Int? {
        guard !isSharedPresentation, session.stage == .served, let winner else { return nil }
        if let existing = history.firstIndex(where: { $0.id == session.id }) { return existing }
        history.insert(DinnerRecord(
            id: session.id, recipeID: winner.id, recipeTitle: winner.title, servedAt: Date(),
            dinerNames: activeMembers.map(\.name), ratings: [:]
        ), at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        return 0
    }

    /// Saves a creator's original link without implying that its ingredients,
    /// timing, thumbnail or instructions have been extracted or verified.
    @discardableResult
    func addRecipe(title: String, url: URL) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            show("Give your saved recipe a name first.")
            return false
        }
        guard let validatedURL = Self.validatedRecipeURL(url) else {
            show("Use a secure YouTube, TikTok or Instagram recipe link.")
            return false
        }
        if let existing = recipes.first(where: { $0.sourceURL.flatMap(Self.validatedRecipeURL) == validatedURL }) {
            favoriteIDs.insert(existing.id)
            show("This recipe link is already in your collection.")
            save()
            return true
        }
        let recipeID = "saved-\(UUID().uuidString)"
        let recipe = Recipe(
            id: recipeID, title: String(trimmedTitle.prefix(100)),
            subtitle: "Your saved recipe. Ingredients and method live in the original link.",
            cuisine: "From your collection", category: "Saved links", minutes: 0,
            servings: 4, imageName: "imported", ingredients: [],
            steps: [RecipeStep(
                id: "\(recipeID)-source", title: "Follow the original recipe",
                instruction: "Open the original recipe link to follow the creator’s ingredients and method. Portions are managed in the source recipe.",
                timerSeconds: nil
            )],
            sourceURL: validatedURL
        )
        recipes.append(recipe)
        favoriteIDs.insert(recipeID)
        show("Recipe link saved to your collection.")
        save()
        return true
    }

    func newDinner() {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        session = .fresh()
        storedVotes = []
        storedOrders = [:]
        save()
    }

    func completeOnboarding(name: String, personName: String, mode: HouseholdMode) {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        household.name = nonEmpty(name, fallback: "Our kitchen")
        household.mode = mode
        if household.members.isEmpty { household.members = [Self.owner()] }
        household.members[0].name = nonEmpty(personName, fallback: "You")
        selectedMemberID = household.members[0].id
        hasOnboarded = true
        save()
    }

    func addMember(name: String, emoji: String, role: String) {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { show("Give your table member a name."); return }
        let member = Member(
            id: UUID().uuidString, name: String(trimmedName.prefix(40)),
            emoji: nonEmpty(emoji, fallback: "🍽️"), role: nonEmpty(role, fallback: "Diner"),
            dietaryNotes: "", attending: household.mode == .family || dinerCount < 2
        )
        household.members.append(member)
        save()
    }

    func setAttendance(memberID: String, attending: Bool) {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard let index = household.members.firstIndex(where: { $0.id == memberID }) else { return }
        guard household.members[index].attending != attending else { return }
        if attending && household.mode == .couple && dinerCount >= 2 {
            show("Table for Two has two seats. Free one or switch to Family Table.")
            return
        }
        household.members[index].attending = attending
        if session.stage == .voting { evaluateCompletion() }
        save()
    }

    func setOrderNote(_ note: String, memberID: String) {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard household.members.contains(where: { $0.id == memberID }) else { return }
        let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        if trimmed.isEmpty { storedOrders.removeValue(forKey: memberID) }
        else { storedOrders[memberID] = trimmed }
        save()
    }

    func setMode(_ mode: HouseholdMode) {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard session.stage == .pitching || session.stage == .served else {
            show("Start a new dinner before changing your table style.")
            return
        }
        household.mode = mode
        save()
    }

    /// The only entry point that creates demonstration household data.
    func loadSampleHousehold() {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        household = Household(name: "The Sunday Club", mode: .family, members: [
            Member(id: "sample-alex", name: "Alex", emoji: "👨🏽‍🍳", role: "Head Chef", dietaryNotes: "", attending: true),
            Member(id: "sample-jamie", name: "Jamie", emoji: "👩🏻", role: "Sous Chef", dietaryNotes: "", attending: true),
            Member(id: "sample-mia", name: "Mia", emoji: "👧🏽", role: "Taste Tester", dietaryNotes: "Mild spice, please", attending: true),
            Member(id: "sample-leo", name: "Leo", emoji: "👦🏽", role: "Diner", dietaryNotes: "", attending: true)
        ])
        selectedMemberID = "sample-alex"
        session = .fresh()
        session.stage = .voting
        session.recipeIDs = ["bulgogi", "pasta", "pizza"]
        storedVotes = [
            Vote(recipeID: "bulgogi", memberID: "sample-jamie", reaction: .love),
            Vote(recipeID: "pasta", memberID: "sample-jamie", reaction: .down),
            Vote(recipeID: "pizza", memberID: "sample-jamie", reaction: .pass),
            Vote(recipeID: "bulgogi", memberID: "sample-mia", reaction: .love),
            Vote(recipeID: "pasta", memberID: "sample-mia", reaction: .down),
            Vote(recipeID: "pizza", memberID: "sample-mia", reaction: .love),
            Vote(recipeID: "bulgogi", memberID: "sample-leo", reaction: .love),
            Vote(recipeID: "pasta", memberID: "sample-leo", reaction: .pass),
            Vote(recipeID: "pizza", memberID: "sample-leo", reaction: .love)
        ]
        storedOrders = ["sample-mia": "Mild spice, please", "sample-leo": "Extra rice if we have bulgogi"]
        favoriteIDs = ["bulgogi", "pasta"]
        history = []
        hasOnboarded = true
        show("Sample table loaded. Take turns voting as Alex, Jamie, Mia and Leo.")
        save()
    }

    /// Returns the explicit demonstration table to setup without discarding
    /// creator links someone may have saved while exploring the app.
    func leaveSampleKitchen() {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard household.members.first?.id.hasPrefix("sample-") == true else { return }
        let owner = Self.owner()
        household = Household(name: "Our kitchen", mode: .family, members: [owner])
        session = .fresh()
        selectedMemberID = owner.id
        favoriteIDs = []
        history = []
        storedVotes = []
        storedOrders = [:]
        toast = nil
        hasOnboarded = false
        save()
    }

    /// Presents a server-authoritative snapshot while retaining the local kitchen
    /// in memory. The signed-in user, never a profile picker, selects the diner.
    func applySharedSnapshot(_ snapshot: CloudKitchenSnapshot, userID: String, drafts: [String: Reaction] = [:]) throws {
        guard let ownMember = snapshot.members.first(where: { $0.userID == userID }),
              !snapshot.members.isEmpty,
              Set(snapshot.members.map(\.id)).count == snapshot.members.count,
              Set(snapshot.pitches.map(\.recipeID)).count == snapshot.pitches.count,
              snapshot.pitches.allSatisfy({ pitch in recipes.contains(where: { $0.id == pitch.recipeID }) }) else {
            throw CloudServiceError.permissionDenied
        }
        if !isSharedPresentation {
            localStateBeforeShared = Snapshot(version: 1, household: household, session: session,
                selectedMemberID: selectedMemberID, favoriteIDs: favoriteIDs, hasOnboarded: hasOnboarded,
                votes: storedVotes, orders: storedOrders,
                customRecipes: recipes.filter { recipe in !RecipeCatalog.all.contains(where: { $0.id == recipe.id }) },
                history: LossyList(history))
            // The local kitchen's dinners must not appear under a shared kitchen.
            history = []
        }
        let previousSession = session
        let incomingOrders = Dictionary(uniqueKeysWithValues: snapshot.orders.map { ($0.memberID, $0) })
        household = Household(name: snapshot.household.name, mode: snapshot.household.mode,
            members: snapshot.members.map { member in
                Member(id: member.id, name: member.displayName, emoji: member.avatarEmoji,
                    role: member.defaultRole == "head_chef" ? "Head Chef" : member.defaultRole == "sous_chef" ? "Sous Chef" : "Diner",
                    dietaryNotes: member.dietaryTags.joined(separator: ", "),
                    attending: incomingOrders[member.id]?.isEatingHome ?? true)
            })
        selectedMemberID = ownMember.id
        sharedSubmittedMemberIDs = Set(snapshot.orders.filter { $0.submittedAt != nil }.map(\.memberID))
        let pitchMap = Dictionary(uniqueKeysWithValues: snapshot.pitches.map { ($0.id, $0.recipeID) })
        storedVotes = snapshot.votes.compactMap { vote in
            guard let recipeID = pitchMap[vote.pitchID], let reaction = Reaction(rawValue: vote.voteWeight) else { return nil }
            return Vote(recipeID: recipeID, memberID: vote.memberID, reaction: reaction)
        }
        storedOrders = Dictionary(uniqueKeysWithValues: snapshot.orders.map { order in
            (order.memberID, (order.modifierTags + (order.dinerNote.isEmpty ? [] : [order.dinerNote])).joined(separator: " · "))
        })
        if let remote = snapshot.session {
            let stage: DinnerStage
            switch remote.status {
            case "pitching": stage = .pitching
            case "voting": stage = .voting
            case "ticket_locked": stage = .ticketLocked
            case "cooking": stage = .cooking
            case "served": stage = .served
            default: throw CloudServiceError.dinnerChanged
            }
            let winningRecipeID = remote.winningPitchID.flatMap { pitchMap[$0] }
            if [.ticketLocked, .cooking, .served].contains(stage), winningRecipeID == nil {
                throw CloudServiceError.dinnerChanged
            }
            let recipe = recipes.first { $0.id == winningRecipeID }
            let sameDinner = previousSession.id == remote.id
            let stepIndex = min(max(0, remote.cookingStepIndex), max(0, (recipe?.steps.count ?? 1) - 1))
            let completed = Set((recipe?.steps ?? []).prefix(stage == .served ? (recipe?.steps.count ?? 0) : stepIndex).map(\.id))
            session = DinnerSession(id: remote.id, stage: stage, recipeIDs: snapshot.pitches.map(\.recipeID),
                winnerID: winningRecipeID, deadline: remote.votingDeadline, stepIndex: stepIndex,
                checkedIngredientIDs: sameDinner ? previousSession.checkedIngredientIDs : [],
                missingIngredientIDs: Set(remote.missingGroceries),
                completedStepIDs: completed.union(sameDinner ? previousSession.completedStepIDs : []),
                timerEnd: sameDinner && stage == .cooking ? previousSession.timerEnd : nil,
                timerTitle: sameDinner && stage == .cooking ? previousSession.timerTitle : nil)
        } else {
            session = .fresh()
            session.id = "pending-" + snapshot.household.id
        }
        isSharedPresentation = true
        hasOnboarded = true
        if session.stage == .voting {
            for (recipeID, reaction) in drafts where session.recipeIDs.contains(recipeID) {
                storedVotes.removeAll { $0.memberID == ownMember.id && $0.recipeID == recipeID }
                storedVotes.append(Vote(recipeID: recipeID, memberID: ownMember.id, reaction: reaction))
            }
        }
    }

    func restoreLocalKitchen() {
        guard let local = localStateBeforeShared else { return }
        household = local.household
        session = local.session
        selectedMemberID = local.selectedMemberID
        favoriteIDs = local.favoriteIDs
        hasOnboarded = local.hasOnboarded
        storedVotes = local.votes
        storedOrders = local.orders
        history = local.history?.elements ?? []
        recipes = RecipeCatalog.all + (local.customRecipes ?? [])
        sharedSubmittedMemberIDs = []
        localStateBeforeShared = nil
        isSharedPresentation = false
        toast = nil
    }

    func save() {
        var snapshot = Snapshot(
            version: 1, household: household, session: session,
            selectedMemberID: selectedMemberID, favoriteIDs: favoriteIDs,
            hasOnboarded: hasOnboarded, votes: storedVotes, orders: storedOrders,
            customRecipes: recipes.filter { recipe in !RecipeCatalog.all.contains(where: { $0.id == recipe.id }) },
            history: LossyList(history)
        )
        // Shared household data stays out of the unscoped local save. Only the
        // device's personal recipe links/favorites update its saved local kitchen.
        if isSharedPresentation {
            guard var local = localStateBeforeShared else { return }
            local.favoriteIDs = favoriteIDs
            local.customRecipes = snapshot.customRecipes
            localStateBeforeShared = local
            snapshot = local
        }
        do {
            let directory = persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: persistenceURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "Your changes are available now, but could not be saved on this device. \(error.localizedDescription)"
        }
    }

    private var rankedPitches: [Recipe] {
        let activeIDs = Set(activeMembers.map(\.id))
        let positions = Dictionary(uniqueKeysWithValues: session.recipeIDs.enumerated().map { ($1, $0) })
        return pitches.sorted { left, right in
            let leftScore = score(for: left.id), rightScore = score(for: right.id)
            if leftScore != rightScore { return leftScore > rightScore }
            let leftPasses = storedVotes.filter { $0.recipeID == left.id && activeIDs.contains($0.memberID) && $0.reaction == .pass }.count
            let rightPasses = storedVotes.filter { $0.recipeID == right.id && activeIDs.contains($0.memberID) && $0.reaction == .pass }.count
            if leftPasses != rightPasses { return leftPasses < rightPasses }
            return (positions[left.id] ?? 0) < (positions[right.id] ?? 0)
        }
    }

    private var mutualMatch: Recipe? {
        guard activeMembers.count == 2 else { return nil }
        return pitches.first { recipe in
            activeMembers.allSatisfy { reaction(for: recipe.id, memberID: $0.id) == .love }
        }
    }

    private func evaluateCompletion() {
        guard session.stage == .voting, !activeMembers.isEmpty, !pitches.isEmpty else { return }
        if household.mode == .couple {
            if let recipe = mutualMatch { confirm(recipe) }
        } else if completedVoterCount == activeMembers.count, let recipe = leader {
            confirm(recipe)
        }
    }

    private func confirm(_ recipe: Recipe) {
        session.winnerID = recipe.id
        session.stage = .ticketLocked
        session.stepIndex = 0
        session.checkedIngredientIDs = []
        session.missingIngredientIDs = []
        session.completedStepIDs = []
        session.timerEnd = nil
        session.timerTitle = nil
        show(household.mode == .couple ? "Dinner match! You both love \(recipe.title)." : "Order confirmed: \(recipe.title).")
    }

    private func restore() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            guard snapshot.version == 1, !snapshot.household.members.isEmpty,
                  Set(snapshot.household.members.map(\.id)).count == snapshot.household.members.count else {
                throw CocoaError(.coderReadCorrupt)
            }
            household = snapshot.household
            session = snapshot.session
            var loadedRecipeIDs = Set(recipes.map(\.id))
            var loadedURLs = Set<URL>()
            for recipe in snapshot.customRecipes ?? [] {
                guard recipe.id.hasPrefix("saved-"), !recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let source = recipe.sourceURL.flatMap(Self.validatedRecipeURL),
                      loadedRecipeIDs.insert(recipe.id).inserted,
                      loadedURLs.insert(source).inserted else { continue }
                var imported = recipe
                imported.sourceURL = source
                recipes.append(imported)
            }
            let knownRecipeIDs = Set(recipes.map(\.id))
            var seenIDs = Set<String>()
            session.recipeIDs = session.recipeIDs.filter { knownRecipeIDs.contains($0) && seenIDs.insert($0).inserted }
            let memberIDs = Set(household.members.map(\.id))
            selectedMemberID = memberIDs.contains(snapshot.selectedMemberID) ? snapshot.selectedMemberID : household.members[0].id
            favoriteIDs = snapshot.favoriteIDs.intersection(knownRecipeIDs)
            hasOnboarded = snapshot.hasOnboarded
            var seenVotes = Set<String>()
            storedVotes = snapshot.votes.filter {
                memberIDs.contains($0.memberID) && session.recipeIDs.contains($0.recipeID) && seenVotes.insert($0.id).inserted
            }
            storedOrders = snapshot.orders.filter { memberIDs.contains($0.key) }
            var seenDinnerIDs = Set<String>()
            history = Array((snapshot.history?.elements ?? []).filter {
                !$0.id.isEmpty && !$0.recipeID.isEmpty && seenDinnerIDs.insert($0.id).inserted
            }.prefix(Self.historyLimit))
            if session.stage == .ticketLocked || session.stage == .cooking || session.stage == .served {
                guard let winner, session.recipeIDs.contains(winner.id), !winner.steps.isEmpty else {
                    session = .fresh()
                    storedVotes = []
                    return
                }
                session.stepIndex = min(max(0, session.stepIndex), winner.steps.count - 1)
                let ingredientIDs = Set(winner.ingredients.map(\.id))
                session.checkedIngredientIDs.formIntersection(ingredientIDs)
                session.missingIngredientIDs.formIntersection(ingredientIDs)
                session.completedStepIDs.formIntersection(Set(winner.steps.map(\.id)))
            }
        } catch {
            persistenceError = "Your saved kitchen could not be opened. A fresh table is ready; the saved file is still on this device."
        }
    }

    private func show(_ message: String) { toast = message }
    private func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(60))
    }
    private static func owner() -> Member {
        Member(id: "owner", name: "You", emoji: "👩‍🍳", role: "Head Chef", dietaryNotes: "", attending: true)
    }
    private static var defaultPersistenceURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("OrderHome", isDirectory: true).appendingPathComponent("kitchen.json")
    }

    private static func validatedRecipeURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              ["youtube.com", "youtu.be", "tiktok.com", "instagram.com"].contains(where: {
                  host == $0 || host.hasSuffix(".\($0)")
              }) else { return nil }
        components.scheme = "https"
        components.host = host
        components.port = nil
        components.fragment = nil
        return components.url
    }

    private struct Snapshot: Codable {
        var version: Int
        var household: Household
        var session: DinnerSession
        var selectedMemberID: String
        var favoriteIDs: Set<String>
        var hasOnboarded: Bool
        var votes: [Vote]
        var orders: [String: String]
        var customRecipes: [Recipe]?
        /// Optional and lossy, so saves from before history existed still open
        /// and a damaged entry can never cost someone their kitchen.
        var history: LossyList<DinnerRecord>?
    }
}
