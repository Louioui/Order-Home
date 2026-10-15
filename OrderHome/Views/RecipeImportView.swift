import SwiftUI

struct RecipeImportView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var link = ""
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SheetHeader(title: "Saw something delicious?", subtitle: "Give that saved recipe a home.")
                Image(systemName: "link").font(.system(size: 34)).foregroundStyle(OHTheme.green).frame(maxWidth: .infinity).padding(.vertical, 15)
                VStack(alignment: .leading, spacing: 10) { Eyebrow(text: "GIVE IT A NAME"); TextField("e.g. Jamie’s crispy chili noodles", text: $title).font(.system(size: 14)).padding(17).background(.white, in: RoundedRectangle(cornerRadius: 14)) }
                VStack(alignment: .leading, spacing: 10) { Eyebrow(text: "PASTE THE RECIPE LINK"); TextField("https://…", text: $link).font(.system(size: 14)).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().padding(17).background(.white, in: RoundedRectangle(cornerRadius: 14)) }
                Text("YouTube · TikTok · Instagram").font(.system(size: 11, weight: .medium)).foregroundStyle(OHTheme.muted)
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "arrow.up.right.square").foregroundStyle(OHTheme.green)
                    Text("We’ll save a link to the creator’s recipe. Ingredients, portions, and the video stay in the original post, so you can follow along there.").font(.system(size: 12)).foregroundStyle(OHTheme.muted).lineSpacing(5)
                }.padding(19).background(OHTheme.lightGreen, in: RoundedRectangle(cornerRadius: 17))
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(OHTheme.accent) }
                PrimaryButton(title: "Save to my house menu", systemImage: "bookmark") {
                    guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), store.addRecipe(title: title, url: url) else { error = "Use a secure YouTube, TikTok, or Instagram link and add a recipe name."; return }
                    dismiss()
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || link.isEmpty)
            }.padding(24)
        }.background(OHTheme.background)
    }
}

extension Recipe {
    var durationLabel: String { minutes > 0 ? "\(minutes) min" : "Original recipe" }
}
