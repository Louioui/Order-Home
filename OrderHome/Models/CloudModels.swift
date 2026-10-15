import Foundation

struct CloudIdentity: Equatable {
    var id: String
    var email: String?
    var displayName: String?
}

struct CloudHousehold: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var mode: HouseholdMode
    var ownerUserID: String

    enum CodingKeys: String, CodingKey {
        case id, name, mode
        case ownerUserID = "owner_user_id"
    }
}

struct CloudMember: Codable, Identifiable, Equatable {
    var id: String
    var userID: String
    var displayName: String
    var avatarEmoji: String
    var defaultRole: String
    var dietaryTags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case displayName = "display_name"
        case avatarEmoji = "avatar_emoji"
        case defaultRole = "default_role"
        case dietaryTags = "dietary_tags"
    }
}

struct CloudDinner: Codable, Identifiable, Equatable {
    var id: String
    var householdID: String
    var headChefID: String
    var status: String
    var votingDeadline: Date
    var winningPitchID: String?
    var missingGroceries: [String]
    var cookingStepIndex: Int

    enum CodingKeys: String, CodingKey {
        case id, status
        case householdID = "household_id"
        case headChefID = "head_chef_id"
        case votingDeadline = "voting_deadline"
        case winningPitchID = "winning_pitch_id"
        case missingGroceries = "missing_groceries"
        case cookingStepIndex = "cooking_step_index"
    }
}

struct CloudPitch: Codable, Identifiable, Equatable {
    var id: String
    var recipeID: String
    var pitchedByMemberID: String

    enum CodingKeys: String, CodingKey {
        case id
        case recipeID = "recipe_id"
        case pitchedByMemberID = "pitched_by_member_id"
    }
}

struct CloudVote: Codable, Equatable {
    var pitchID: String
    var memberID: String
    var voteWeight: Int

    enum CodingKeys: String, CodingKey {
        case pitchID = "pitch_id"
        case memberID = "member_id"
        case voteWeight = "vote_weight"
    }
}

struct CloudOrder: Codable, Equatable {
    var memberID: String
    var isEatingHome: Bool
    var modifierTags: [String]
    var dinerNote: String
    var submittedAt: Date?

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case isEatingHome = "is_eating_home"
        case modifierTags = "modifier_tags"
        case dinerNote = "diner_note"
        case submittedAt = "submitted_at"
    }
}

struct CloudKitchenSnapshot: Codable, Equatable {
    var household: CloudHousehold
    var members: [CloudMember]
    var session: CloudDinner?
    var pitches: [CloudPitch]
    var votes: [CloudVote]
    var orders: [CloudOrder]
}

struct CloudInvitation: Codable, Equatable {
    var token: String
    var expiresAt: Date
    var householdName: String

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case householdName = "household_name"
    }
}

struct CloudReaction: Codable, Equatable {
    var pitchID: String
    var weight: Int

    enum CodingKeys: String, CodingKey {
        case pitchID = "pitch_id"
        case weight
    }
}

enum CloudCommand {
    case openDinner(householdID: String, deadline: Date)
    case nominate(sessionID: String, recipeID: String)
    case removePitch(sessionID: String, recipeID: String)
    case startVoting(sessionID: String)
    case submitOrder(sessionID: String, reactions: [CloudReaction], attending: Bool, note: String)
    case closeVoting(sessionID: String)
    case advanceKitchen(sessionID: String, status: String, stepIndex: Int, missingGroceries: [String])
    case updateProfile(householdID: String, name: String, emoji: String, dietaryTags: [String])
    case setMode(householdID: String, mode: HouseholdMode)
    case expireVoting(sessionID: String)
    case extendVoting(sessionID: String, deadline: Date)
    case savePreferences(sessionID: String, attending: Bool, note: String)
    case cancelDinner(sessionID: String)
}

/// The controller only depends on this interface, so connected behavior can be
/// verified without creating accounts or placing credentials in tests.
@MainActor
protocol KitchenCloudService: AnyObject {
    var isConfigured: Bool { get }
    func restoreSession() async throws -> CloudIdentity?
    func signInWithApple(idToken: String, nonce: String, displayName: String?) async throws -> CloudIdentity
    func requestEmailCode(email: String) async throws
    func verifyEmailCode(email: String, code: String) async throws -> CloudIdentity
    func signOut() async throws
    func listKitchens() async throws -> [CloudHousehold]
    func snapshot(householdID: String) async throws -> CloudKitchenSnapshot
    func createKitchen(name: String, mode: HouseholdMode, displayName: String) async throws -> String
    func createInvite(householdID: String) async throws -> CloudInvitation
    func joinKitchen(token: String, displayName: String) async throws -> String
    func perform(_ command: CloudCommand) async throws
    func changes(householdID: String) -> AsyncStream<Void>
}

enum CloudJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            if let date = fractional.date(from: value) ?? plain.date(from: value) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid server date"))
        }
        return decoder
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
