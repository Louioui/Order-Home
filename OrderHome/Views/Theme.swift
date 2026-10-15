import SwiftUI

enum OHTheme {
    static let background = Color(hex: 0xF8F6F0)
    static let ink = Color(hex: 0x263C31)
    static let accent = Color(hex: 0xCD532D)
    static let muted = Color(hex: 0x747C72)
    static let line = Color(hex: 0xE5E5DA)
    static let green = Color(hex: 0x536D4E)
    static let lightGreen = Color(hex: 0xE9EEDF)
    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 16, weight: .semibold))
                if let systemImage { Image(systemName: systemImage).font(.system(size: 14, weight: .semibold)) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(OHTheme.accent, in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
    }
}

struct FoodImage: View {
    let recipe: Recipe
    var body: some View {
        Image(recipe.imageName)
            .resizable()
            .scaledToFill()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            .accessibilityLabel(recipe.title)
    }
}

struct MemberAvatar: View {
    let member: Member
    var size: CGFloat = 40
    var body: some View {
        Text(member.emoji).font(.system(size: size * 0.49))
            .frame(width: size, height: size)
            .background(avatarColor, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .accessibilityLabel(member.name)
    }
    private var avatarColor: Color {
        let colors: [Color] = [Color(hex: 0xE9D9C5), Color(hex: 0xE3E8D6), Color(hex: 0xF3DDCF), Color(hex: 0xDEDFF0)]
        return colors[member.id.utf8.reduce(0) { $0 + Int($1) } % colors.count]
    }
}

struct SectionHeading: View {
    let title: String
    var eyebrow: String? = nil
    var trailing: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if let eyebrow { Text(eyebrow.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.8).foregroundStyle(OHTheme.muted) }
                Text(title).font(OHTheme.serif(25)).foregroundStyle(OHTheme.ink)
            }
            Spacer()
            if let trailing, let action {
                Button(action: action) { HStack(spacing: 4) { Text(trailing); Image(systemName: "arrow.up.right").font(.system(size: 10)) }.font(.system(size: 12, weight: .semibold)).foregroundStyle(OHTheme.accent) }.buttonStyle(.plain).padding(.bottom, 3)
            }
        }
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = OHTheme.muted
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(color) }
}

struct TagPill: View {
    let text: String
    var color: Color = OHTheme.green
    var body: some View { Text(text).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 7).foregroundStyle(color).background(color.opacity(0.09), in: Capsule()) }
}

struct BrandMark: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(OHTheme.accent).frame(width: 31, height: 34)
                Image(systemName: "fork.knife").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
            }
            Text("order home").font(.system(size: 23, weight: .medium, design: .serif)).tracking(-1).foregroundStyle(OHTheme.ink)
        }.accessibilityElement(children: .combine)
    }
}

struct SheetHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(OHTheme.serif(31)).foregroundStyle(OHTheme.ink)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(OHTheme.muted)
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(OHTheme.ink).frame(width: 36, height: 36).background(.white, in: Circle()) }.accessibilityLabel("Close")
        }.padding(.bottom, 12)
    }
}
