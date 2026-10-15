import Foundation

/// How someone feels about one dish. The raw values are the same scores the
/// app's `Reaction` uses (pass 0, down 1, love 2), so a chat poll and a kitchen
/// vote rank dishes identically.
enum PollReaction: Int, CaseIterable, Identifiable {
    case pass = 0
    case down = 1
    case love = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .pass: "Pass"
        case .down: "I’m down"
        case .love: "Craving it"
        }
    }
    var emoji: String {
        switch self {
        case .pass: "✋"
        case .down: "👌"
        case .love: "🔥"
        }
    }
}

/// A dinner poll that lives entirely inside an iMessage conversation.
///
/// There is no server: the whole poll, including every ballot, is encoded into
/// the message's URL. Each vote sends back an updated copy of the same message
/// and Messages replaces the bubble in place. Nothing here touches UIKit or the
/// Messages framework, so the rules can be tested and the same file compiles
/// into both the app and the Messages extension.
///
/// Limitation by design: if two people vote from the same bubble at the same
/// moment, the last message to arrive wins and the other ballot can be lost.
struct ChatPoll: Equatable {
    static let currentVersion = 1
    static let dishCount = 2...5
    static let maxBallots = 24

    struct Dish: Equatable, Identifiable {
        var id: String
        var title: String
        var minutes: Int
    }

    /// The dish's title and time travel inside the message, so a poll reads
    /// correctly without the recipe catalog.
    var id: String
    var dishes: [Dish]
    var deadline: Date
    var closedEarly = false
    /// Participant key of whoever started the poll. Only they can close it early.
    var creator: String
    /// People in the conversation when the poll started, including the creator.
    var expectedVoters: Int
    /// Participant key to one score per dish, in `dishes` order (0, 1 or 2).
    var ballots: [String: [Int]] = [:]

    /// A short stable key for one conversation participant. Messages hands out a
    /// per-conversation UUID, never a name, and a full UUID would bloat the URL.
    static func voterKey(for participant: UUID) -> String {
        String(participant.uuidString.lowercased().prefix(8))
    }

    static func new(dishes: [Dish], deadline: Date, creator: String, expectedVoters: Int) -> ChatPoll? {
        guard dishCount.contains(dishes.count), !creator.isEmpty,
              Set(dishes.map(\.id)).count == dishes.count else { return nil }
        return ChatPoll(
            id: String(UUID().uuidString.lowercased().prefix(8)), dishes: dishes, deadline: deadline,
            creator: creator, expectedVoters: max(1, min(expectedVoters, maxBallots))
        )
    }

    // MARK: When is it decided?

    enum Decision: Equatable {
        case closedByCreator
        case deadlinePassed
        case everyoneVoted
    }

    /// Why the poll is over, or `nil` while it is still open. Voting stops as
    /// soon as this returns a value.
    func decision(now: Date) -> Decision? {
        // TODO: This rule is yours to tune. Today the poll ends as soon as ANY of
        // these happens, which keeps dinner moving:
        //   - the person who started it closes it,
        //   - the deadline passes, or
        //   - everyone who was in the chat has voted.
        // Reasonable alternatives: ignore `everyoneVoted` so a family can keep
        // changing their minds until the deadline, or require the creator to
        // close it so nobody is locked out by a quick early majority.
        if closedEarly { return .closedByCreator }
        if now >= deadline { return .deadlinePassed }
        if expectedVoters > 0, ballots.count >= expectedVoters { return .everyoneVoted }
        return nil
    }

    func isOpen(now: Date) -> Bool { decision(now: now) == nil }

    // MARK: Voting

    /// Records or replaces one person's ballot. Returns `nil` when the poll is
    /// over or the ballot does not cover every dish with a valid score.
    func casting(_ ballot: [Int], voter: String, now: Date) -> ChatPoll? {
        guard isOpen(now: now), !voter.isEmpty,
              ballot.count == dishes.count, ballot.allSatisfy({ (0...2).contains($0) }),
              ballots[voter] != nil || ballots.count < Self.maxBallots else { return nil }
        var updated = self
        updated.ballots[voter] = ballot
        return updated
    }

    func closing() -> ChatPoll {
        var updated = self
        updated.closedEarly = true
        return updated
    }

    // MARK: Results

    struct Result: Equatable, Identifiable {
        var dish: Dish
        var score: Int
        var passes: Int
        /// Table happiness: the score as a share of the best possible score.
        var percent: Int
        var id: String { dish.id }
    }

    /// Dishes from best to worst by the same rule the app uses: higher score,
    /// then fewer passes, then the order they were pitched.
    func results() -> [Result] {
        let voters = ballots.count
        let ranked = dishes.enumerated().map { index, dish -> (index: Int, result: Result) in
            let scores = ballots.values.map { $0[index] }
            let score = scores.reduce(0, +)
            let percent = voters == 0 ? 0 : Int((Double(score) / Double(voters * 2) * 100).rounded())
            return (index, Result(dish: dish, score: score, passes: scores.filter { $0 == 0 }.count, percent: percent))
        }
        return ranked.sorted { left, right in
            if left.result.score != right.result.score { return left.result.score > right.result.score }
            if left.result.passes != right.result.passes { return left.result.passes < right.result.passes }
            return left.index < right.index
        }.map(\.result)
    }

    /// The front-runner, or `nil` until someone has voted.
    var leader: Result? { ballots.isEmpty ? nil : results().first }

    /// "3 of 4 voted", or "3 voted" if more people voted than were counted at the start.
    var progressText: String {
        ballots.count <= expectedVoters ? "\(ballots.count) of \(expectedVoters) voted" : "\(ballots.count) voted"
    }
}

// MARK: - Message URL

extension ChatPoll {
    enum Decoded: Equatable {
        case poll(ChatPoll)
        /// Made by a newer version of the app. Show "update to see this poll".
        case newerVersion
        case invalid
    }

    private static let host = "poll"
    private static let maxPayloadLength = 8_000

    /// `orderhome://poll?p=…` carrying the whole poll. The custom scheme keeps
    /// the message openable by the app later without any server.
    var url: URL {
        var components = URLComponents()
        components.scheme = "orderhome"
        components.host = Self.host
        components.queryItems = [URLQueryItem(name: "p", value: Self.base64URL(from: wireData))]
        return components.url ?? URL(string: "orderhome://\(Self.host)")!
    }

    /// Decodes leniently: anything unexpected is `.invalid`, never a crash, and
    /// individual damaged ballots are dropped rather than failing the whole poll.
    static func decode(_ url: URL) -> Decoded {
        guard url.scheme?.lowercased() == "orderhome", url.host?.lowercased() == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let payload = items.first(where: { $0.name == "p" })?.value,
              payload.count <= maxPayloadLength,
              let data = data(fromBase64URL: payload) else { return .invalid }
        let decoder = JSONDecoder()
        guard let version = (try? decoder.decode(WireVersion.self, from: data))?.v else { return .invalid }
        if version > currentVersion { return .newerVersion }
        guard version >= 1, let wire = try? decoder.decode(Wire.self, from: data),
              let poll = ChatPoll(validating: wire) else { return .invalid }
        return .poll(poll)
    }

    // MARK: Wire format

    private struct WireVersion: Decodable { var v: Int }

    private struct WireDish: Codable {
        var i: String
        var t: String
        var m: Int
    }

    /// Short keys keep the URL small: v version, i id, d dishes, e deadline,
    /// c closed, o creator, x expected voters, b ballots ("2102" = one digit per dish).
    private struct Wire: Codable {
        var v: Int
        var i: String
        var d: [WireDish]
        var e: Int
        var c: Int?
        var o: String
        var x: Int
        var b: [String: String]
    }

    private var wireData: Data {
        let wire = Wire(
            v: Self.currentVersion, i: id,
            d: dishes.map { WireDish(i: $0.id, t: $0.title, m: $0.minutes) },
            e: Int(deadline.timeIntervalSince1970), c: closedEarly ? 1 : nil, o: creator, x: expectedVoters,
            b: ballots.mapValues { $0.map(String.init).joined() }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(wire)) ?? Data()
    }

    private init?(validating wire: Wire) {
        let dishes = wire.d.map { Dish(id: $0.i, title: String($0.t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)), minutes: min(max($0.m, 0), 600)) }
        guard Self.dishCount.contains(dishes.count), !wire.i.isEmpty, wire.i.count <= 32,
              !wire.o.isEmpty, wire.o.count <= 16,
              dishes.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 40 && !$0.title.isEmpty }),
              Set(dishes.map(\.id)).count == dishes.count else { return nil }
        var ballots: [String: [Int]] = [:]
        for key in wire.b.keys.sorted() where ballots.count < Self.maxBallots {
            guard !key.isEmpty, key.count <= 16, let digits = wire.b[key], digits.count == dishes.count else { continue }
            let scores = digits.compactMap { $0.wholeNumberValue }
            guard scores.count == dishes.count, scores.allSatisfy({ (0...2).contains($0) }) else { continue }
            ballots[key] = scores
        }
        self.init(
            id: wire.i, dishes: dishes, deadline: Date(timeIntervalSince1970: TimeInterval(wire.e)),
            closedEarly: wire.c == 1, creator: wire.o, expectedVoters: min(max(wire.x, 1), Self.maxBallots),
            ballots: ballots
        )
    }

    private static func base64URL(from data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(fromBase64URL text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
