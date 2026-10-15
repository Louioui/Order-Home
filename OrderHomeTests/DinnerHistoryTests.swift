import XCTest
@testable import OrderHome

/// Dinner history and the post-meal rating: one record per served dinner,
/// ratings that can add (never remove) a House Menu favorite, and persistence
/// that can never cost someone their kitchen.
final class DinnerHistoryTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories { try? FileManager.default.removeItem(at: directory) }
        temporaryDirectories = []
    }

    private func newPersistenceURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("kitchen.json")
    }

    /// Takes a kitchen through pitch, vote, cook and the dinner bell.
    @MainActor
    private func serveDinner(on store: OrderHomeStore) {
        store.nominate(RecipeCatalog.all[0])
        store.nominate(RecipeCatalog.all[1])
        store.startVoting()
        store.vote(.love, for: store.pitches[0].id)
        store.vote(.down, for: store.pitches[1].id)
        store.startCooking()
        store.ringDinnerBell()
    }

    /// Rewrites the saved JSON the way an older or damaged file would look.
    private func editSave(at url: URL, _ change: (inout [String: Any]) -> Void) throws {
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        change(&object)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    private func sharedSnapshot(session: String = "null") throws -> CloudKitchenSnapshot {
        let json = """
        {"household":{"id":"home","name":"Shared table","mode":"family","owner_user_id":"user"},"members":[{"id":"member","user_id":"user","display_name":"Sam","avatar_emoji":"🍽️","default_role":"head_chef","dietary_tags":[]}],"session":\(session),"pitches":[],"votes":[],"orders":[]}
        """
        return try CloudJSON.decoder().decode(CloudKitchenSnapshot.self, from: Data(json.utf8))
    }

    @MainActor
    func testRingingTheBellRecordsOneDinnerAndNothingDuplicatesIt() throws {
        let store = OrderHomeStore(persistenceURL: newPersistenceURL())
        XCTAssertTrue(store.history.isEmpty)
        serveDinner(on: store)
        XCTAssertEqual(store.session.stage, .served)
        let record = try XCTUnwrap(store.history.first)
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(record.id, store.session.id)
        XCTAssertEqual(record.recipeID, store.winner?.id)
        XCTAssertEqual(record.recipeTitle, store.winner?.title)
        XCTAssertEqual(record.dinerNames, ["You"])
        XCTAssertEqual(record.dinerIDs, ["owner"])
        XCTAssertEqual(record.servedAt.timeIntervalSinceNow, 0, accuracy: 5)
        XCTAssertEqual(store.currentDinnerRecord, record)

        store.ringDinnerBell()
        store.rateDinner(.good, memberID: "owner")
        store.rateDinner(.loved, memberID: "owner")
        XCTAssertEqual(store.history.count, 1, "Neither the bell nor a rating may create a second record")
    }

    @MainActor
    func testRatingsAreRecordedToggledAndOnlyEverAddAFavorite() throws {
        let store = OrderHomeStore(persistenceURL: newPersistenceURL())
        serveDinner(on: store)
        let winner = try XCTUnwrap(store.winner)
        XCTAssertNil(store.rating(for: "owner"))

        store.rateDinner(.good, memberID: "owner")
        XCTAssertEqual(store.rating(for: "owner"), .good)
        XCTAssertFalse(store.favoriteIDs.contains(winner.id), "A merely good dinner is not saved automatically")

        store.rateDinner(.loved, memberID: "owner")
        XCTAssertEqual(store.rating(for: "owner"), .loved)
        XCTAssertTrue(store.favoriteIDs.contains(winner.id))
        XCTAssertEqual(store.toast, "\(winner.title) joined your House Menu.")

        // Someone un-hearts it on purpose; a rating that does not newly qualify
        // the dish must not bring it back.
        store.toggleFavorite(winner.id)
        XCTAssertFalse(store.favoriteIDs.contains(winner.id))
        store.rateDinner(.good, memberID: "owner")
        XCTAssertFalse(store.favoriteIDs.contains(winner.id))

        // Tapping the rating you already gave takes it back, and a rating
        // never removes a favorite.
        store.rateDinner(.good, memberID: "owner")
        XCTAssertNil(store.rating(for: "owner"))
        store.toggleFavorite(winner.id)
        store.rateDinner(.tweak, memberID: "owner")
        XCTAssertTrue(store.favoriteIDs.contains(winner.id))
        XCTAssertEqual(store.rating(for: "owner"), .tweak)
    }

    /// Pins the default in `HouseFavoritePolicy`. If you change that rule on
    /// purpose, update this test with it.
    func testDefaultPolicySavesAnyLovedDish() {
        XCTAssertTrue(HouseFavoritePolicy.shouldSave(ratings: [.loved], dinerCount: 4))
        XCTAssertTrue(HouseFavoritePolicy.shouldSave(ratings: [.good, .loved, .tweak], dinerCount: 3))
        XCTAssertFalse(HouseFavoritePolicy.shouldSave(ratings: [.good, .tweak], dinerCount: 2))
        XCTAssertFalse(HouseFavoritePolicy.shouldSave(ratings: [], dinerCount: 2))
    }

    @MainActor
    func testRatingNeedsAServedDinnerAndSomeoneAtTheTable() {
        let store = OrderHomeStore(persistenceURL: newPersistenceURL())
        store.rateDinner(.loved, memberID: "owner")
        XCTAssertTrue(store.history.isEmpty, "Nothing has been served yet")
        serveDinner(on: store)
        store.rateDinner(.loved, memberID: "stranger")
        XCTAssertTrue(store.currentDinnerRecord?.ratings.isEmpty == true)
    }

    @MainActor
    func testOnlyThePeopleAtTheTableCanRateAndLaterChangesDoNotChangeWho() throws {
        let store = OrderHomeStore(persistenceURL: newPersistenceURL())
        store.addMember(name: "Guest", emoji: "🍽️", role: "Diner")
        let guest = try XCTUnwrap(store.household.members.last)
        store.nominate(RecipeCatalog.all[0])
        store.nominate(RecipeCatalog.all[1])
        store.startVoting()
        for member in store.household.members {
            store.selectedMemberID = member.id
            store.vote(.love, for: store.pitches[0].id)
            store.vote(.down, for: store.pitches[1].id)
        }
        store.startCooking()
        store.ringDinnerBell()
        let record = try XCTUnwrap(store.currentDinnerRecord)
        XCTAssertEqual(Set(try XCTUnwrap(record.dinerIDs)), ["owner", guest.id])

        // Someone joins the household after dinner was served and defaults to attending...
        store.addMember(name: "Latecomer", emoji: "🍽️", role: "Diner")
        let latecomer = try XCTUnwrap(store.household.members.last)
        XCTAssertTrue(store.activeMembers.contains { $0.id == latecomer.id })
        XCTAssertEqual(Set(store.dinersAtTable.map(\.id)), ["owner", guest.id])
        store.rateDinner(.loved, memberID: latecomer.id)
        XCTAssertNil(store.rating(for: latecomer.id), "A person who was not at the table cannot rate this dinner")

        // ...while a guest who leaves the table afterwards can still rate the meal they ate.
        store.setAttendance(memberID: guest.id, attending: false)
        XCTAssertEqual(Set(store.dinersAtTable.map(\.id)), ["owner", guest.id])
        store.rateDinner(.good, memberID: guest.id)
        XCTAssertEqual(store.rating(for: guest.id), .good)
    }

    @MainActor
    func testDinnersRecordedBeforeTableIDsExistedStillLoadAndFallBackToTheCurrentTable() throws {
        let url = newPersistenceURL()
        let store = OrderHomeStore(persistenceURL: url)
        serveDinner(on: store)
        try editSave(at: url) { object in
            var entries = (object["history"] as? [[String: Any]]) ?? []
            for index in entries.indices { entries[index].removeValue(forKey: "dinerIDs") }
            object["history"] = entries
        }
        let restored = OrderHomeStore(persistenceURL: url)
        XCTAssertNil(restored.persistenceError)
        let record = try XCTUnwrap(restored.currentDinnerRecord)
        XCTAssertNil(record.dinerIDs)
        XCTAssertEqual(restored.dinersAtTable.map(\.id), ["owner"], "Falls back to who is attending now")
        restored.rateDinner(.loved, memberID: "owner")
        XCTAssertEqual(restored.rating(for: "owner"), .loved)
    }

    @MainActor
    func testHistorySurvivesRelaunchWithRatingsIntact() throws {
        let url = newPersistenceURL()
        let store = OrderHomeStore(persistenceURL: url)
        serveDinner(on: store)
        store.rateDinner(.loved, memberID: "owner")
        let restored = OrderHomeStore(persistenceURL: url)
        XCTAssertNil(restored.persistenceError)
        XCTAssertEqual(restored.history, store.history)
        XCTAssertEqual(restored.rating(for: "owner"), .loved)
        XCTAssertEqual(restored.servedCount(of: try XCTUnwrap(store.winner).id), 1)
        XCTAssertNotNil(restored.lastServed(try XCTUnwrap(store.winner).id))
    }

    @MainActor
    func testHistoryIsCappedAndPrunesTheOldestDinners() throws {
        let store = OrderHomeStore(persistenceURL: newPersistenceURL())
        serveDinner(on: store)
        let oldest = try XCTUnwrap(store.history.first).id
        store.newDinner()
        for _ in 0..<(OrderHomeStore.historyLimit + 2) {
            serveDinner(on: store)
            store.newDinner()
        }
        XCTAssertEqual(store.history.count, OrderHomeStore.historyLimit)
        XCTAssertFalse(store.history.contains { $0.id == oldest })
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(store.history.first).servedAt, try XCTUnwrap(store.history.last).servedAt, "Newest first")
    }

    @MainActor
    func testSaveFromBeforeHistoryExistedStillOpensAndAServedDinnerCanBeRatedLate() throws {
        let url = newPersistenceURL()
        let store = OrderHomeStore(persistenceURL: url)
        serveDinner(on: store)
        try editSave(at: url) { $0.removeValue(forKey: "history") }
        let restored = OrderHomeStore(persistenceURL: url)
        XCTAssertNil(restored.persistenceError)
        XCTAssertEqual(restored.household, store.household)
        XCTAssertEqual(restored.session.stage, .served)
        XCTAssertTrue(restored.history.isEmpty)

        restored.rateDinner(.good, memberID: "owner")
        XCTAssertEqual(restored.history.count, 1, "A dinner served before history existed is recorded when first rated")
        XCTAssertEqual(restored.rating(for: "owner"), .good)
    }

    @MainActor
    func testDamagedHistoryNeverCostsSomeoneTheirKitchen() throws {
        let url = newPersistenceURL()
        let store = OrderHomeStore(persistenceURL: url)
        serveDinner(on: store)
        store.rateDinner(.loved, memberID: "owner")
        let good = try XCTUnwrap(store.history.first)

        try editSave(at: url) { object in
            var entries = (object["history"] as? [Any]) ?? []
            entries.insert("not a dinner", at: 0)
            entries.append(["id": 5])
            entries.append(NSNull())
            object["history"] = entries
        }
        let withJunk = OrderHomeStore(persistenceURL: url)
        XCTAssertNil(withJunk.persistenceError)
        XCTAssertEqual(withJunk.household, store.household)
        XCTAssertEqual(withJunk.history, [good], "Readable entries are kept; damaged ones are dropped")

        try editSave(at: url) { $0["history"] = "not a list at all" }
        let notAList = OrderHomeStore(persistenceURL: url)
        XCTAssertNil(notAList.persistenceError)
        XCTAssertEqual(notAList.household, store.household)
        XCTAssertTrue(notAList.history.isEmpty)

        try editSave(at: url) { object in
            object["history"] = [[
                "id": good.id, "recipeID": good.recipeID, "recipeTitle": good.recipeTitle,
                "servedAt": 0, "dinerNames": ["You"], "ratings": ["owner": "adored"]
            ]]
        }
        let unknownRating = OrderHomeStore(persistenceURL: url)
        XCTAssertNil(unknownRating.persistenceError)
        XCTAssertEqual(unknownRating.history.count, 1)
        XCTAssertNil(unknownRating.rating(for: "owner"), "A rating this version doesn't know is ignored, not fatal")
    }

    @MainActor
    func testLeavingTheSampleKitchenLeavesNoSampleDinnersBehind() throws {
        let url = newPersistenceURL()
        let store = OrderHomeStore(persistenceURL: url)
        store.loadSampleHousehold()
        for recipe in store.pitches { store.vote(.love, for: recipe.id) }
        store.startCooking()
        store.ringDinnerBell()
        XCTAssertEqual(store.history.count, 1)

        store.leaveSampleKitchen()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertTrue(OrderHomeStore(persistenceURL: url).history.isEmpty)
    }

    @MainActor
    func testPersonalHistorySurvivesAVisitToASharedKitchen() throws {
        let url = newPersistenceURL()
        let store = OrderHomeStore(persistenceURL: url)
        serveDinner(on: store)
        let record = try XCTUnwrap(store.history.first)

        try store.applySharedSnapshot(try sharedSnapshot(), userID: "user")
        XCTAssertTrue(store.isSharedPresentation)
        XCTAssertTrue(store.history.isEmpty, "A shared kitchen must not show the local kitchen's dinners")

        store.rateDinner(.loved, memberID: "member")
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertEqual(store.toast, "Use your connected kitchen to make this change.")

        // A save while a shared kitchen is showing writes the stashed local
        // kitchen. It must carry the history, not erase it.
        store.toggleFavorite(RecipeCatalog.all[0].id)
        XCTAssertEqual(OrderHomeStore(persistenceURL: url).history, [record])

        store.restoreLocalKitchen()
        XCTAssertFalse(store.isSharedPresentation)
        XCTAssertEqual(store.history, [record])
    }

    @MainActor
    func testAnInvalidSharedDinnerLeavesTheLocalKitchenAndItsHistoryUntouched() throws {
        let url = newPersistenceURL()
        let store = OrderHomeStore(persistenceURL: url)
        serveDinner(on: store)
        let record = try XCTUnwrap(store.history.first)
        let household = store.household
        let selected = store.selectedMemberID

        let unknownStatus = #"{"id":"dinner","household_id":"home","head_chef_id":"member","status":"mystery","voting_deadline":"2026-10-16T01:30:00Z","winning_pitch_id":null,"missing_groceries":[],"cooking_step_index":0}"#
        let lockedWithoutWinner = #"{"id":"dinner","household_id":"home","head_chef_id":"member","status":"ticket_locked","voting_deadline":"2026-10-16T01:30:00Z","winning_pitch_id":null,"missing_groceries":[],"cooking_step_index":0}"#
        for (name, dinner) in [("an unknown status", unknownStatus), ("a locked dinner with no winner", lockedWithoutWinner)] {
            XCTAssertThrowsError(try store.applySharedSnapshot(try sharedSnapshot(session: dinner), userID: "user"), name) { error in
                XCTAssertEqual(error as? CloudServiceError, .dinnerChanged, name)
            }
            XCTAssertFalse(store.isSharedPresentation, name)
            XCTAssertEqual(store.history, [record], "\(name): history must not be cleared")
            XCTAssertEqual(store.household, household, "\(name): the household must not be replaced")
            XCTAssertEqual(store.selectedMemberID, selected, name)
        }

        // The failed attempts must not poison the next ordinary save.
        store.toggleFavorite(RecipeCatalog.all[0].id)
        let reloaded = OrderHomeStore(persistenceURL: url)
        XCTAssertEqual(reloaded.history, [record])
        XCTAssertEqual(reloaded.household, household)
    }
}
