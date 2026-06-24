//
//  ContentView.swift
//  Earthquake Warning
//
//  Created by Sebastian Raynham on 2025-11-26.
//

import Foundation
import SwiftUI
import UserNotifications
internal import Combine
import Network

// Simple model for earthquake/tsunami warnings
struct EarthquakeWarning: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let description: String
    let receivedAt: Date
    
    static func == (lhs: EarthquakeWarning, rhs: EarthquakeWarning) -> Bool {
        lhs.id == rhs.id
    }
}

enum AppearanceSelection: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    var id: String { rawValue }
}

let regions = ["대한민국 (한국어)", "臺灣 (繁體中文)"]

func localeForRegion(_ region: String) -> Locale {
    switch region {
    case "대한민국 (한국어)": return Locale(identifier: "ko")
    case "臺灣 (繁體中文)": return Locale(identifier: "zh-Hant")
    default: return Locale.current
    }
}

/// Returns a coarse region code used for filtering based on the region display string
func regionCode(for region: String) -> String {
    switch region {
    case "대한민국 (한국어)": return "KR"
    case "臺灣 (繁體中文)": return "TW"
    default: return ""
    }
}

/// Filters warnings to only those that appear to affect the given region.
/// This uses simple heuristics on the title/description until the backend provides explicit region fields.
func filterWarnings(_ warnings: [EarthquakeWarning], for region: String) -> [EarthquakeWarning] {
    let code = regionCode(for: region)
    // Only keep warnings from the last 7 days
    let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
    let recentWarnings = warnings.filter { $0.receivedAt >= sevenDaysAgo }
    // Keywords per region (can be expanded). Includes English and local language variants.
    let keywordsByCode: [String: [String]] = [
        "KR": ["Korea", "South Korea", "대한민국", "한국", "KR"],
        "TW": ["Taiwan", "臺灣", "台灣", "TW"]
    ]
    guard let keywords = keywordsByCode[code], !keywords.isEmpty else {
        return recentWarnings
    }
    func matches(_ text: String) -> Bool {
        let lower = text.lowercased()
        return keywords.contains { kw in lower.contains(kw.lowercased()) }
    }
    return recentWarnings.filter { w in
        // If either the title or description contains a region keyword, keep it
        if matches(w.title) || matches(w.description) { return true }
        // Heuristic: If the app locale language matches typical language used in the warning, keep it
        // (Useful when providers localize content but omit explicit place names.)
        let regionLocale = localeForRegion(region).identifier
        switch regionLocale {
        case "ko": return w.description.contains("지진") || w.title.contains("지진")
        case "zh-Hant": return w.description.contains("地震") || w.title.contains("地震")
        default: return false
        }
    }
}

struct ContentView: View {
    @AppStorage("selectedRegion") private var selectedRegion: String = regions.first ?? "대한민국"
    @State private var appLocale: Locale = localeForRegion(regions.first!)
    @State private var warnings: [EarthquakeWarning] = []
    @State private var isLoading = false
    @State private var showingNotificationAlert = false
    @State private var showingOptions: Bool = false
    @State private var isRefreshHintExpanded: Bool = false
    @State private var lastInteraction: Date = Date()
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("timeSensitiveEnabled") private var timeSensitiveEnabled: Bool = false
    
    @AppStorage("appearanceSelection") private var appearanceSelectionRaw: String = AppearanceSelection.system.rawValue
    private var appearanceSelection: AppearanceSelection {
        get { AppearanceSelection(rawValue: appearanceSelectionRaw) ?? .system }
        set { appearanceSelectionRaw = newValue.rawValue }
    }
    
    @State private var isNetworkAvailable: Bool = true
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Liquid Glass container (modern effect)
                LiquidGlass()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(localizedString("App Title", locale: appLocale))
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .frame(height: geo.size.height * 0.3)
                            // Notification area block
                            VStack(alignment: .leading, spacing: 12) {
                                // Header for clarity
                                HStack(spacing: 8) {
                                    Image(systemName: "waveform.path.ecg")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.red)
                                    Text(localizedString("Recent Warnings", locale: appLocale))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.bottom, 4)

                                Divider()
                                    .opacity(0.25)

                                if let latest = warnings.first {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text(latest.title)
                                                .font(.title2).bold()
                                            if let magBadge = magnitudeBadge(from: latest.description) {
                                                Text(magBadge)
                                                    .font(.caption)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.orange.opacity(0.15))
                                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                            }
                                        }
                                        Text(latest.description)
                                            .font(.body)
                                        Text(formattedDate(latest.receivedAt))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    VStack(alignment: .center, spacing: 10) {
                                        Spacer()
                                        Text(localizedString("No warnings.", locale: appLocale))
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity)
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .padding(16)
                            .background(
                                LinearGradient(colors: [Color(.systemBackground).opacity(0.9), Color(.secondarySystemBackground).opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .overlay(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                            .frame(height: geo.size.height * 0.7 - 24)
                        }
                        .frame(height: geo.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            lastInteraction = Date()
                            withAnimation { isRefreshHintExpanded = false }
                        }
                    }
                    
                    HStack(spacing: 12) {
                        // Settings button
                        Button(action: {
                            lastInteraction = Date()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0)) {
                                showingOptions = true
                                isRefreshHintExpanded = false
                            }
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 22, weight: .medium))
                                .frame(width: 48, height: 48)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 3)
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Refresh pill/button
                        Button(action: {
                            lastInteraction = Date()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isRefreshHintExpanded = false
                            }
                            if isNetworkAvailable {
                                Task { await fetchWarnings() }
                            } else {
                                showingNotificationAlert = true
                            }
                        }) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Image(systemName: isNetworkAvailable ? "arrow.clockwise" : "exclamationmark.triangle.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                        .opacity(isLoading ? 0 : 1)
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                    }
                                }
                                .frame(width: 48, height: 48)
                                .contentShape(Circle())
                                // Slide the icon left so its circular area sits flush with the pill's left edge when expanded
                                .padding(.leading, isRefreshHintExpanded ? -12 : 0)

                                if isRefreshHintExpanded {
                                    Text(localizedString("Refresh", locale: appLocale))
                                        .font(.system(size: 16, weight: .semibold))
                                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                                }
                            }
                            // Add internal padding; when expanded, add extra leading padding so the left edge hugs the icon's circle
                            .padding(.leading, isRefreshHintExpanded ? 12 : 0)
                            .padding(.trailing, isRefreshHintExpanded ? 14 : 0)
                            .frame(height: 48)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .shadow(color: Color.accentColor.opacity(0.09), radius: 5, x: 0, y: 3)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isRefreshHintExpanded)
                        }
                        .accessibilityLabel(localizedString("Refresh", locale: appLocale))
                    }
                    .padding(.bottom, 20)
                    .onAppear { lastInteraction = Date() }
                    .onChange(of: warnings) { oldValue, newValue in lastInteraction = Date(); withAnimation { isRefreshHintExpanded = false } }
                    .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
                        // Expand after 5 seconds of inactivity and not loading
                        let idle = Date().timeIntervalSince(lastInteraction)
                        if idle >= 5.0 && !isLoading {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                isRefreshHintExpanded = true
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingOptions) {
                    NavigationStack {
                        List {
                            Section(header: Text(localizedString("Appearance", locale: appLocale))) {
                                Picker(localizedString("Theme", locale: appLocale), selection: $appearanceSelectionRaw) {
                                    Text(localizedString("System", locale: appLocale)).tag(AppearanceSelection.system.rawValue)
                                    Text(localizedString("Light", locale: appLocale)).tag(AppearanceSelection.light.rawValue)
                                    Text(localizedString("Dark", locale: appLocale)).tag(AppearanceSelection.dark.rawValue)
                                }
                                .pickerStyle(.segmented)
                            }
                            Section(header: Text(localizedString("Notifications", locale: appLocale))) {
                                Toggle(isOn: $notificationsEnabled) {
                                    Label(localizedString("Notifications", locale: appLocale), systemImage: "bell")
                                }
                                .onChange(of: notificationsEnabled) { oldValue, newValue in
                                    if newValue {
                                        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
                                        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, _ in
                                            DispatchQueue.main.async {
                                                notificationsEnabled = granted
                                            }
                                        }
                                    } else {
                                        notificationsEnabled = false
                                    }
                                }

                                Toggle(isOn: $timeSensitiveEnabled) {
                                    Label(localizedString("Time Sensitive", locale: appLocale), systemImage: "exclamationmark.triangle.fill")
                                }
                                .onChange(of: timeSensitiveEnabled) {
                                    guard notificationsEnabled else { return }
                                    let options: UNAuthorizationOptions = [.alert, .sound, .badge]
                                    UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, _ in
                                        DispatchQueue.main.async {
                                            notificationsEnabled = granted
                                        }
                                    }
                                }

                                Text(localizedString("Control whether alerts from this app are delivered. Time Sensitive requires the entitlement and raises the notification's interruption level to break through Focus modes.", locale: appLocale))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Section(header: Text(localizedString("Region & Language", locale: appLocale))) {
                                HStack {
                                    Label(localizedString("Region & Language", locale: appLocale), systemImage: "globe")
                                    Spacer()
                                    Picker("", selection: $selectedRegion) {
                                        ForEach(regions, id: \.self) { region in
                                            Text(region).tag(region)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                                .onChange(of: selectedRegion) { oldValue, newValue in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        appLocale = localeForRegion(newValue)
                                    }
                                    Task { await fetchWarnings() }
                                }

                                NavigationLink(destination: SourcesView(localize: localizedString, locale: appLocale)) {
                                    Label(localizedString("Sources", locale: appLocale), systemImage: "book.pages")
                                }
                            }
                        }
                        .navigationTitle(localizedString("Settings", locale: appLocale))
                        .navigationBarTitleDisplayMode(.inline)
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
        .environment(\.locale, appLocale)
        .preferredColorScheme({
            switch appearanceSelection {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }())
        .task {
            requestNotificationPermission()
            await fetchWarnings()
            networkMonitor.pathUpdateHandler = { path in
                DispatchQueue.main.async {
                    self.isNetworkAvailable = (path.status == .satisfied)
                }
            }
            networkMonitor.start(queue: networkQueue)
        }
        .alert(localizedString("New Warning!", locale: appLocale), isPresented: $showingNotificationAlert) {
            Button(localizedString("OK", locale: appLocale)) {}
        } message: {
            Text(isNetworkAvailable ? localizedString("A new earthquake/tsunami warning was received.", locale: appLocale) : localizedString("You are not connected to the internet.", locale: appLocale))
        }
        .onDisappear { networkMonitor.cancel() }
    }
    
    func localizedString(_ key: String, locale: Locale) -> String {
        // Simple localized strings for demo purposes
        // In a real app, use Localizable.strings files per language
        let languageCode = locale.identifier
        
        switch key {
        case "App Title":
            switch languageCode {
            case "ko": return "지진"
            case "zh-Hant": return "地震"
            default: return "Earthquake"
            }
        case "Recent Warnings":
            switch languageCode {
            case "ko": return "최근 수신된 경보"
            case "zh-Hant": return "最近收到的警報"
            default: return "Recent warnings"
            }
        case "Fetching warnings...":
            switch languageCode {
            case "ko": return "경고를 가져오는 중..."
            case "zh-Hant": return "正在取得警告..."
            default: return "Fetching warnings..."
            }
        case "No warnings.":
            switch languageCode {
            case "ko": return "경보 없음"
            case "zh-Hant": return "無警告"
            default: return "No warnings."
            }
        case "New Warning!":
            switch languageCode {
            case "ko": return "새로운 알림이 수신되었습니다"
            case "zh-Hant": return "新警報！"
            default: return "New Warning!"
            }
        case "OK":
            switch languageCode {
            case "ko": return "확인"
            case "zh-Hant": return "確定"
            default: return "OK"
            }
        case "A new earthquake/tsunami warning was received.":
            switch languageCode {
            case "ko": return "새로운 지진/쓰나미 경고가 수신되었습니다."
            case "zh-Hant": return "收到新的地震/海嘯警報。"
            default: return "A new earthquake/tsunami warning was received."
            }
        case "EARTHQUAKE":
            switch languageCode {
            case "ko": return "지진"
            case "zh-Hant": return "地震"
            default: return "EARTHQUAKE"
            }
        case "Magnitude":
            switch languageCode {
            case "ko": return "규모"
            case "zh-Hant": return "規模"
            default: return "Magnitude"
            }
        case "Settings":
            switch languageCode {
            case "ko": return "설정"
            case "zh-Hant": return "設定"
            default: return "Settings"
            }
        case "Notifications":
            switch languageCode {
            case "ko": return "알림"
            case "zh-Hant": return "通知"
            default: return "Notifications"
            }
        case "Refresh":
            switch languageCode {
            case "ko": return "새로고침"
            case "zh-Hant": return "重新整理"
            default: return "Refresh"
            }
        case "Time Sensitive":
            switch languageCode {
            case "ko": return "긴급한 알림 "
            case "zh-Hant": return "時間敏感"
            default: return "Time Sensitive"
            }
        case "Region & Language":
            switch languageCode {
            case "ko": return "지역 및 언어"
            case "zh-Hant": return "地區與語言"
            default: return "Region & Language"
            }
        case "Choose the region to tailor language and filter warnings relevant to that area.":
            switch languageCode {
            case "ko": return "지역과 언어를 선택할 수 있습니다. 선택된 지역의 알림만 표시합니다."
            case "zh-Hant": return "選擇地區以配合語言，並篩選與該地區相關的警報。"
            default: return "Choose the region to tailor language and filter warnings relevant to that area."
            }
        case "Control whether alerts from this app are delivered. Time Sensitive requires the entitlement and raises the notification's interruption level to break through Focus modes.":
            switch languageCode {
            case "ko": return "이 앱의 알림 전달 여부를 제어합니다. 시간 민감 알림은 권한이 필요하며 집중 모드를 우회하도록 알림 중단 수준을 높입니다."
            case "zh-Hant": return "控制是否傳遞此 App 的提醒。時間敏感提醒需要權限，並提高中斷等級以穿透專注模式。"
            default: return "Control whether alerts from this app are delivered. Time Sensitive requires the entitlement and raises the notification's interruption level to break through Focus modes."
            }
        case "Appearance":
            switch languageCode {
            case "ko": return "화면 모드"
            case "zh-Hant": return "外觀"
            default: return "Appearance"
            }
        case "Theme":
            switch languageCode {
            case "ko": return "테마"
            case "zh-Hant": return "主題"
            default: return "Theme"
            }
        case "System":
            switch languageCode {
            case "ko": return "시스템"
            case "zh-Hant": return "系統"
            default: return "System"
            }
        case "Light":
            switch languageCode {
            case "ko": return "라이트"
            case "zh-Hant": return "淺色"
            default: return "Light"
            }
        case "Dark":
            switch languageCode {
            case "ko": return "다크"
            case "zh-Hant": return "深色"
            default: return "Dark"
            }
        case "Sources":
            switch languageCode {
            case "ko": return "데이터 제공"
            case "zh-Hant": return "來源"
            default: return "Sources"
            }
        case "These links open in your default browser.":
            switch languageCode {
            case "ko": return "링크를 누르면 기본 브라우저에서 열립니다."
            case "zh-Hant": return "這些連結將在您的預設瀏覽器中開啟。"
            default: return "These links open in your default browser."
            }
        case "Information is sourced from official seismic warning providers.":
            switch languageCode {
            case "ko": return "정보는 공식 지진 경보 제공처에서 가져옵니다."
            case "zh-Hant": return "資訊來源為官方地震警報提供單位。"
            default: return "Information is sourced from official seismic warning providers."
            }
        case "You are not connected to the internet.":
            switch languageCode {
            case "ko": return "인터넷에 연결되어 있지 않습니다."
            case "zh-Hant": return "您目前未連線至網際網路。"
            default: return "You are not connected to the internet."
            }
        case "Yesterday,":
            switch languageCode {
            case "ko": return "어제,"
            case "zh-Hant": return "昨天，"
            default: return "Yesterday,"
            }
        default:
            return key
        }
    }
    
    func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            // Today: just time
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            timeFormatter.locale = appLocale
            return timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            timeFormatter.locale = appLocale
            return "\(localizedString("Yesterday,", locale: appLocale)) " + timeFormatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.locale = appLocale
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
    
    func fetchWarnings() async {
        isLoading = true
        do {
            let results = try await EarthquakeWarningService.shared.fetchWarnings(for: selectedRegion)
            await MainActor.run {
                let filtered = filterWarnings(results, for: selectedRegion)
                self.warnings = filtered
                self.isLoading = false
                
                self.showingNotificationAlert = !filtered.isEmpty
                
                // Send notification only for the first filtered warning
                if let first = filtered.first {
                    sendLocalNotification(for: first)
                }
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.warnings = []
            }
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                print("Notification permission granted: \(granted)")
            }
        }
    }
    
    func magnitudeBadge(from description: String) -> String? {
        // Try to find a number that looks like magnitude in the description
        let pattern = "(M(?:agnitude)?\\s*)(\\d+(?:\\.\\d+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(location: 0, length: description.utf16.count)
        guard let match = regex.firstMatch(in: description, options: [], range: range), match.numberOfRanges >= 3,
              let magRange = Range(match.range(at: 2), in: description), let mag = Double(description[magRange]) else { return nil }
        let level: String
        switch mag {
        case 6.0...: level = "Severe"
        case 4.0..<6.0: level = "Moderate"
        default: level = "Light"
        }
        return "M\(String(format: "%.1f", mag)) • \(level)"
    }
    
    func sendLocalNotification(for warning: EarthquakeWarning) {
        // Try to extract magnitude and location from description
        let description = warning.description
        let magnitudeRegEx = try? NSRegularExpression(pattern: "Magnitude (\\d+(?:\\.\\d+)?) at (.+)")
        let match = magnitudeRegEx?.firstMatch(in: description, range: NSRange(description.startIndex..., in: description))
        var magnitudeLevel = ""
        var magnitudeValue = ""
        var location = ""
        if let match, let magRange = Range(match.range(at:1), in: description), let locRange = Range(match.range(at:2), in: description) {
            magnitudeValue = String(description[magRange])
            location = String(description[locRange])
            if let mag = Double(magnitudeValue) {
                if mag >= 6.0 {
                    magnitudeLevel = "🔴 "
                } else if mag >= 4.0 {
                    magnitudeLevel = "🟡 "
                } else {
                    magnitudeLevel = "🟢 "
                }
            }
        } else {
            location = warning.title
        }
        let eqStr = localizedString("EARTHQUAKE", locale: appLocale)
        let title = "\(magnitudeLevel)M\(magnitudeValue.isEmpty ? "?" : magnitudeValue) \(eqStr)"
        let body = "\u{25A0} \(location)\n" + warning.title
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Elevate to time-sensitive interruption level when enabled and supported
        if timeSensitiveEnabled {
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

#Preview {
    ContentView()
}

// VisualEffectBlur (for better glass look, works as a cross-platform placeholder)
struct VisualEffectBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    }
    func updateUIView(_ view: UIVisualEffectView, context: Context) {}
}


// Lightweight LiquidGlass background to resolve missing symbol and provide a modern glass effect
struct LiquidGlass: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let top = Color(uiColor: .systemBackground)
        let bottom = Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemGroupedBackground)

        LinearGradient(
            gradient: Gradient(colors: [top, bottom]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            // A subtle material veil to pick up surrounding colors and feel glassy in both modes
            Rectangle().fill(.ultraThinMaterial)
        )
        .ignoresSafeArea()
    }
}

