import SwiftUI

/// "How was it?" Each person who ate gives a one-tap verdict. Ratings feed the
/// House Menu (see `HouseFavoritePolicy`) and the Past dinners list. Shown only
/// for the local kitchen: a connected kitchen keeps no dinner history yet.
struct DinnerRatingCard: View {
    @Environment(OrderHomeStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How was it?")
                .font(.system(size: 27, weight: .regular, design: .serif))
                .foregroundStyle(OHTheme.ink)
            Text("A quick word from everyone who ate. Loved dishes join your House Menu.")
                .font(.subheadline).foregroundStyle(OHTheme.muted)
            ForEach(store.dinersAtTable) { member in
                HStack(spacing: 12) {
                    MemberAvatar(member: member, size: 38)
                    Text(member.name)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(OHTheme.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        ForEach(DinnerRating.allCases) { rating in ratingButton(rating, member: member) }
                    }
                }
            }
        }
        .padding(24)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private func ratingButton(_ rating: DinnerRating, member: Member) -> some View {
        let selected = store.rating(for: member.id) == rating
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(duration: 0.3)) { store.rateDinner(rating, memberID: member.id) }
        } label: {
            Text(rating.emoji).font(.system(size: 20))
                .frame(width: 44, height: 44)
                .background(selected ? OHTheme.accent.opacity(0.12) : OHTheme.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? OHTheme.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rating.title), \(member.name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Every dinner that made it to the table, newest first, with a one-tap
/// "cook it again" that pitches the dish for tonight.
struct PastDinnersView: View {
    @Environment(OrderHomeStore.self) private var store
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: "Dinners we’ve shared.", subtitle: "Every meal that made it to the table.")
                if store.isSharedPresentation {
                    ContentUnavailableView("Kept on your iPhone", systemImage: "iphone", description: Text("Your connected kitchen doesn’t keep a dinner history yet. Switch back to your iPhone kitchen to see yours."))
                } else if store.history.isEmpty {
                    ContentUnavailableView("No dinners yet", systemImage: "fork.knife", description: Text("Ring the dinner bell after cooking and your meal will be remembered here."))
                } else {
                    if store.session.stage != .pitching {
                        Text("Start a fresh dinner to pitch one of these again.")
                            .font(.system(size: 12)).foregroundStyle(OHTheme.muted)
                    }
                    if let notice {
                        Text(notice).font(.system(size: 12, weight: .medium)).foregroundStyle(OHTheme.accent)
                    }
                    ForEach(store.history) { record in
                        PastDinnerCard(record: record) { notice = $0 }
                    }
                }
            }.padding(24)
        }.background(OHTheme.background)
    }
}

private struct PastDinnerCard: View {
    @Environment(OrderHomeStore.self) private var store
    let record: DinnerRecord
    let onNotice: (String) -> Void

    private var recipe: Recipe? { store.recipes.first { $0.id == record.recipeID } }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 9) {
                Text(record.recipeTitle).font(OHTheme.serif(21)).foregroundStyle(OHTheme.ink)
                Text("\(record.servedAt.formatted(date: .abbreviated, time: .omitted)) · \(record.dinerNames.count) at the table")
                    .font(.system(size: 11)).foregroundStyle(OHTheme.muted)
                ratingSummary
                if let recipe {
                    Button { pitch(recipe) } label: {
                        Label("Cook it again", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(OHTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.session.stage != .pitching)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var thumbnail: some View {
        if let recipe {
            FoodImage(recipe: recipe).frame(width: 78, height: 84).clipShape(RoundedRectangle(cornerRadius: 13))
        } else {
            Image(systemName: "fork.knife").font(.system(size: 22)).foregroundStyle(OHTheme.muted)
                .frame(width: 78, height: 84).background(OHTheme.background, in: RoundedRectangle(cornerRadius: 13))
        }
    }

    @ViewBuilder private var ratingSummary: some View {
        let ratings = record.allRatings
        if ratings.isEmpty {
            Text("Not rated yet").font(.system(size: 11)).foregroundStyle(OHTheme.muted)
        } else {
            HStack(spacing: 6) {
                ForEach(DinnerRating.allCases) { rating in
                    let count = ratings.filter { $0 == rating }.count
                    if count > 0 { TagPill(text: "\(rating.emoji) \(count)") }
                }
            }
        }
    }

    private func pitch(_ recipe: Recipe) {
        store.nominate(recipe)
        onNotice(store.session.recipeIDs.contains(recipe.id)
            ? "\(recipe.title) is on tonight’s board."
            : store.toast ?? "That one couldn’t be added right now.")
    }
}
