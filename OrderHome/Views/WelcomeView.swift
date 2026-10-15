import SwiftUI

struct WelcomeView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(CloudKitchenController.self) private var cloud
    @State private var setup = false
    @State private var sharedKitchen = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 25) {
                HStack { BrandMark(); Spacer(); Text("A GOOD EVENING STARTS HERE").font(.system(size: 7, weight: .bold)).tracking(1).foregroundStyle(OHTheme.muted) }.padding(.top, 12)
                ZStack(alignment: .bottomLeading) {
                    if let recipe = store.recipes.first { FoodImage(recipe: recipe) }
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) { Image(systemName: "heart.fill"); Text("HOMEMADE. TOGETHER.").tracking(1.7) }.font(.system(size: 9, weight: .semibold))
                        Text("The best table\nis your table.").font(OHTheme.serif(37)).tracking(-1)
                    }.foregroundStyle(.white).padding(24)
                }.frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 27))
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "LESS DECIDING. MORE DINING.")
                    Text("Come home\nto something good.").font(OHTheme.serif(38)).tracking(-1.5).foregroundStyle(OHTheme.ink)
                    Text("Bring your cravings. Pick dinner together.\nMake a little room for the everyday moments.").font(.system(size: 13)).foregroundStyle(OHTheme.muted).lineSpacing(5)
                }
                VStack(spacing: 14) {
                    if cloud.isConfigured {
                        PrimaryButton(title: cloud.identity == nil ? "Bring your people together" : "Open my shared kitchen", systemImage: "person.2") { sharedKitchen = true }
                            .accessibilityIdentifier("openSharedKitchenSetup")
                        Button { setup = true } label: {
                            Label("Start a kitchen on this iPhone", systemImage: "iphone")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(OHTheme.ink).padding(.vertical, 6)
                        }.accessibilityIdentifier("openLocalKitchenSetup")
                    } else {
                        PrimaryButton(title: "Make yourself at home", systemImage: "arrow.right") { setup = true }
                    }
                    Button { withAnimation { store.loadSampleHousehold() } } label: { Text("Take a look around a sample kitchen").font(.system(size: 12, weight: .medium)).foregroundStyle(OHTheme.ink).padding(.vertical, 9) }.accessibilityIdentifier("exploreSampleKitchen")
                }
                HStack { Spacer(); Text("GOOD FOOD. YOUR PEOPLE. ONE LITTLE APP.").font(.system(size: 8, weight: .medium)).tracking(1.4).foregroundStyle(OHTheme.muted); Spacer() }
            }.padding(.horizontal, 25).padding(.bottom, 20)
        }.background(OHTheme.background)
        .sheet(isPresented: $setup) { KitchenSetupView() }
        .sheet(isPresented: $sharedKitchen) { SharedKitchenView() }
    }
}

struct KitchenSetupView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kitchenName = ""
    @State private var mode: HouseholdMode = .family
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SheetHeader(title: "Every home has a kitchen.", subtitle: "Let’s make this one yours.")
                VStack(alignment: .leading, spacing: 10) { Eyebrow(text: "YOUR NAME"); TextField("e.g. Alex", text: $name).textContentType(.givenName).padding(17).background(.white, in: RoundedRectangle(cornerRadius: 14)) }
                VStack(alignment: .leading, spacing: 10) { Eyebrow(text: "NAME YOUR KITCHEN"); TextField("e.g. The Sunday Kitchen", text: $kitchenName).padding(17).background(.white, in: RoundedRectangle(cornerRadius: 14)) }
                Eyebrow(text: "WHO’S AROUND YOUR TABLE?")
                ForEach(HouseholdMode.allCases) { choice in
                    Button { mode = choice } label: {
                        HStack(spacing: 15) {
                            Image(systemName: choice == .family ? "person.3" : "heart").font(.system(size: 23)).frame(width: 34)
                            VStack(alignment: .leading, spacing: 7) { Text(choice.title).font(.system(size: 16, weight: .semibold)); Text(choice.subtitle).font(.system(size: 12)) }
                            Spacer(); Image(systemName: choice == mode ? "checkmark.circle.fill" : "circle")
                        }.foregroundStyle(choice == mode ? .white : OHTheme.ink).padding(21).background(choice == mode ? OHTheme.ink : .white, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain)
                }
                PrimaryButton(title: "Open my kitchen", systemImage: "arrow.right") {
                    dismiss()
                    withAnimation { store.completeOnboarding(name: kitchenName, personName: name, mode: mode) }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Start with yourself. Add the rest of your people in Your table, and pass the phone to collect their cravings.").font(.system(size: 12)).foregroundStyle(OHTheme.muted).lineSpacing(5)
            }.padding(24)
        }.background(OHTheme.background)
    }
}
