import Foundation

/// Decides when a dinner's ratings are strong enough to save it to the House Menu.
///
/// `OrderHomeStore.rateDinner` asks this after every rating change and adds the
/// dish to the favorites only when the answer flips from `false` to `true`. So a
/// rating can add a favorite but never removes one, and a dish someone has
/// deliberately un-hearted is not re-added by a later rating that leaves the
/// answer at `true`.
enum HouseFavoritePolicy {
    /// - Parameters:
    ///   - ratings: Every rating given for tonight's dinner so far. People who
    ///     have not rated yet are simply absent, so this can be shorter than
    ///     `dinerCount`.
    ///   - dinerCount: How many people ate at the table tonight.
    /// - Returns: `true` when the dish should be saved to the House Menu.
    static func shouldSave(ratings: [DinnerRating], dinerCount: Int) -> Bool {
        // TODO: This is your call, and it shapes how the cookbook grows.
        //
        // Today one 😍 from anyone saves the dish, which matches the
        // architecture doc ("😍 Add to House Menu"). Other reasonable rules:
        //   - Majority: loved by more than half of `dinerCount`, so a picky
        //     diner can't fill the cookbook alone. Couples (2 people) then
        //     need both partners, which fits "Table for Two" matching.
        //   - Veto: any 🔄 keeps it out until the recipe is tweaked.
        //   - Quiet crowd: require everyone to have rated first, so the verdict
        //     can't flip while the phone is still being passed around.
        ratings.contains(.loved)
    }
}
