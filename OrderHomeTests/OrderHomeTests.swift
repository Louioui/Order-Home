import XCTest
@testable import OrderHome

final class OrderHomeTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories { try? FileManager.default.removeItem(at: directory) }
        temporaryDirectories = []
    }

    @MainActor
    private func freshStore() -> OrderHomeStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryDirectories.append(directory)
        return OrderHomeStore(persistenceURL: directory.appendingPathComponent("kitchen.json"))
    }

    @MainActor
    private func addTwoPitches(to store: OrderHomeStore) {
        store.nominate(RecipeCatalog.all[0])
        store.nominate(RecipeCatalog.all[1])
    }

    @MainActor
    func testFreshKitchenHasNoFabricatedPeopleOrVotes() async {
        let store = freshStore()
        XCTAssertFalse(store.hasOnboarded)
        XCTAssertEqual(store.household.members.count, 1)
        XCTAssertEqual(store.dinerCount, 1)
        XCTAssertTrue(store.pitches.isEmpty)
        XCTAssertTrue(store.votes.isEmpty)
        XCTAssertNil(store.winner)
    }

    @MainActor
    func testMenuRejectsDuplicatesAndCapsAtFivePitches() async {
        let store = freshStore()
        for recipe in RecipeCatalog.all { store.nominate(recipe) }
        store.nominate(RecipeCatalog.all[0])
        XCTAssertEqual(store.pitches.count, 5)
        XCTAssertEqual(Set(store.session.recipeIDs).count, 5)
        store.removePitch(RecipeCatalog.all[0].id)
        XCTAssertEqual(store.pitches.count, 4)
    }

    @MainActor
    func testFamilyTiePrefersFewerPasses() async {
        let store = freshStore()
        store.addMember(name: "Sam", emoji: "👩", role: "Diner")
        store.addMember(name: "Lee", emoji: "👦", role: "Diner")
        addTwoPitches(to: store)
        store.startVoting()
        let first = store.pitches[0].id, second = store.pitches[1].id
        store.vote(.love, for: first)
        store.vote(.down, for: second)
        store.selectedMemberID = store.household.members[1].id
        store.vote(.pass, for: first)
        store.vote(.down, for: second)
        XCTAssertEqual(store.score(for: first), 2)
        XCTAssertEqual(store.score(for: second), 2)
        XCTAssertEqual(store.leader?.id, second)
        store.lockWinner()
        XCTAssertEqual(store.winner?.id, second)
    }

    @MainActor
    func testExactFamilyTieUsesNominationOrder() async {
        let store = freshStore()
        store.addMember(name: "Sam", emoji: "👩", role: "Diner")
        addTwoPitches(to: store)
        store.startVoting()
        for recipe in store.pitches { store.vote(.down, for: recipe.id) }
        XCTAssertEqual(store.leader?.id, store.pitches[0].id)
        store.lockWinner()
        XCTAssertEqual(store.winner?.id, store.pitches[0].id)
    }

    @MainActor
    func testAttendanceCountsPeopleOnceAndExcludesTheirVotes() async {
        let store = freshStore()
        store.addMember(name: "Sam", emoji: "👩", role: "Diner")
        store.addMember(name: "Lee", emoji: "👦", role: "Diner")
        addTwoPitches(to: store)
        store.startVoting()
        let first = store.pitches[0].id, second = store.pitches[1].id
        store.vote(.love, for: first)
        store.vote(.down, for: second)
        let samID = store.household.members[1].id
        store.selectedMemberID = samID
        store.vote(.pass, for: first)
        store.vote(.love, for: second)
        XCTAssertEqual(store.dinerCount, 3, "Four reactions still represent only two of three diners")
        XCTAssertEqual(store.score(for: second), 3)
        store.setAttendance(memberID: samID, attending: false)
        XCTAssertEqual(store.dinerCount, 2)
        XCTAssertEqual(store.score(for: second), 1)
        XCTAssertEqual(store.leader?.id, first)
        XCTAssertEqual(store.completedVoterCount, 1)
    }

    @MainActor
    func testEmptyTableCannotOpenVotingOrCooking() async {
        let store = freshStore()
        addTwoPitches(to: store)
        store.setAttendance(memberID: store.currentMember.id, attending: false)
        store.startVoting()
        XCTAssertEqual(store.session.stage, .pitching)
        store.startCooking()
        XCTAssertEqual(store.session.stage, .pitching)
        XCTAssertEqual(store.matchPercent(for: store.pitches[0].id), 0)
    }

    @MainActor
    func testAllCompletedOrdersLockOneWinnerAndFreezeVotes() async {
        let store = freshStore()
        store.addMember(name: "Sam", emoji: "👩", role: "Diner")
        addTwoPitches(to: store)
        store.startVoting()
        let first = store.pitches[0].id, second = store.pitches[1].id
        store.vote(.love, for: first)
        store.vote(.down, for: second)
        XCTAssertEqual(store.session.stage, .voting)
        store.selectedMemberID = store.household.members[1].id
        store.vote(.love, for: first)
        store.vote(.pass, for: second)
        XCTAssertEqual(store.session.stage, .ticketLocked)
        XCTAssertEqual(store.winner?.id, first)
        let lockedVotes = store.votes
        store.vote(.love, for: second)
        XCTAssertEqual(store.votes, lockedVotes)
    }

    @MainActor
    func testCoupleRequiresMutualLoveAndCanRecoverFromNoMatch() async {
        let store = freshStore()
        store.setMode(.couple)
        store.addMember(name: "Sam", emoji: "👩", role: "Sous Chef")
        addTwoPitches(to: store)
        store.startVoting()
        let first = store.pitches[0].id, second = store.pitches[1].id
        store.vote(.love, for: first)
        store.vote(.pass, for: second)
        store.selectedMemberID = store.household.members[1].id
        store.vote(.pass, for: first)
        store.vote(.love, for: second)
        store.lockWinner()
        XCTAssertEqual(store.session.stage, .voting)
        XCTAssertNil(store.winner)
        store.vote(.love, for: first)
        XCTAssertEqual(store.session.stage, .ticketLocked)
        XCTAssertEqual(store.winner?.id, first)
    }

    @MainActor
    func testCoupleNeedsTwoAttendingPeople() async {
        let store = freshStore()
        store.setMode(.couple)
        addTwoPitches(to: store)
        store.startVoting()
        XCTAssertEqual(store.session.stage, .pitching)
    }

    @MainActor
    func testDeadlineLocksSubmittedFamilyVotesButDoesNotInventVotes() async {
        let store = freshStore()
        store.addMember(name: "Sam", emoji: "👩", role: "Diner")
        addTwoPitches(to: store)
        store.startVoting()
        let afterDeadline = store.session.deadline.addingTimeInterval(1)
        store.checkDeadline(now: afterDeadline)
        XCTAssertEqual(store.session.stage, .voting)
        store.vote(.love, for: store.pitches[1].id)
        store.checkDeadline(now: afterDeadline)
        XCTAssertEqual(store.session.stage, .ticketLocked)
        XCTAssertEqual(store.winner?.id, store.pitches[1].id)
    }

    @MainActor
    func testTimerEndAndKitchenProgressSurviveRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryDirectories.append(directory)
        let url = directory.appendingPathComponent("kitchen.json")
        let store = OrderHomeStore(persistenceURL: url)
        addTwoPitches(to: store)
        store.startVoting()
        store.vote(.love, for: store.pitches[0].id)
        store.vote(.down, for: store.pitches[1].id)
        store.startCooking()
        let ingredient = try XCTUnwrap(store.winner?.ingredients.first)
        store.toggleIngredient(ingredient.id)
        store.advanceStep()
        store.startTimer(seconds: 90, title: "Simmer")
        let originalEnd = try XCTUnwrap(store.session.timerEnd)
        let restored = OrderHomeStore(persistenceURL: url)
        XCTAssertEqual(restored.session.stage, .cooking)
        XCTAssertEqual(restored.session.timerEnd?.timeIntervalSince1970 ?? 0, originalEnd.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(restored.session.timerTitle, "Simmer")
        XCTAssertEqual(restored.session.stepIndex, store.session.stepIndex)
        XCTAssertTrue(restored.session.checkedIngredientIDs.contains(ingredient.id))
        XCTAssertNil(restored.persistenceError)
    }

    @MainActor
    func testDinnerLifecycleResetsSessionAndPreservesHouseFavorites() async throws {
        let store = freshStore()
        store.startCooking()
        store.ringDinnerBell()
        XCTAssertEqual(store.session.stage, .pitching)
        addTwoPitches(to: store)
        let favorite = store.pitches[0].id
        store.toggleFavorite(favorite)
        store.startVoting()
        store.vote(.love, for: favorite)
        store.vote(.down, for: store.pitches[1].id)
        store.startCooking()
        XCTAssertEqual(store.session.stage, .cooking)
        store.startTimer(seconds: 30, title: "Rest")
        store.ringDinnerBell()
        XCTAssertEqual(store.session.stage, .served)
        XCTAssertNil(store.session.timerEnd)
        XCTAssertEqual(store.session.completedStepIDs.count, try XCTUnwrap(store.winner).steps.count)
        let previousID = store.session.id
        store.newDinner()
        XCTAssertNotEqual(store.session.id, previousID)
        XCTAssertEqual(store.session.stage, .pitching)
        XCTAssertTrue(store.pitches.isEmpty)
        XCTAssertTrue(store.votes.isEmpty)
        XCTAssertTrue(store.favoriteIDs.contains(favorite))
    }

    func testIngredientScalingPreservesFractionsAndZeroAttendance() {
        let ingredient = Ingredient(id: "rice", name: "Rice", amount: 1.5, unit: "cups")
        XCTAssertEqual(ingredient.quantity(for: 2, baseServings: 4), "¾ cups")
        XCTAssertEqual(ingredient.quantity(for: 6, baseServings: 4), "2¼ cups")
        XCTAssertEqual(ingredient.quantity(for: 0, baseServings: 4), "0 cups")
        let tiny = Ingredient(id: "salt", name: "Salt", amount: 0.1, unit: "tsp")
        XCTAssertEqual(tiny.quantity(for: 1, baseServings: 4), "0.025 tsp")
    }

    @MainActor
    func testRecipeImportRejectsUntrustedSchemesHostsAndCredentials() async throws {
        let store = freshStore()
        let initialCount = store.recipes.count
        for address in [
            "javascript:alert(1)",
            "http://www.youtube.com/watch?v=recipe",
            "https://youtube.com.example.org/watch?v=recipe",
            "https://notyoutube.com/watch?v=recipe",
            "https://name:password@www.youtube.com/watch?v=recipe",
            "https://www.youtube.com:444/watch?v=recipe"
        ] {
            XCTAssertFalse(store.addRecipe(title: "A saved meal", url: try XCTUnwrap(URL(string: address))), address)
        }
        XCTAssertFalse(store.addRecipe(title: "  ", url: try XCTUnwrap(URL(string: "https://youtu.be/recipe"))))
        XCTAssertEqual(store.recipes.count, initialCount)
    }

    @MainActor
    func testSavedRecipeDeduplicatesAndSurvivesRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryDirectories.append(directory)
        let persistenceURL = directory.appendingPathComponent("kitchen.json")
        let store = OrderHomeStore(persistenceURL: persistenceURL)
        let initialCount = store.recipes.count
        let original = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=orderhome-test#ingredients"))
        XCTAssertTrue(store.addRecipe(title: "Creator's noodles", url: original))
        let saved = try XCTUnwrap(store.recipes.last)
        XCTAssertTrue(store.favoriteIDs.contains(saved.id))
        XCTAssertTrue(saved.ingredients.isEmpty, "Saving a link must not fabricate scraped ingredients")
        XCTAssertNil(saved.sourceURL?.fragment)
        XCTAssertTrue(store.addRecipe(title: "Same recipe", url: try XCTUnwrap(URL(string: "https://WWW.YOUTUBE.COM:443/watch?v=orderhome-test#steps"))))
        XCTAssertEqual(store.recipes.count, initialCount + 1)
        store.nominate(saved)
        let restored = OrderHomeStore(persistenceURL: persistenceURL)
        XCTAssertEqual(restored.recipes.first(where: { $0.id == saved.id })?.title, "Creator's noodles")
        XCTAssertTrue(restored.favoriteIDs.contains(saved.id))
        XCTAssertEqual(restored.pitches.map(\.id), [saved.id])
        XCTAssertNil(restored.persistenceError)
    }

    @MainActor
    func testLeavingSampleKitchenClearsDemoStatePreservesLinksAndGuardsPersonalKitchen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryDirectories.append(directory)
        let persistenceURL = directory.appendingPathComponent("kitchen.json")
        let store = OrderHomeStore(persistenceURL: persistenceURL)
        store.loadSampleHousehold()
        XCTAssertTrue(store.addRecipe(title: "Saved creator recipe", url: try XCTUnwrap(URL(string: "https://youtu.be/preserve-my-recipe"))))
        let customRecipe = try XCTUnwrap(store.recipes.last)
        for recipe in store.pitches { store.vote(.love, for: recipe.id) }
        store.startCooking()
        store.startTimer(seconds: 90, title: "Sample simmer")
        XCTAssertEqual(store.session.stage, .cooking)
        XCTAssertFalse(store.votes.isEmpty)
        XCTAssertFalse(store.orders.isEmpty)
        XCTAssertFalse(store.favoriteIDs.isEmpty)
        XCTAssertNotNil(store.session.timerEnd)

        store.leaveSampleKitchen()
        XCTAssertFalse(store.hasOnboarded)
        XCTAssertEqual(store.household.members.count, 1)
        XCTAssertEqual(store.currentMember.id, "owner")
        XCTAssertEqual(store.selectedMemberID, "owner")
        XCTAssertEqual(store.session.stage, .pitching)
        XCTAssertTrue(store.pitches.isEmpty)
        XCTAssertTrue(store.votes.isEmpty)
        XCTAssertTrue(store.orders.isEmpty)
        XCTAssertTrue(store.favoriteIDs.isEmpty)
        XCTAssertNil(store.session.timerEnd)
        XCTAssertNil(store.session.timerTitle)
        XCTAssertNil(store.winner)
        XCTAssertTrue(store.recipes.contains(where: { $0.id == customRecipe.id }))

        let restored = OrderHomeStore(persistenceURL: persistenceURL)
        XCTAssertFalse(restored.hasOnboarded)
        XCTAssertEqual(restored.household, store.household)
        XCTAssertTrue(restored.votes.isEmpty)
        XCTAssertTrue(restored.orders.isEmpty)
        XCTAssertTrue(restored.favoriteIDs.isEmpty)
        XCTAssertNil(restored.session.timerEnd)
        XCTAssertEqual(restored.recipes.first(where: { $0.id == customRecipe.id })?.sourceURL, customRecipe.sourceURL)
        XCTAssertNil(restored.persistenceError)

        restored.completeOnboarding(name: "My personal kitchen", personName: "Taylor", mode: .family)
        restored.nominate(customRecipe)
        restored.toggleFavorite(customRecipe.id)
        restored.setOrderNote("Sauce on the side", memberID: restored.currentMember.id)
        let personalHousehold = restored.household
        let personalSession = restored.session
        restored.leaveSampleKitchen()
        XCTAssertTrue(restored.hasOnboarded, "The sample reset must not reset a personal kitchen")
        XCTAssertEqual(restored.household, personalHousehold)
        XCTAssertEqual(restored.session, personalSession)
        XCTAssertTrue(restored.favoriteIDs.contains(customRecipe.id))
        XCTAssertEqual(restored.orders[restored.currentMember.id], "Sauce on the side")
    }

    @MainActor
    func testCorruptSaveIsReportedAndPreserved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryDirectories.append(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("kitchen.json")
        let original = Data("broken save".utf8)
        try original.write(to: url)
        let store = OrderHomeStore(persistenceURL: url)
        XCTAssertNotNil(store.persistenceError)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(store.session.stage, .pitching)
    }
}
