import XCTest
@testable import OrderHome

/// The iMessage poll: the state that travels inside a message URL, the rules
/// for voting and deciding, and the guarantee that a chat poll ranks dishes the
/// same way the app's own kitchen vote does.
final class ChatPollTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var deadline: Date { start.addingTimeInterval(3_600) }

    private func dish(_ index: Int) -> ChatPoll.Dish { PollDishMenu.all[index].dish }

    private func poll(dishes: Int = 3, expected: Int = 3) throws -> ChatPoll {
        try XCTUnwrap(ChatPoll.new(
            dishes: (0..<dishes).map(dish), deadline: deadline, creator: "creator1", expectedVoters: expected
        ))
    }

    /// A message URL built from hand-written JSON, to exercise the decoder.
    private func url(json: String) -> URL {
        let payload = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "orderhome://poll?p=\(payload)")!
    }

    private let validJSON = #"{"v":1,"i":"poll1234","d":[{"i":"bulgogi","t":"Bulgogi","m":35},{"i":"pasta","t":"Rigatoni","m":25}],"e":1800003600,"o":"creator1","x":2,"b":{"aaaaaaaa":"20"}}"#

    // MARK: Round trip and decoding

    func testPollSurvivesTheMessageURLUnchanged() throws {
        var original = try poll()
        original = try XCTUnwrap(original.casting([2, 1, 0], voter: "voter001", now: start))
        original = try XCTUnwrap(original.casting([0, 1, 2], voter: "voter002", now: start)).closing()
        guard case .poll(let decoded) = ChatPoll.decode(original.url) else { return XCTFail("Should decode") }
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.closedEarly)
        XCTAssertEqual(decoded.deadline, deadline)
        XCTAssertEqual(original.url.scheme, "orderhome")
    }

    func testAHandWrittenValidPayloadDecodes() {
        guard case .poll(let decoded) = ChatPoll.decode(url(json: validJSON)) else { return XCTFail("Should decode") }
        XCTAssertEqual(decoded.dishes.map(\.id), ["bulgogi", "pasta"])
        XCTAssertEqual(decoded.ballots["aaaaaaaa"], [2, 0])
        XCTAssertEqual(decoded.expectedVoters, 2)
    }

    func testMalformedURLsAreInvalidAndNeverCrash() {
        let bad: [String] = [
            "https://example.com/poll?p=abc",
            "orderhome://kitchen",
            "orderhome://poll",
            "orderhome://poll?p=",
            "orderhome://poll?p=!!!not-base64!!!",
            "orderhome://poll?q=\(Data("{}".utf8).base64EncodedString())",
            "orderhome://poll?p=\(String(repeating: "A", count: 9_000))"
        ]
        for text in bad { XCTAssertEqual(ChatPoll.decode(URL(string: text)!), .invalid, text) }
        for json in ["not json", "[]", "{}", #"{"v":1}"#, #"{"v":0,"i":"a"}"#, #"{"v":"one"}"#] {
            XCTAssertEqual(ChatPoll.decode(url(json: json)), .invalid, json)
        }
    }

    func testAPollFromANewerVersionIsReportedNotRejectedAsBroken() {
        XCTAssertEqual(ChatPoll.decode(url(json: #"{"v":2,"somethingNew":true}"#)), .newerVersion)
    }

    func testDamagedPartsAreRejectedWithoutLosingTheRest() throws {
        // A ballot with the wrong number of digits, a bad digit and an empty key are dropped; the poll survives.
        let withBadBallots = #"{"v":1,"i":"poll1234","d":[{"i":"a","t":"A","m":5},{"i":"b","t":"B","m":5}],"e":1800003600,"o":"c","x":4,"b":{"good0001":"21","short001":"2","digit001":"29","":"10"}}"#
        guard case .poll(let decoded) = ChatPoll.decode(url(json: withBadBallots)) else { return XCTFail("Should decode") }
        XCTAssertEqual(decoded.ballots, ["good0001": [2, 1]])

        let oneDish = #"{"v":1,"i":"p","d":[{"i":"a","t":"A","m":5}],"e":1,"o":"c","x":1,"b":{}}"#
        let sixDishes = "[" + (0..<6).map { #"{"i":"d\#($0)","t":"D","m":5}"# }.joined(separator: ",") + "]"
        let duplicates = #"{"v":1,"i":"p","d":[{"i":"a","t":"A","m":5},{"i":"a","t":"B","m":5}],"e":1,"o":"c","x":1,"b":{}}"#
        let blankTitle = #"{"v":1,"i":"p","d":[{"i":"a","t":"  ","m":5},{"i":"b","t":"B","m":5}],"e":1,"o":"c","x":1,"b":{}}"#
        XCTAssertEqual(ChatPoll.decode(url(json: oneDish)), .invalid)
        XCTAssertEqual(ChatPoll.decode(url(json: #"{"v":1,"i":"p","d":\#(sixDishes),"e":1,"o":"c","x":1,"b":{}}"#)), .invalid)
        XCTAssertEqual(ChatPoll.decode(url(json: duplicates)), .invalid)
        XCTAssertEqual(ChatPoll.decode(url(json: blankTitle)), .invalid)
    }

    func testTheURLStaysSmallAtFiveDishesAndAFullGroup() throws {
        var big = try XCTUnwrap(ChatPoll.new(
            dishes: PollDishMenu.all.prefix(5).map(\.dish), deadline: deadline, creator: "creator1", expectedVoters: 12
        ))
        for index in 0..<12 {
            let voter = ChatPoll.voterKey(for: UUID())
            big = try XCTUnwrap(big.casting([2, 1, 0, 2, 1].shuffled(), voter: voter, now: start), "voter \(index)")
        }
        big = big.closing()
        let size = big.url.absoluteString.utf8.count
        XCTAssertLessThan(size, 2_000, "A poll URL of \(size) bytes is too large for a message")
        guard case .poll(let decoded) = ChatPoll.decode(big.url) else { return XCTFail("Should decode") }
        XCTAssertEqual(decoded, big)
    }

    // MARK: Creating and voting

    func testPollsNeedBetweenTwoAndFiveDistinctDishes() {
        XCTAssertNil(ChatPoll.new(dishes: [dish(0)], deadline: deadline, creator: "c", expectedVoters: 2))
        XCTAssertNil(ChatPoll.new(dishes: (0..<6).map(dish), deadline: deadline, creator: "c", expectedVoters: 2))
        XCTAssertNil(ChatPoll.new(dishes: [dish(0), dish(0)], deadline: deadline, creator: "c", expectedVoters: 2))
        XCTAssertNil(ChatPoll.new(dishes: [dish(0), dish(1)], deadline: deadline, creator: "", expectedVoters: 2))
        XCTAssertNotNil(ChatPoll.new(dishes: [dish(0), dish(1)], deadline: deadline, creator: "c", expectedVoters: 2))
    }

    func testAReVoteReplacesTheOldBallotInsteadOfAddingAnother() throws {
        var current = try poll()
        current = try XCTUnwrap(current.casting([2, 2, 2], voter: "voter001", now: start))
        current = try XCTUnwrap(current.casting([0, 0, 1], voter: "voter001", now: start))
        XCTAssertEqual(current.ballots.count, 1)
        XCTAssertEqual(current.ballots["voter001"], [0, 0, 1])
        XCTAssertEqual(current.leader?.dish.id, dish(2).id)
    }

    func testIncompleteOrInvalidBallotsAreRefused() throws {
        let current = try poll()
        XCTAssertNil(current.casting([2, 1], voter: "voter001", now: start), "Must cover every dish")
        XCTAssertNil(current.casting([2, 1, 3], voter: "voter001", now: start))
        XCTAssertNil(current.casting([2, 1, -1], voter: "voter001", now: start))
        XCTAssertNil(current.casting([2, 1, 0], voter: "", now: start))
    }

    func testADecodedPollNeverHoldsMoreThanTheBallotCap() throws {
        // Voting itself stops once everyone has voted, so the cap guards the
        // decoder against a hand-crafted message with an enormous ballot list.
        let ballots = (0..<(ChatPoll.maxBallots + 6)).map { #""voter\#(String(format: "%03d", $0))":"21""# }.joined(separator: ",")
        let json = #"{"v":1,"i":"p","d":[{"i":"a","t":"A","m":5},{"i":"b","t":"B","m":5}],"e":1800003600,"o":"c","x":500,"b":{\#(ballots)}}"#
        guard case .poll(let decoded) = ChatPoll.decode(url(json: json)) else { return XCTFail("Should decode") }
        XCTAssertEqual(decoded.ballots.count, ChatPoll.maxBallots)
        XCTAssertEqual(decoded.expectedVoters, ChatPoll.maxBallots, "An absurd headcount is clamped")
    }

    // MARK: When it is decided

    func testAPollIsDecidedByTheDeadlineTheCreatorOrEveryoneVoting() throws {
        let open = try poll(expected: 2)
        XCTAssertNil(open.decision(now: start))
        XCTAssertTrue(open.isOpen(now: start))

        XCTAssertEqual(open.decision(now: deadline), .deadlinePassed)
        XCTAssertEqual(open.closing().decision(now: start), .closedByCreator)

        let first = try XCTUnwrap(open.casting([2, 1, 0], voter: "voter001", now: start))
        XCTAssertNil(first.decision(now: start), "One of two people is not everyone")
        let second = try XCTUnwrap(first.casting([0, 1, 2], voter: "voter002", now: start))
        XCTAssertEqual(second.decision(now: start), .everyoneVoted)
    }

    func testNoVotesCanBeCastOnceThePollIsOver() throws {
        let open = try poll()
        XCTAssertNil(open.casting([2, 1, 0], voter: "voter001", now: deadline), "After the deadline")
        XCTAssertNil(open.closing().casting([2, 1, 0], voter: "voter001", now: start), "After the creator closed it")
        let decidedByEveryone = try XCTUnwrap(try poll(expected: 1).casting([2, 1, 0], voter: "voter001", now: start))
        XCTAssertNil(decidedByEveryone.casting([0, 1, 2], voter: "voter001", now: start), "After everyone voted")
    }

    func testAPollWithNoVotesHasNoLeader() throws {
        let empty = try poll()
        XCTAssertNil(empty.leader)
        XCTAssertEqual(empty.results().map(\.percent), [0, 0, 0])
        XCTAssertEqual(empty.progressText, "0 of 3 voted")
    }

    // MARK: Ranking matches the app

    /// Runs the same ballots through the app's own kitchen vote and a chat poll.
    /// Both must pick the same dish: higher score, then fewer passes, then the
    /// order the dishes were pitched.
    @MainActor
    private func kitchenWinner(ballots: [[Int]], dishCount: Int) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OrderHomeStore(persistenceURL: directory.appendingPathComponent("kitchen.json"))
        for index in 1..<ballots.count { store.addMember(name: "Diner \(index)", emoji: "🍽️", role: "Diner") }
        let recipes = (0..<dishCount).map { PollDishMenu.all[$0].id }.compactMap { id in RecipeCatalog.all.first { $0.id == id } }
        for recipe in recipes { store.nominate(recipe) }
        store.startVoting()
        for (voterIndex, ballot) in ballots.enumerated() {
            store.selectedMemberID = store.household.members[voterIndex].id
            for (dishIndex, score) in ballot.enumerated() {
                store.vote(try XCTUnwrap(Reaction(rawValue: score)), for: recipes[dishIndex].id)
            }
        }
        return try XCTUnwrap(store.winner?.id, "The kitchen vote should be decided once everyone has reacted")
    }

    @MainActor
    func testChatPollsRankDishesExactlyLikeTheKitchenVote() throws {
        let scenarios: [(name: String, ballots: [[Int]])] = [
            ("clear winner", [[2, 1, 0], [2, 0, 1], [1, 2, 0]]),
            ("score tie goes to the dish with fewer passes", [[2, 1, 0], [0, 1, 0], [2, 2, 0]]),
            ("exact tie goes to the dish pitched first", [[1, 1, 0], [1, 1, 0], [0, 0, 0]]),
            ("everyone passes on everything", [[0, 0, 0], [0, 0, 0], [0, 0, 0]]),
            ("a late dish wins on score alone", [[0, 1, 2], [0, 1, 2], [1, 0, 2]])
        ]
        for scenario in scenarios {
            var chat = try poll(expected: scenario.ballots.count)
            for (index, ballot) in scenario.ballots.enumerated() {
                chat = try XCTUnwrap(chat.casting(ballot, voter: "voter00\(index)", now: start), scenario.name)
            }
            let expected = try kitchenWinner(ballots: scenario.ballots, dishCount: 3)
            XCTAssertEqual(chat.results().first?.dish.id, expected, scenario.name)
        }
    }

    func testTableHappinessIsTheShareOfTheBestPossibleScore() throws {
        var current = try poll(expected: 2)
        current = try XCTUnwrap(current.casting([2, 1, 0], voter: "voter001", now: start))
        current = try XCTUnwrap(current.casting([2, 0, 0], voter: "voter002", now: start))
        XCTAssertEqual(current.results().map(\.percent), [100, 25, 0])
        XCTAssertEqual(current.leader?.score, 4)
    }

    // MARK: Staying in step with the app

    func testThePollDishMenuMatchesTheRecipeCatalog() {
        XCTAssertEqual(PollDishMenu.all.map(\.id), RecipeCatalog.all.map(\.id))
        for entry in PollDishMenu.all {
            let recipe = RecipeCatalog.all.first { $0.id == entry.id }
            XCTAssertEqual(entry.dish.title, recipe?.title, entry.id)
            XCTAssertEqual(entry.dish.minutes, recipe?.minutes, entry.id)
        }
    }

    func testPollReactionsUseTheSameScoresAsTheAppsReactions() {
        XCTAssertEqual(PollReaction.allCases.map(\.rawValue), Reaction.allCases.map(\.rawValue))
    }

    func testVoterKeysAreShortAndStablePerParticipant() {
        let participant = UUID()
        XCTAssertEqual(ChatPoll.voterKey(for: participant), ChatPoll.voterKey(for: participant))
        XCTAssertEqual(ChatPoll.voterKey(for: participant).count, 8)
        XCTAssertNotEqual(ChatPoll.voterKey(for: UUID()), ChatPoll.voterKey(for: UUID()))
    }
}
