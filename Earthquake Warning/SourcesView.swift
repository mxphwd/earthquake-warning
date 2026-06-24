import SwiftUI

struct SourcesView: View {
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
                            Text(src.country)
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(src.name)
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
                Text("These links open in your default browser.")
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SourcesView() }
}
