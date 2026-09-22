import SwiftUI

/// The same original book mark used by the Home Screen icon, with vector scaling.
struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        Image("BrandMark").resizable().scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct BrandIdentity: View {
    var markSize: CGFloat = 44
    var body: some View {
        HStack(spacing: 14) {
            BrandMark(size: markSize)
            VStack(alignment: .leading, spacing: 3) {
                Text("Vault Reader").font(.title3.weight(.semibold))
                Text("你的随身知识库").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
