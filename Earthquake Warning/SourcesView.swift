import SwiftUI

struct SourcesView: View {
    let localize: (String, Locale) -> String
    let locale: Locale
    // Simple model of sources; adjust URLs/text as needed
    private let sources: [(flag: String, country: String, name: String, url: String)] = [
        ("🇰🇷", "Korea", "Korea Meteorological Administration", "https://www.kma.go.kr/"),
        ("🇹🇼", "Taiwan", "Central Weather Administration", "https://www.cwa.gov.tw/")
    ]

    var body: some View {
        List {
            Section {
                ForEach(sources, id: \.country) { src in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(src.flag)
                            .font(.system(size: 28))
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localize(src.country, locale))
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localize(src.name, locale))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let url = URL(string: src.url) {
                                    Link(src.url, destination: url)
                                        .font(.footnote)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text(localize("These links open in your default browser.", locale))
            }
        }
        .navigationTitle(localize("Sources", locale))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SourcesView(localize: { key, locale in key }, locale: .current)
    }
}
