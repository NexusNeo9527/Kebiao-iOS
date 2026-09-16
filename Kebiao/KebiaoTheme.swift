import SwiftUI

enum KebiaoTheme {
    static let background = Color(red: 0.965, green: 0.962, blue: 0.974)
    static let card = Color.white
    static let accent = Color(hex: 0xFF3E63)
    static let secondaryText = Color(red: 0.55, green: 0.55, blue: 0.58)
    static let cardRadius: CGFloat = 22
}

struct KebiaoCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KebiaoTheme.card, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius, style: .continuous))
    }
}
