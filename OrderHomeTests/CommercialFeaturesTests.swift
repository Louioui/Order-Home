import XCTest
import AppIntents
@testable import OrderHome

final class CommercialFeaturesTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
    }

    private func newPersistenceURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("kitchen.json")
    }

    // MARK: - 1. Smart Unit Conversions

    func testStandardUnitFormattingAndFractions() {
        let flour = Ingredient(id: "1", name: "Flour", amount: 1.5, unit: "cups")
        // 4 diners with baseServings 4 -> 1.5 cups
        XCTAssertEqual(flour.quantity(for: 4, baseServings: 4, unitSystem: .standard), "1½ cups")

        let rice = Ingredient(id: "2", name: "Rice", amount: 0.75, unit: "cup")
        XCTAssertEqual(rice.quantity(for: 4, baseServings: 4, unitSystem: .standard), "¾ cup")

        let garlic = Ingredient(id: "3", name: "Garlic", amount: 3, unit: "cloves")
        XCTAssertEqual(garlic.quantity(for: 4, baseServings: 4, unitSystem: .standard), "3 cloves")
    }

    func testMetricUnitConversions() {
        // 1 cup = 240 ml
        let milk = Ingredient(id: "1", name: "Milk", amount: 1.0, unit: "cup")
        XCTAssertEqual(milk.quantity(for: 4, baseServings: 4, unitSystem: .metric), "240 ml")

        // 5 cups = 1200 ml = 1.2 L
        let water = Ingredient(id: "2", name: "Water", amount: 5.0, unit: "cups")
        XCTAssertEqual(water.quantity(for: 4, baseServings: 4, unitSystem: .metric), "1.2 L")

        // 1 tbsp = 15 ml
        let oil = Ingredient(id: "3", name: "Olive Oil", amount: 1.0, unit: "tbsp")
        XCTAssertEqual(oil.quantity(for: 4, baseServings: 4, unitSystem: .metric), "15 ml")

        // 1 tsp = 5 ml
        let salt = Ingredient(id: "4", name: "Salt", amount: 1.0, unit: "tsp")
        XCTAssertEqual(salt.quantity(for: 4, baseServings: 4, unitSystem: .metric), "5 ml")

        // 8 oz = ~226.796 g -> rounded to 227 g
        let cheese = Ingredient(id: "5", name: "Cheese", amount: 8.0, unit: "oz")
        XCTAssertEqual(cheese.quantity(for: 4, baseServings: 4, unitSystem: .metric), "227 g")

        // 3 lbs = ~1.361 kg
        let pork = Ingredient(id: "6", name: "Pork Shoulder", amount: 3.0, unit: "lbs")
        let formattedPork = pork.quantity(for: 4, baseServings: 4, unitSystem: .metric)
        XCTAssertTrue(formattedPork.hasSuffix("kg"))

        // Unrecognized unit remains unchanged
        let scallions = Ingredient(id: "7", name: "Scallions", amount: 2.0, unit: "stalks")
        XCTAssertEqual(scallions.quantity(for: 4, baseServings: 4, unitSystem: .metric), "2 stalks")
    }

    func testImperialUnitConversions() {
        // 28.35 g -> 1 oz
        let butter = Ingredient(id: "1", name: "Butter", amount: 28.35, unit: "g")
        let butterText = butter.quantity(for: 4, baseServings: 4, unitSystem: .imperial)
        XCTAssertTrue(butterText.contains("oz") || butterText.contains("1"))

        // 500 ml -> cups
        let broth = Ingredient(id: "2", name: "Broth", amount: 500, unit: "ml")
        let brothText = broth.quantity(for: 4, baseServings: 4, unitSystem: .imperial)
        XCTAssertTrue(brothText.contains("cups"))

        // 15 ml -> 1 tbsp
        let vinegar = Ingredient(id: "3", name: "Vinegar", amount: 15, unit: "ml")
        XCTAssertEqual(vinegar.quantity(for: 4, baseServings: 4, unitSystem: .imperial), "1 tbsp")

        // 5 ml -> 1 tsp
        let vanilla = Ingredient(id: "4", name: "Vanilla", amount: 5, unit: "ml")
        XCTAssertEqual(vanilla.quantity(for: 4, baseServings: 4, unitSystem: .imperial), "1 tsp")
    }

    func testUnitSystemRegionalDefault() {
        let regional = UnitSystem.regionalDefault
        XCTAssertTrue([UnitSystem.metric, UnitSystem.imperial].contains(regional))
    }

    // MARK: - 2. Reminders Aisle Classification

    func testSupermarketAisleClassification() {
        let aisle = RemindersGroceryService.SupermarketAisle.classify

        // Produce
        XCTAssertEqual(aisle("fresh basil leaves"), .produce)
        XCTAssertEqual(aisle("Yellow Onion"), .produce)
        XCTAssertEqual(aisle("Minced Garlic"), .produce)
        XCTAssertEqual(aisle("Ripe Avocados"), .produce)
        XCTAssertEqual(aisle("Baby Spinach"), .produce)

        // Meat & Seafood
        XCTAssertEqual(aisle("Boneless Skinless Chicken Thighs"), .meatSeafood)
        XCTAssertEqual(aisle("Atlantic Salmon Fillet"), .meatSeafood)
        XCTAssertEqual(aisle("Ground Beef (80/20)"), .meatSeafood)
        XCTAssertEqual(aisle("Pork Belly"), .meatSeafood)

        // Dairy & Refrigerated
        XCTAssertEqual(aisle("Unsalted Butter"), .dairyRefrigerated)
        XCTAssertEqual(aisle("Grated Parmesan Cheese"), .dairyRefrigerated)
        XCTAssertEqual(aisle("Heavy Cream"), .dairyRefrigerated)
        XCTAssertEqual(aisle("Large Eggs"), .dairyRefrigerated)

        // Bakery
        XCTAssertEqual(aisle("Brioche Buns"), .bakery)
        XCTAssertEqual(aisle("Flour Tortillas"), .bakery)
        XCTAssertEqual(aisle("Crusty French Bread"), .bakery)

        // Pantry
        XCTAssertEqual(aisle("Jasmine Rice"), .pantry)
        XCTAssertEqual(aisle("Extra Virgin Olive Oil"), .pantry)
        XCTAssertEqual(aisle("Rigatoni Pasta"), .pantry)
        XCTAssertEqual(aisle("Low-Sodium Soy Sauce"), .pantry)
        XCTAssertEqual(aisle("Kosher Salt"), .pantry)

        // Other
        XCTAssertEqual(aisle("Toothpicks"), .other)
        XCTAssertEqual(aisle("Aluminum Foil"), .other)
    }

    // MARK: - 3. Smart Recipe Suggestions Engine

    func testDinnerSuggestionsWithEmptyHistoryReturnsCatalog() {
        let recipes = RecipeCatalog.all
        let suggestions = DinnerSuggestionEngine.generateSuggestions(
            recipes: recipes,
            history: [],
            favorites: ["pasta"],
            now: Date(),
            limit: 3
        )

        XCTAssertEqual(suggestions.count, 3)
        // Pasta is a favorite, so it should rank first among candidates
        XCTAssertEqual(suggestions.first?.recipe.id, "pasta")
    }

    func testDinnerSuggestionsDayOfWeekAffinity() {
        let calendar = Calendar.current
        let today = Date()

        // Create 2 historical dinners on this exact same weekday for "bulgogi"
        let pastDate1 = calendar.date(byAdding: .day, value: -7, to: today)!
        let pastDate2 = calendar.date(byAdding: .day, value: -14, to: today)!

        let record1 = DinnerRecord(
            id: "rec-1",
            recipeID: "bulgogi",
            recipeTitle: "Bulgogi Bowls",
            servedAt: pastDate1,
            dinerNames: ["Chef"],
            dinerIDs: ["1"],
            ratings: ["1": DinnerRating.loved.rawValue]
        )
        let record2 = DinnerRecord(
            id: "rec-2",
            recipeID: "bulgogi",
            recipeTitle: "Bulgogi Bowls",
            servedAt: pastDate2,
            dinerNames: ["Chef"],
            dinerIDs: ["1"],
            ratings: ["1": DinnerRating.loved.rawValue]
        )

        let suggestions = DinnerSuggestionEngine.generateSuggestions(
            recipes: RecipeCatalog.all,
            history: [record1, record2],
            favorites: [],
            now: today,
            limit: 3
        )

        let topSuggestion = try? XCTUnwrap(suggestions.first)
        XCTAssertEqual(topSuggestion?.recipe.id, "bulgogi")
        XCTAssertEqual(topSuggestion?.matchTag, "Table Habit")
        XCTAssertTrue(topSuggestion?.headline.contains("Tradition") == true)
    }

    func testDinnerSuggestionsRecencyCooldownSuppressesRecentMeal() {
        let calendar = Calendar.current
        let today = Date()
        // Cooked yesterday
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let recentRecord = DinnerRecord(
            id: "rec-recent",
            recipeID: "salmon",
            recipeTitle: "Sheet Pan Salmon",
            servedAt: yesterday,
            dinerNames: ["Chef"],
            dinerIDs: ["1"],
            ratings: ["1": DinnerRating.loved.rawValue]
        )

        let suggestions = DinnerSuggestionEngine.generateSuggestions(
            recipes: RecipeCatalog.all,
            history: [recentRecord],
            favorites: ["salmon"], // Even as a favorite, yesterday's meal is penalized
            now: today,
            limit: 3
        )

        // Salmon should not be the top pick because it was just eaten yesterday (-100 penalty)
        XCTAssertNotEqual(suggestions.first?.recipe.id, "salmon")
    }

    // MARK: - 4. Siri & Apple Intelligence App Intents

    @MainActor
    func testCheckDinnerStatusIntentStages() async throws {
        let store = OrderHomeStore.shared
        store.resetAllData()

        let intent = CheckDinnerStatusIntent()

        // 1. Pitching stage with no pitches
        _ = try await intent.perform()

        // 2. Pitching with a dish
        store.nominate(RecipeCatalog.all[0])
        _ = try await intent.perform()

        // 3. Voting stage
        store.nominate(RecipeCatalog.all[1])
        store.startVoting()
        _ = try await intent.perform()

        // 4. Ticket locked stage
        store.vote(.love, for: store.pitches[0].id)
        store.lockWinner()
        _ = try await intent.perform()

        // 5. Cooking stage
        store.startCooking()
        _ = try await intent.perform()

        // 6. Served stage
        store.ringDinnerBell()
        _ = try await intent.perform()
    }

    @MainActor
    func testPitchCravingIntent() async throws {
        let store = OrderHomeStore.shared
        store.resetAllData()

        var intent = PitchCravingIntent()
        intent.dishName = ""
        _ = try await intent.perform()

        // Pitch an existing recipe title
        intent.dishName = "Rigatoni"
        _ = try await intent.perform()
        XCTAssertTrue(store.session.recipeIDs.contains("pasta"))

        // Pitching the same dish again warns user without crashing
        _ = try await intent.perform()
    }

    @MainActor
    func testToggleDinnerAttendanceIntent() async throws {
        let store = OrderHomeStore.shared
        store.resetAllData()

        guard let memberID = store.household.members.first?.id else {
            XCTFail("Owner member not found")
            return
        }

        var intent = ToggleDinnerAttendanceIntent()
        intent.eatingHome = false
        _ = try await intent.perform()
        XCTAssertFalse(store.household.members.first(where: { $0.id == memberID })?.attending ?? true)

        intent.eatingHome = true
        _ = try await intent.perform()
        XCTAssertTrue(store.household.members.first(where: { $0.id == memberID })?.attending ?? false)
    }

    // MARK: - 5. Apple Review Guideline 5.1.1(v) Data Deletion & Reset

    @MainActor
    func testResetAllDataWipesEverythingClean() throws {
        let url = newPersistenceURL()
        let store = OrderHomeStore(persistenceURL: url)

        // Add dummy state
        store.nominate(RecipeCatalog.all[0])
        store.nominate(RecipeCatalog.all[1])
        store.startVoting()
        store.vote(.love, for: store.pitches[0].id)
        store.lockWinner()
        store.startCooking()
        store.ringDinnerBell()

        XCTAssertFalse(store.history.isEmpty)
        XCTAssertEqual(store.session.stage, .served)

        // Wipe data
        store.resetAllData()

        XCTAssertTrue(store.history.isEmpty)
        XCTAssertEqual(store.session.stage, .pitching)
        XCTAssertTrue(store.session.recipeIDs.isEmpty)
        XCTAssertTrue(store.favoriteIDs.isEmpty)
        XCTAssertFalse(store.hasOnboarded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSharedKitchenContainerResetClearsFile() throws {
        let containerURL = SharedKitchenContainer.kitchenFileURL
        let testData = Data("{\"test\": true}".utf8)
        try? FileManager.default.createDirectory(at: containerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try testData.write(to: containerURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: containerURL.path))

        SharedKitchenContainer.reset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: containerURL.path))
    }
}
