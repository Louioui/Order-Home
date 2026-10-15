import SwiftUI

struct HouseMenuView: View {
    @Environment(OrderHomeStore.self) private var store
    @State private var search = ""
    @State private var category = "All recipes"
    @State private var importingRecipe = false
    @State private var showingHistory = false
    @State private var selectedRecipe: Recipe?
    private let categories = ["All recipes", "Favorites", "Quick & easy", "Comfort food", "Date night"]
    private var filtered: [Recipe] {
        store.recipes.filter { recipe in
            let searchMatch = search.isEmpty || "\(recipe.title) \(recipe.cuisine) \(recipe.category) \(recipe.subtitle)".localizedCaseInsensitiveContains(search)
            let categoryMatch = category == "All recipes" || (category == "Favorites" ? store.favoriteIDs.contains(recipe.id) : recipe.category == category || (category == "Quick & easy" && recipe.minutes > 0 && recipe.minutes <= 30))
            return searchMatch && categoryMatch
        }
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack { BrandMark(); Spacer(); Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath").font(.system(size: 20)).foregroundStyle(OHTheme.green).frame(width: 40, height: 40) }.accessibilityLabel("Past dinners"); Button { importingRecipe = true } label: { Image(systemName: "link.badge.plus").font(.system(size: 20)).foregroundStyle(OHTheme.green).frame(width: 40, height: 40) }.accessibilityLabel("Save a recipe link") }
                VStack(alignment: .leading, spacing: 9) {
                    Eyebrow(text: "THE GOOD-FOOD COLLECTION")
                    Text("Your house.\nYour kind of food.").font(OHTheme.serif(38)).tracking(-1.4).foregroundStyle(OHTheme.ink)
                    Text("Weeknight heroes and soon-to-be favorites.").font(.system(size: 12)).foregroundStyle(OHTheme.muted)
                }
                SearchField(text: $search, placeholder: "Find a dish, cuisine, or craving")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { item in
                            Button { category = item } label: {
                                Text(item).font(.system(size: 12, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 11).background(category == item ? OHTheme.ink : .white, in: Capsule()).foregroundStyle(category == item ? .white : OHTheme.ink)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                HStack { Eyebrow(text: category == "Favorites" ? "SAVED WITH LOVE" : "A LITTLE INSPIRATION"); Spacer(); Text("\(filtered.count) recipes").font(.system(size: 10)).foregroundStyle(OHTheme.muted) }
                if filtered.isEmpty {
                    ContentUnavailableView(category == "Favorites" ? "Your favorites live here" : "Nothing on the menu yet", systemImage: category == "Favorites" ? "heart" : "magnifyingglass", description: Text(category == "Favorites" ? "Tap the heart on a recipe to save it for another night." : "Try a dish name or a cuisine like Korean or Italian."))
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 23) {
                    ForEach(filtered) { recipe in
                        RecipeGridCard(recipe: recipe, isFavorite: store.favoriteIDs.contains(recipe.id), onFavorite: { store.toggleFavorite(recipe.id) }) { selectedRecipe = recipe }
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "leaf").font(.system(size: 20))
                    Text("A small, thoughtfully written cookbook.\nOur house recipes are ready to cook offline.").font(.system(size: 11)).lineSpacing(4)
                }.foregroundStyle(OHTheme.muted).padding(.vertical, 8)
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 28)
        }.sheet(item: $selectedRecipe) { RecipeDetailView(recipe: $0) }
        .sheet(isPresented: $importingRecipe) { RecipeImportView() }
        .sheet(isPresented: $showingHistory) { PastDinnersView() }
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(OHTheme.muted)
            TextField(placeholder, text: $text).font(.system(size: 13)).autocorrectionDisabled()
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(OHTheme.muted) }.accessibilityLabel("Clear search") }
        }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(OHTheme.line, lineWidth: 0.7))
    }
}

struct RecipeGridCard: View {
    let recipe: Recipe
    let isFavorite: Bool
    let onFavorite: () -> Void
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                Button(action: action) { FoodImage(recipe: recipe).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 17)) }.buttonStyle(.plain)
                Button(action: onFavorite) { Image(systemName: isFavorite ? "heart.fill" : "heart").font(.system(size: 13)).foregroundStyle(isFavorite ? OHTheme.accent : OHTheme.ink).frame(width: 31, height: 31).background(.white.opacity(0.95), in: Circle()) }.buttonStyle(.plain).padding(9).accessibilityLabel(isFavorite ? "Unsave \(recipe.title)" : "Save \(recipe.title)")
            }
            Button(action: action) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(OHTheme.ink).multilineTextAlignment(.leading).lineLimit(2).frame(minHeight: 34, alignment: .top)
                    HStack(spacing: 5) { Image(systemName: "clock"); Text(recipe.durationLabel); Text("·"); Text(recipe.cuisine) }.font(.system(size: 10)).foregroundStyle(OHTheme.muted).lineLimit(1)
                }
            }.buttonStyle(.plain)
        }
    }
}

struct MenuBuilderView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var selectedRecipe: Recipe?
    private var filtered: [Recipe] {
        store.recipes.filter { (!favoritesOnly || store.favoriteIDs.contains($0.id)) && (search.isEmpty || "\($0.title) \($0.cuisine) \($0.subtitle)".localizedCaseInsensitiveContains(search)) }
    }
    private var canNominate: Bool { store.session.stage == .pitching }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SheetHeader(title: "Bring a craving.", subtitle: "Good dinner starts with a little inspiration.")
                HStack { TagPill(text: "\(store.pitches.count) of 5 on tonight’s board"); Spacer(); if !canNominate { TagPill(text: "Voting has started", color: OHTheme.accent) } }
                SearchField(text: $search, placeholder: "Pasta? Tacos? Something cozy?")
                HStack(spacing: 8) {
                    ForEach([false, true], id: \.self) { only in
                        Button { favoritesOnly = only } label: { Text(only ? "House favorites" : "All cravings").font(.system(size: 12, weight: .medium)).padding(.horizontal, 17).padding(.vertical, 11).background(favoritesOnly == only ? OHTheme.ink : .white, in: Capsule()).foregroundStyle(favoritesOnly == only ? .white : OHTheme.ink) }.buttonStyle(.plain)
                    }
                }
                if filtered.isEmpty { ContentUnavailableView("No recipes found", systemImage: "magnifyingglass", description: Text("Try another craving or browse all recipes.")) }
                ForEach(filtered) { recipe in
                    HStack(spacing: 13) {
                        Button { selectedRecipe = recipe } label: { FoodImage(recipe: recipe).frame(width: 83, height: 84).clipShape(RoundedRectangle(cornerRadius: 13)) }.buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 7) {
                            Button { selectedRecipe = recipe } label: { Text(recipe.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(OHTheme.ink).multilineTextAlignment(.leading) }.buttonStyle(.plain)
                            Text("\(recipe.durationLabel) · \(recipe.cuisine)").font(.system(size: 11)).foregroundStyle(OHTheme.muted)
                            if store.session.recipeIDs.contains(recipe.id) { Text("ON THE BOARD").font(.system(size: 8, weight: .bold)).tracking(1.4).foregroundStyle(OHTheme.green) }
                        }
                        Spacer(minLength: 0)
                        if canNominate {
                            Button {
                                if store.session.recipeIDs.contains(recipe.id) { store.removePitch(recipe.id) }
                                else { store.nominate(recipe) }
                            } label: { Image(systemName: store.session.recipeIDs.contains(recipe.id) ? "checkmark" : "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(store.session.recipeIDs.contains(recipe.id) ? OHTheme.green : OHTheme.accent).frame(width: 38, height: 38).background(store.session.recipeIDs.contains(recipe.id) ? OHTheme.lightGreen : OHTheme.accent.opacity(0.08), in: Circle()) }.buttonStyle(.plain).disabled(!store.session.recipeIDs.contains(recipe.id) && store.pitches.count >= 5).accessibilityLabel(store.session.recipeIDs.contains(recipe.id) ? "Remove \(recipe.title)" : "Add \(recipe.title)")
                        }
                    }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding(24)
        }
        .background(OHTheme.background)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: canNominate ? "Done · \(store.pitches.count) cravings on the table" : "Back to tonight", systemImage: "arrow.right") { dismiss() }.padding(.horizontal, 24).padding(.vertical, 13).background(OHTheme.background)
        }
        .sheet(item: $selectedRecipe) { RecipeDetailView(recipe: $0) }
    }
}

struct RecipeDetailView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State private var servings = 4
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                ZStack(alignment: .topTrailing) {
                    FoodImage(recipe: recipe).frame(height: 270)
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(OHTheme.ink).frame(width: 36, height: 36).background(.white, in: Circle()) }.padding(20).accessibilityLabel("Close recipe")
                }.clipShape(RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "\(recipe.cuisine) · \(recipe.durationLabel)")
                    Text(recipe.title).font(OHTheme.serif(35)).foregroundStyle(OHTheme.ink)
                    Text(recipe.subtitle).font(.system(size: 14)).foregroundStyle(OHTheme.muted).lineSpacing(5)
                    HStack {
                        TagPill(text: recipe.category)
                        Spacer()
                        Button { store.toggleFavorite(recipe.id) } label: { Label(store.favoriteIDs.contains(recipe.id) ? "Saved" : "Save recipe", systemImage: store.favoriteIDs.contains(recipe.id) ? "heart.fill" : "heart").font(.system(size: 12, weight: .semibold)).foregroundStyle(OHTheme.accent) }
                    }
                    if let lastServed = store.lastServed(recipe.id) {
                        Label("Served \(store.servedCount(of: recipe.id)) \(store.servedCount(of: recipe.id) == 1 ? "time" : "times") · last \(lastServed.formatted(.relative(presentation: .named)))", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 11)).foregroundStyle(OHTheme.muted)
                    }
                }
                HStack {
                    Text(recipe.ingredients.isEmpty ? "The original recipe" : "The ingredients").font(OHTheme.serif(24)).foregroundStyle(OHTheme.ink)
                    Spacer()
                    if !recipe.ingredients.isEmpty { Stepper("\(servings) servings", value: $servings, in: 1...16).font(.system(size: 11)).fixedSize() }
                }
                if let source = recipe.sourceURL {
                    Link(destination: source) { Label("Open the creator’s original recipe", systemImage: "arrow.up.right.square").font(.system(size: 14, weight: .semibold)).foregroundStyle(OHTheme.accent).padding(17).frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 14)) }
                }
                ForEach(recipe.ingredients) { ingredient in
                    HStack {
                        Text(ingredient.name).font(.system(size: 13)).foregroundStyle(OHTheme.ink)
                        Spacer()
                        Text(ingredient.quantity(for: servings, baseServings: recipe.servings)).font(.system(size: 12, weight: .medium)).foregroundStyle(OHTheme.muted)
                    }.padding(.bottom, 9).overlay(alignment: .bottom) { Rectangle().fill(OHTheme.line).frame(height: 0.5) }
                }
                Text("Make something good").font(OHTheme.serif(24)).foregroundStyle(OHTheme.ink)
                ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text(String(format: "%02d", index + 1)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(OHTheme.accent).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(step.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(OHTheme.ink)
                            Text(step.instruction).font(.system(size: 13)).foregroundStyle(OHTheme.muted).lineSpacing(5)
                        }
                    }.padding(.bottom, 10)
                }
                Text(recipe.sourceURL == nil ? "Written for the Order Home cookbook. Adjust seasoning and cooking time to your ingredients and equipment." : "Saved from a creator’s original post. Follow the source recipe for ingredients, quantities, and cooking times.").font(.system(size: 11)).foregroundStyle(OHTheme.muted).lineSpacing(4)
            }.padding(24)
        }.background(OHTheme.background)
            .safeAreaInset(edge: .bottom) {
                if store.session.stage == .pitching {
                    PrimaryButton(title: store.session.recipeIDs.contains(recipe.id) ? "Already on tonight’s board" : "Pitch this for tonight", systemImage: "plus") { store.nominate(recipe); dismiss() }.disabled(store.session.recipeIDs.contains(recipe.id) || store.pitches.count >= 5).padding(.horizontal, 24).padding(.vertical, 12).background(OHTheme.background)
                }
            }.onAppear { servings = max(1, store.dinerCount) }
    }
}
