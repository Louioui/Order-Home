import Foundation
import Observation

/// The complete local dinner workflow. Each person can take a turn on this
/// device; profiles do not imply an authenticated or remotely synced account.
@MainActor
@Observable
final class OrderHomeStore {
    var household: Household
    var session: DinnerSession
    var recipes: [Recipe] {
        didSet {
            rebuildRecipeIndex()
        }
    }
    var selectedMemberID: String
    var favoriteIDs: Set<String>
    var hasOnboarded: Bool
    var toast: String?
    var persistenceError: String?
    /// Dinners that reached the table, newest first. Belongs to the local
    /// kitchen only: it is stashed while a shared kitchen is shown.
    private(set) var history: [DinnerRecord] = []

    static let historyLimit = 60
    private static let catalogIDs: Set<String> = Set(RecipeCatalog.all.map(\.id))
    private static let sharedEncoder = JSONEncoder()
    private static let sharedDecoder = JSONDecoder()

    @ObservationIgnored
    private var recipeIndex: [String: Recipe] = [:]

    private(set) var isSharedPresentation = false
    private var sharedSubmittedMemberIDs: Set<String> = []
    private var localStateBeforeShared: Snapshot?

    private var storedVotes: [Vote]
    private var storedOrders: [String: String]
    private let persistenceURL: URL

    private func rebuildRecipeIndex() {
        if recipes.count == RecipeCatalog.all.count {
            recipeIndex = RecipeCatalog.indexByID
        } else {
            recipeIndex = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    func recipe(for id: String) -> Recipe? {
        recipeIndex[id]
    }

    var currentMember: Member {
        household.members.first(where: { $0.id == selectedMemberID })
            ?? household.members.first
            ?? Self.owner()
    }
    var activeMembers: [Member] { household.members.filter(\.attending) }
    var dinerCount: Int { activeMembers.count }
    var pitches: [Recipe] {
        session.recipeIDs.compactMap { recipeIndex[$0] }
    }
    var winner: Recipe? { session.winnerID.flatMap { recipeIndex[$0] } }
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
        self.recipeIndex = RecipeCatalog.indexByID
        self.selectedMemberID = owner.id
        self.favoriteIDs = []
        self.hasOnboarded = false
        self.storedVotes = []
        self.storedOrders = [:]
        self.persistenceURL = persistenceURL ?? Self.defaultPersistenceURL
        self.toast = nil
        self.persistenceError = nil
        restore()
        checkPendingChatPollHandoff()
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
        var total = 0
        for vote in storedVotes where vote.recipeID == recipeID {
            if household.members.contains(where: { $0.id == vote.memberID && $0.attending }) {
                total += vote.reaction.rawValue
            }
        }
        return total
    }

    func matchPercent(for recipeID: String) -> Int {
        guard dinerCount > 0 else { return 0 }
        return Int((Double(score(for: recipeID)) / Double(dinerCount * 2) * 100).rounded())
    }

    func nominate(_ recipe: Recipe) {
        guard !isSharedPresentation else { show("Use your connected kitchen to make this change."); return }
        guard session.stage == .pitching else { show("Start a new dinner to change the menu."); return }
        guard recipeIndex[recipe.id] != nil else { return }
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
        guard recipeIndex[id] != nil else { return }
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

    /// The people who ate the dinner on the table. Once the dinner is recorded
    /// this is fixed to who was there, so someone added or marked as attending
    /// afterwards cannot rate a meal they did not eat. A dinner without a
    /// recorded table (served before history existed) uses who is attending now.
    var dinersAtTable: [Member] {
        guard let ids = currentDinnerRecord?.dinerIDs else { return activeMembers }
        return household.members.filter { ids.contains($0.id) }
    }

    func servedCount(of recipeID: String) -> Int {
        var count = 0
        for record in history where record.recipeID == recipeID {
            count += 1
        }
        return count
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
        guard session.stage == .served, dinersAtTable.contains(where: { $0.id == memberID }),
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
            dinerNames: activeMembers.map(\.name), dinerIDs: activeMembers.map(\.id), ratings: [:]
        ), at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        return 0
    }

    /// Saves a creator's original link, optionally with custom minutes, ingredients, and steps.
    @discardableResult
    func addRecipe(
        title: String,
        url: URL,
        minutes: Int = 0,
        ingredientLines: String? = nil,
        stepLines: String? = nil
    ) -> Bool {
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
        let parsedIngredients = ingredientLines.map(Self.parseIngredientLines) ?? []
        var parsedSteps = stepLines.map(Self.parseStepLines) ?? []
        if parsedSteps.isEmpty {
            parsedSteps = [RecipeStep(
                id: "\(recipeID)-source", title: "Follow the original recipe",
                instruction: "Open the original recipe link to follow the creator’s ingredients and method. Portions are managed in the source recipe.",
                timerSeconds: nil
            )]
        }
        let recipe = Recipe(
            id: recipeID, title: String(trimmedTitle.prefix(100)),
            subtitle: "Your saved recipe. Follow the steps or check the original video.",
            cuisine: "From your collection", category: "Saved links", minutes: max(0, minutes),
            servings: 4, imageName: "imported", ingredients: parsedIngredients,
            steps: parsedSteps,
            sourceURL: validatedURL
        )
        recipes.append(recipe)
        favoriteIDs.insert(recipeID)
        show("Recipe saved to your collection.")
        save()
        return true
    }

    /// Updates existing recipe details such as cook time, manual ingredients, or steps.
    func updateRecipe(
        id: String,
        title: String? = nil,
        minutes: Int? = nil,
        ingredientLines: String? = nil,
        stepLines: String? = nil
    ) {
        guard let idx = recipes.firstIndex(where: { $0.id == id }) else { return }
        var item = recipes[idx]
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        }
        if let minutes, minutes >= 0 {
            item.minutes = minutes
        }
        if let ingredientLines {
            item.ingredients = Self.parseIngredientLines(ingredientLines)
        }
        if let stepLines {
            let parsed = Self.parseStepLines(stepLines)
            if !parsed.isEmpty {
                item.steps = parsed
            }
        }
        recipes[idx] = item
        rebuildRecipeIndex()
        save()
        show("Recipe details updated.")
    }

    /// Ingests a completed chat poll from iMessage and locks the kitchen ticket immediately.
    func importCompletedChatPoll(_ poll: ChatPoll) {
        guard let leaderDish = poll.leader?.dish ?? poll.results().first?.dish else {
            show("No winning dish was found in this poll.")
            return
        }
        let winningRecipe: Recipe
        if let found = recipe(for: leaderDish.id) {
            winningRecipe = found
        } else {
            let synthesized = Recipe(
                id: leaderDish.id,
                title: leaderDish.title,
                subtitle: "Voted tonight in iMessage poll",
                cuisine: "From chat poll",
                category: "Family Poll Winner",
                minutes: leaderDish.minutes,
                servings: max(1, poll.ballots.count > 0 ? poll.ballots.count : poll.expectedVoters),
                imageName: "imported",
                ingredients: [],
                steps: [
                    RecipeStep(
                        id: "\(leaderDish.id)-step-1",
                        title: "Prepare \(leaderDish.title)",
                        instruction: "Follow your favorite recipe for \(leaderDish.title) chosen tonight by your family in iMessage.",
                        timerSeconds: leaderDish.minutes > 0 ? leaderDish.minutes * 60 : nil
                    )
                ],
                sourceURL: nil
            )
            recipes.append(synthesized)
            winningRecipe = synthesized
        }

        session.recipeIDs = [winningRecipe.id]
        session.winnerID = winningRecipe.id
        session.stage = .ticketLocked
        session.stepIndex = 0
        session.checkedIngredientIDs = []
        session.missingIngredientIDs = []
        session.completedStepIDs = []
        session.timerEnd = nil
        session.timerTitle = nil
        hasOnboarded = true
        show("Locked kitchen ticket for \(winningRecipe.title) 🧾")
        save()
    }

    func checkPendingChatPollHandoff() {
        if let poll = SharedKitchenContainer.consumePendingChatPoll() {
            importCompletedChatPoll(poll)
        }
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
              snapshot.pitches.allSatisfy({ pitch in recipeIndex[pitch.recipeID] != nil }) else {
            throw CloudServiceError.permissionDenied
        }
        // Validate the dinner before changing anything. This function can throw
        // only here: a throw after local state is stashed or overwritten would leave
        // a half-applied shared kitchen with an emptied history, and the caller does
        // not restore it, so the next local save would write that over the personal
        // kitchen.
        let pitchMap = Dictionary(uniqueKeysWithValues: snapshot.pitches.map { ($0.id, $0.recipeID) })
        var remoteDinner: (dinner: CloudDinner, stage: DinnerStage, winningRecipeID: String?)?
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
            remoteDinner = (remote, stage, winningRecipeID)
        }
        if !isSharedPresentation {
            localStateBeforeShared = Snapshot(version: 1, household: household, session: session,
                selectedMemberID: selectedMemberID, favoriteIDs: favoriteIDs, hasOnboarded: hasOnboarded,
                votes: storedVotes, orders: storedOrders,
                customRecipes: recipes.filter { !Self.catalogIDs.contains($0.id) },
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
        storedVotes = snapshot.votes.compactMap { vote in
            guard let recipeID = pitchMap[vote.pitchID], let reaction = Reaction(rawValue: vote.voteWeight) else { return nil }
            return Vote(recipeID: recipeID, memberID: vote.memberID, reaction: reaction)
        }
        storedOrders = Dictionary(uniqueKeysWithValues: snapshot.orders.map { order in
            (order.memberID, (order.modifierTags + (order.dinerNote.isEmpty ? [] : [order.dinerNote])).joined(separator: " · "))
        })
        if let validated = remoteDinner {
            let remote = validated.dinner, stage = validated.stage, winningRecipeID = validated.winningRecipeID
            let recipe = winningRecipeID.flatMap { recipeIndex[$0] }
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
            customRecipes: recipes.filter { !Self.catalogIDs.contains($0.id) },
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
            let data = try Self.sharedEncoder.encode(snapshot)
            try data.write(to: persistenceURL, options: .atomic)
            persistenceError = nil
            syncLiveActivity()
        } catch {
            persistenceError = "Your changes are available now, but could not be saved on this device. \(error.localizedDescription)"
        }
    }

    private var rankedPitches: [Recipe] {
        let activeIDs = Set(activeMembers.map(\.id))
        let currentPitches = pitches
        guard currentPitches.count > 1 else { return currentPitches }

        var scores: [String: Int] = [:]
        var passCounts: [String: Int] = [:]
        for vote in storedVotes where activeIDs.contains(vote.memberID) {
            scores[vote.recipeID, default: 0] += vote.reaction.rawValue
            if vote.reaction == .pass {
                passCounts[vote.recipeID, default: 0] += 1
            }
        }

        let positions = Dictionary(uniqueKeysWithValues: session.recipeIDs.enumerated().map { ($1, $0) })
        return currentPitches.sorted { left, right in
            let leftScore = scores[left.id, default: 0]
            let rightScore = scores[right.id, default: 0]
            if leftScore != rightScore { return leftScore > rightScore }
            let leftPasses = passCounts[left.id, default: 0]
            let rightPasses = passCounts[right.id, default: 0]
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
            let snapshot = try Self.sharedDecoder.decode(Snapshot.self, from: data)
            guard snapshot.version == 1, !snapshot.household.members.isEmpty,
                  Set(snapshot.household.members.map(\.id)).count == snapshot.household.members.count else {
                throw CocoaError(.coderReadCorrupt)
            }
            household = snapshot.household
            session = snapshot.session
            var loadedRecipeIDs = Set(recipes.map(\.id))
            var loadedURLs = Set<URL>()
            var newRecipes: [Recipe] = []
            for recipe in snapshot.customRecipes ?? [] {
                guard recipe.id.hasPrefix("saved-"), !recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let source = recipe.sourceURL.flatMap(Self.validatedRecipeURL),
                      loadedRecipeIDs.insert(recipe.id).inserted,
                      loadedURLs.insert(source).inserted else { continue }
                var imported = recipe
                imported.sourceURL = source
                newRecipes.append(imported)
            }
            if !newRecipes.isEmpty {
                recipes.append(contentsOf: newRecipes)
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
        SharedKitchenContainer.kitchenFileURL
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

    private func syncLiveActivity() {
        #if canImport(ActivityKit)
        if let winner {
            let totalSteps = max(1, winner.steps.count)
            let currentStepIdx = min(session.stepIndex, totalSteps - 1)
            let stepTitle = winner.steps.indices.contains(currentStepIdx) ? winner.steps[currentStepIdx].title : "Preparing dinner"
            KitchenLiveActivityManager.shared.sync(
                dinnerID: session.id,
                recipeTitle: winner.title,
                recipeEmoji: PollDishMenu.emoji(for: winner.id),
                servings: max(1, dinerCount),
                stage: session.stage,
                stepIndex: session.stepIndex,
                totalSteps: totalSteps,
                stepTitle: stepTitle,
                timerEnd: session.timerEnd
            )
        } else {
            KitchenLiveActivityManager.shared.endAll()
        }
        #endif
    }

    // MARK: - Manual Recipe Text Parsing

    static func parseIngredientLines(_ text: String) -> [Ingredient] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.enumerated().map { index, line in
            parseSingleIngredientLine(line, id: "ing-\(index + 1)")
        }
    }

    private static func parseSingleIngredientLine(_ line: String, id: String) -> Ingredient {
        let cleaned = line
            .replacingOccurrences(of: "½", with: " 0.5 ")
            .replacingOccurrences(of: "⅓", with: " 0.333 ")
            .replacingOccurrences(of: "⅔", with: " 0.667 ")
            .replacingOccurrences(of: "¼", with: " 0.25 ")
            .replacingOccurrences(of: "¾", with: " 0.75 ")
            .replacingOccurrences(of: "⅛", with: " 0.125 ")
            .replacingOccurrences(of: "⅜", with: " 0.375 ")
            .replacingOccurrences(of: "⅝", with: " 0.625 ")
            .replacingOccurrences(of: "⅞", with: " 0.875 ")

        let tokens = cleaned.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else {
            return Ingredient(id: id, name: line, amount: 1, unit: "")
        }

        var amount: Double = 0
        var tokenIdx = 0

        if let val = Double(tokens[0]) {
            amount = val
            tokenIdx = 1
            if tokens.count > 1, tokens[1].contains("/"), let frac = parseFraction(tokens[1]) {
                amount += frac
                tokenIdx = 2
            }
        } else if tokens[0].contains("/"), let frac = parseFraction(tokens[0]) {
            amount = frac
            tokenIdx = 1
        }

        let commonUnits: Set<String> = [
            "cup", "cups", "tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons",
            "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "g", "gram", "grams",
            "kg", "ml", "clove", "cloves", "can", "cans", "pinch", "dash", "slice", "slices",
            "piece", "pieces", "stalk", "stalks", "sprig", "sprigs", "bunch", "bunches", "head", "heads"
        ]

        var unit = ""
        if tokenIdx < tokens.count {
            let candidateUnit = tokens[tokenIdx].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if commonUnits.contains(candidateUnit) {
                unit = candidateUnit
                tokenIdx += 1
            }
        }

        let name = tokens[tokenIdx...].joined(separator: " ")
        return Ingredient(
            id: id,
            name: name.isEmpty ? line : name,
            amount: amount > 0 ? amount : 1.0,
            unit: unit
        )
    }

    private static func parseFraction(_ string: String) -> Double? {
        let parts = string.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return nil }
        return parts[0] / parts[1]
    }

    static func parseStepLines(_ text: String) -> [RecipeStep] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.enumerated().map { index, rawLine in
            var cleaned = rawLine
            if let range = cleaned.range(of: "^(Step\\s*\\d+[:.-]?|\\d+[.)-]|[-*])\\s*", options: .regularExpression) {
                cleaned.removeSubrange(range)
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

            let title: String
            if let periodIdx = cleaned.firstIndex(of: ".") {
                let firstSentence = String(cleaned[..<periodIdx])
                title = firstSentence.count <= 45 ? firstSentence : String(cleaned.prefix(35)) + "…"
            } else {
                title = cleaned.count <= 40 ? cleaned : String(cleaned.prefix(35)) + "…"
            }

            var timerSeconds: Int? = nil
            if let match = cleaned.range(of: "(\\d+)\\s*(min|minute|minutes)", options: .caseInsensitive) {
                let snippet = String(cleaned[match])
                let digits = snippet.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let mins = Int(digits), mins > 0, mins <= 360 {
                    timerSeconds = mins * 60
                }
            }

            return RecipeStep(
                id: "step-\(index + 1)",
                title: title.isEmpty ? "Step \(index + 1)" : title,
                instruction: cleaned,
                timerSeconds: timerSeconds
            )
        }
    }

    // MARK: - Smart Dietary Conflict Warnings

    struct DietaryWarning: Identifiable, Hashable {
        var id: String { "\(memberName)-\(tag)-\(ingredientName)" }
        var memberName: String
        var tag: String
        var ingredientName: String
        var message: String
    }

    func dietaryWarnings(for recipe: Recipe) -> [DietaryWarning] {
        var warnings: [DietaryWarning] = []
        let attendees = activeMembers
        guard !attendees.isEmpty, !recipe.ingredients.isEmpty else { return [] }

        let glutenKeywords = ["pasta", "spaghetti", "rigatoni", "flour", "wheat", "bread", "soy sauce", "noodle", "noodles", "barley"]
        let dairyKeywords = ["cheese", "parmesan", "mozzarella", "ricotta", "cream", "milk", "butter", "yogurt", "ghee"]
        let meatKeywords = ["chicken", "beef", "pork", "bacon", "meat", "steak", "turkey", "lamb", "prosciutto", "sausage", "ham"]
        let fishKeywords = ["salmon", "fish", "tuna", "cod", "anchovy", "halibut", "trout"]
        let shellfishKeywords = ["shrimp", "prawn", "crab", "lobster", "clam", "mussel", "oyster", "scallop"]
        let nutKeywords = ["peanut", "almond", "cashew", "walnut", "pecan", "hazelnut", "pistachio", "nut"]

        for member in attendees {
            let notes = member.dietaryNotes.lowercased()
            guard !notes.isEmpty else { continue }

            let hasGlutenFree = notes.contains("gluten") || notes.contains("celiac")
            let hasDairyFree = notes.contains("dairy") || notes.contains("lactose")
            let isVegetarian = notes.contains("vegetarian")
            let isVegan = notes.contains("vegan")
            let hasNutAllergy = notes.contains("nut") || notes.contains("peanut")
            let hasShellfishAllergy = notes.contains("shellfish")

            for ingredient in recipe.ingredients {
                let name = ingredient.name.lowercased()

                if hasGlutenFree, let match = glutenKeywords.first(where: { name.contains($0) }) {
                    warnings.append(DietaryWarning(
                        memberName: member.name, tag: "Gluten-Free", ingredientName: ingredient.name,
                        message: "\(member.name) eats gluten-free, but this dish calls for \(match)."
                    ))
                }
                if hasDairyFree, let match = dairyKeywords.first(where: { name.contains($0) }) {
                    warnings.append(DietaryWarning(
                        memberName: member.name, tag: "Dairy-Free", ingredientName: ingredient.name,
                        message: "\(member.name) eats dairy-free, but this dish calls for \(match)."
                    ))
                }
                if (isVegetarian || isVegan), let match = meatKeywords.first(where: { name.contains($0) }) {
                    warnings.append(DietaryWarning(
                        memberName: member.name, tag: isVegan ? "Vegan" : "Vegetarian", ingredientName: ingredient.name,
                        message: "\(member.name) is \(isVegan ? "vegan" : "vegetarian"), but this calls for \(match)."
                    ))
                }
                if (isVegetarian || isVegan), let match = fishKeywords.first(where: { name.contains($0) }) {
                    warnings.append(DietaryWarning(
                        memberName: member.name, tag: isVegan ? "Vegan" : "Vegetarian", ingredientName: ingredient.name,
                        message: "\(member.name) is \(isVegan ? "vegan" : "vegetarian"), but this calls for \(match)."
                    ))
                }
                if isVegan, let match = dairyKeywords.first(where: { name.contains($0) }) {
                    warnings.append(DietaryWarning(
                        memberName: member.name, tag: "Vegan", ingredientName: ingredient.name,
                        message: "\(member.name) is vegan, but this dish calls for \(match)."
                    ))
                }
                if hasNutAllergy, let match = nutKeywords.first(where: { name.contains($0) }) {
                    warnings.append(DietaryWarning(
                        memberName: member.name, tag: "Nut Allergy", ingredientName: ingredient.name,
                        message: "⚠️ \(member.name) has a nut allergy, and this calls for \(match)."
                    ))
                }
                if hasShellfishAllergy, let match = shellfishKeywords.first(where: { name.contains($0) }) {
                    warnings.append(DietaryWarning(
                        memberName: member.name, tag: "Shellfish Allergy", ingredientName: ingredient.name,
                        message: "⚠️ \(member.name) has a shellfish allergy, and this calls for \(match)."
                    ))
                }
            }
        }
        return warnings
    }

    // MARK: - Family Food Stats ("Dinner Wrapped")

    struct DinerFrequency: Equatable, Identifiable {
        var id: String { name }
        var name: String
        var emoji: String
        var count: Int
    }

    struct FamilyFoodStats: Equatable {
        var dinnersCookedCount: Int
        var favoriteRecipeCount: Int
        var averageCookMinutes: Int
        var averageRating: Double
        var totalRatingsCount: Int
        var topCookedRecipe: Recipe?
        var topCookedCount: Int
        var dinerFrequencies: [DinerFrequency]
    }

    var foodStats: FamilyFoodStats {
        let total = history.count
        guard total > 0 else {
            return FamilyFoodStats(
                dinnersCookedCount: 0,
                favoriteRecipeCount: favoriteIDs.count,
                averageCookMinutes: 0,
                averageRating: 0.0,
                totalRatingsCount: 0,
                topCookedRecipe: nil,
                topCookedCount: 0,
                dinerFrequencies: []
            )
        }
        var dishCounts: [String: Int] = [:]
        var totalMinutes = 0
        var minutesCount = 0
        var dinerCounts: [String: Int] = [:]
        var totalRatingScore = 0.0
        var ratingsCount = 0

        for record in history {
            dishCounts[record.recipeID, default: 0] += 1
            if let r = recipe(for: record.recipeID), r.minutes > 0 {
                totalMinutes += r.minutes
                minutesCount += 1
            }
            for name in record.dinerNames {
                dinerCounts[name, default: 0] += 1
            }
            for r in record.allRatings {
                ratingsCount += 1
                switch r {
                case .loved: totalRatingScore += 5.0
                case .good: totalRatingScore += 4.0
                case .tweak: totalRatingScore += 3.0
                }
            }
        }

        let topDishEntry = dishCounts.max(by: { $0.value < $1.value })
        let topDishRecipe = topDishEntry.flatMap { recipe(for: $0.key) }
        let topDishCount = topDishEntry?.value ?? 0
        let avgMinutes = minutesCount > 0 ? (totalMinutes / minutesCount) : 0
        let avgRating = ratingsCount > 0 ? (totalRatingScore / Double(ratingsCount)) : 0.0

        let memberEmojis = Dictionary(household.members.map { ($0.name, $0.emoji) }, uniquingKeysWith: { first, _ in first })
        let frequencies = dinerCounts.map { (name, count) in
            DinerFrequency(name: name, emoji: memberEmojis[name] ?? "🥑", count: count)
        }.sorted { $0.count > $1.count }

        return FamilyFoodStats(
            dinnersCookedCount: total,
            favoriteRecipeCount: favoriteIDs.count,
            averageCookMinutes: avgMinutes,
            averageRating: avgRating,
            totalRatingsCount: ratingsCount,
            topCookedRecipe: topDishRecipe,
            topCookedCount: topDishCount,
            dinerFrequencies: frequencies
        )
    }
}
