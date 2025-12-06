//
//  ContentView.swift
//  Earthquake Warning
//
//  Created by Sebastian Raynham on 2025-11-26.
//

import Foundation
import SwiftUI
import UserNotifications

// Simple model for earthquake/tsunami warnings
struct EarthquakeWarning: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let receivedAt: Date
}

let regions = ["대한민국 (한국어)", "中国 (简体中文)", "臺灣 (繁體中文)"]

func localeForRegion(_ region: String) -> Locale {
    switch region {
    case "대한민국 (한국어)": return Locale(identifier: "ko")
    case "中国 (简体中文)": return Locale(identifier: "zh-Hans")
    case "臺灣 (繁體中文)": return Locale(identifier: "zh-Hant")
    default: return Locale.current
    }
}

struct ContentView: View {
    @AppStorage("selectedRegion") private var selectedRegion: String = regions.first ?? "대한민국"
    @State private var appLocale: Locale = localeForRegion(regions.first!)
    @State private var warnings: [EarthquakeWarning] = []
    @State private var isLoading = false
    @State private var showingNotificationAlert = false
    @State private var showingOptions: Bool = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("timeSensitiveEnabled") private var timeSensitiveEnabled: Bool = false
    
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
                                Text(localizedString("Earthquake", locale: appLocale))
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .frame(height: geo.size.height * 0.3)
                            // Notification area block
                            VStack {
                                if let latest = warnings.first {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(latest.title)
                                            .font(.title2).bold()
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
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                            .frame(height: geo.size.height * 0.7 - 24)
                        }
                        .frame(height: geo.size.height)
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0)) {
                                showingOptions = true
                            }
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 22, weight: .medium))
                                .frame(width: 48, height: 48)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 3)
                                .scaleEffect(showingOptions ? 1.05 : 1)
                                .opacity(showingOptions ? 0.95 : 1)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sheet(isPresented: $showingOptions) {
                            VStack(spacing: 16) {
                                Text(localizedString("Settings", locale: appLocale))
                                    .font(.system(size: 22, weight: .semibold))
                                Divider()
                                // Notifications section
                                Toggle(isOn: $notificationsEnabled) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "bell")
                                        Text(localizedString("Notifications", locale: appLocale))
                                    }
                                }
                                .onChange(of: notificationsEnabled) { oldValue, newValue in
                                    if newValue {
                                        // Request authorization including time sensitive if enabled
                                        // Time Sensitive delivery is controlled by entitlement and notification interruption level, not by authorization options.
                                        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
                                        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, _ in
                                            DispatchQueue.main.async {
                                                notificationsEnabled = granted
                                            }
                                        }
                                    } else {
                                        // Can't revoke programmatically; reflect state and suggest user changes in Settings if needed
                                        notificationsEnabled = false
                                    }
                                }
                                
                                Toggle(isOn: $timeSensitiveEnabled) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.red)
                                        Text(localizedString("Time Sensitive", locale: appLocale))
                                    }
                                }
                                .onChange(of: timeSensitiveEnabled) {
                                    // If notifications are enabled, re-request to include/exclude time sensitive option
                                    guard notificationsEnabled else { return }
                                    // Time Sensitive delivery is controlled by entitlement and notification interruption level, not by authorization options.
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
                                
                                // Region & Language (inline row styled like a toggle)
                                HStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "globe")
                                        Text(localizedString("Region & Language", locale: appLocale))
                                    }
                                    Spacer()
                                    Picker(localizedString("Region & Language", locale: appLocale), selection: $selectedRegion) {
                                        ForEach(regions, id: \.self) { region in
                                            Text(region).tag(region)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                }
                                .onChange(of: selectedRegion) { oldValue, newValue in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        appLocale = localeForRegion(newValue)
                                    }
                                    Task { await fetchWarnings() }
                                }
                                
                                // Guidance under Region & Language
                                Text(localizedString("Choose the region to tailor language and filter warnings relevant to that area.", locale: appLocale))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Spacer()
                            }
                            .padding()
                            .presentationDetents([.medium])
                        }
                        
                        Button(action: { Task { await fetchWarnings() } }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(width: 48, height: 48)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                                .shadow(color: Color.accentColor.opacity(0.09), radius: 5, x: 0, y: 3)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .environment(\.locale, appLocale)
        .task {
            requestNotificationPermission()
            await fetchWarnings()
        }
        .alert(localizedString("New Warning!", locale: appLocale), isPresented: $showingNotificationAlert) {
            Button(localizedString("OK", locale: appLocale)) {}
        } message: {
            Text(localizedString("A new earthquake/tsunami warning was received.", locale: appLocale))
        }
    }
    
    func localizedString(_ key: String, locale: Locale) -> String {
        // Simple localized strings for demo purposes
        // In a real app, use Localizable.strings files per language
        let languageCode = locale.identifier
        switch key {
        case "Earthquake":
            switch languageCode {
            case "ko": return "지진"
            case "zh-Hans": return "地震"
            case "zh-Hant": return "地震"
            default: return "Earthquake"
            }
        case "Fetching warnings...":
            switch languageCode {
            case "ko": return "경고를 가져오는 중..."
            case "zh-Hans": return "正在获取警告..."
            case "zh-Hant": return "正在取得警告..."
            default: return "Fetching warnings..."
            }
        case "No warnings.":
            switch languageCode {
            case "ko": return "경고 없음"
            case "zh-Hans": return "无警告"
            case "zh-Hant": return "無警告"
            default: return "No warnings."
            }
        case "New Warning!":
            switch languageCode {
            case "ko": return "새 경고!"
            case "zh-Hans": return "新警报！"
            case "zh-Hant": return "新警報！"
            default: return "New Warning!"
            }
        case "OK":
            switch languageCode {
            case "ko": return "확인"
            case "zh-Hans": return "好的"
            case "zh-Hant": return "確定"
            default: return "OK"
            }
        case "A new earthquake/tsunami warning was received.":
            switch languageCode {
            case "ko": return "새로운 지진/쓰나미 경고가 접수되었습니다."
            case "zh-Hans": return "收到新的地震/海啸警报。"
            case "zh-Hant": return "收到新的地震/海嘯警報。"
            default: return "A new earthquake/tsunami warning was received."
            }
        case "EARTHQUAKE":
            switch languageCode {
            case "ko": return "지진"
            case "zh-Hans": return "地震"
            case "zh-Hant": return "地震"
            default: return "EARTHQUAKE"
            }
        case "Magnitude":
            switch languageCode {
            case "ko": return "규모"
            case "zh-Hans": return "震级"
            case "zh-Hant": return "規模"
            default: return "Magnitude"
            }
        case "Settings":
            switch languageCode {
            case "ko": return "설정"
            case "zh-Hans": return "设置"
            case "zh-Hant": return "設定"
            default: return "Settings"
            }
        case "Notifications":
            switch languageCode {
            case "ko": return "알림"
            case "zh-Hans": return "通知"
            case "zh-Hant": return "通知"
            default: return "Notifications"
            }
        case "Time Sensitive":
            switch languageCode {
            case "ko": return "긴급한 알림 "
            case "zh-Hans": return "时间敏感"
            case "zh-Hant": return "時間敏感"
            default: return "Time Sensitive"
            }
        case "Region & Language":
            switch languageCode {
            case "ko": return "지역 및 언어"
            case "zh-Hans": return "地区与语言"
            case "zh-Hant": return "地區與語言"
            default: return "Region & Language"
            }
        case "Choose the region to tailor language and filter warnings relevant to that area.":
            switch languageCode {
            case "ko": return "지역과 언어를 선택할 수 있습니다. 선택된 지역의 알림만 표시합니다."
            case "zh-Hans": return "选择地区以匹配语言，并筛选与该地区相关的警报。"
            case "zh-Hant": return "選擇地區以配合語言，並篩選與該地區相關的警報。"
            default: return "Choose the region to tailor language and filter warnings relevant to that area."
            }
        case "Control whether alerts from this app are delivered. Time Sensitive requires the entitlement and raises the notification's interruption level to break through Focus modes.":
            switch languageCode {
            case "ko": return "이 앱의 알림 전달 여부를 제어합니다. 시간 민감 알림은 권한이 필요하며 집중 모드를 우회하도록 알림 중단 수준을 높입니다."
            case "zh-Hans": return "控制是否传递此应用的提醒。时间敏感提醒需要权限，并提高打断级别以穿透专注模式。"
            case "zh-Hant": return "控制是否傳遞此 App 的提醒。時間敏感提醒需要權限，並提高中斷等級以穿透專注模式。"
            default: return "Control whether alerts from this app are delivered. Time Sensitive requires the entitlement and raises the notification's interruption level to break through Focus modes."
            }
        case "Yesterday,":
            switch languageCode {
            case "ko": return "어제,"
            case "zh-Hans": return "昨天，"
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
            formatter.dateFormat = "EEEE, yyyy/MM/dd, h:mm a"
            return formatter.string(from: date)
        }
    }
    
    func fetchWarnings() async {
        isLoading = true
        do {
            let results = try await EarthquakeWarningService.shared.fetchWarnings(for: selectedRegion)
            await MainActor.run {
                // Filter results to only those containing the selected region in title or description
                let filtered = results.filter { $0.title.contains(selectedRegion) || $0.description.contains(selectedRegion) }
                self.warnings = filtered
                self.isLoading = false
                
                // Show alert only if there are filtered warnings
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
    var body: some View {
        Color.white
            .ignoresSafeArea()
    }
}

