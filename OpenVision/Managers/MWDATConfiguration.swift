// OpenVision - MWDATConfiguration.swift
// Pure Foundation inspector for Info.plist MWDAT configuration and Meta AI callback URLs.
// Redacted by design: raw ClientToken and Apple TeamID values are never stored or emitted.

import Foundation

enum MWDATConfigMode: String, Equatable, Sendable {
    case developer
    case production
    case invalidPlaceholder
    case invalidFormat
}

enum MWDATFieldState: String, Equatable, Sendable {
    case empty
    case developerDefault
    case configured
    case placeholder
    case invalid
    case missing
}

struct MWDATConfigurationReport: Equatable, Sendable {
    let mode: MWDATConfigMode
    let metaAppIDState: MWDATFieldState
    let clientTokenState: MWDATFieldState
    let teamIDState: MWDATFieldState
    /// Non-secret callback scheme or Universal Link from MWDAT.AppLinkURLScheme.
    let appLinkURLScheme: String
    /// Non-secret custom URL schemes declared under CFBundleURLTypes.
    let registeredURLSchemes: [String]
    /// Bundle identifier from CFBundleIdentifier.
    let bundleIdentifier: String
    /// True when LSApplicationQueriesSchemes includes "fb-viewapp".
    let hasMetaAIQueryScheme: Bool
    /// True when Bluetooth Classic keys (bluetooth-central, external-accessory, com.meta.ar.wearable) are present.
    let hasBluetoothClassic: Bool
    /// Actionable Vietnamese diagnostic issues (never containing raw secrets).
    let issues: [String]
    /// True when any configuration defect is expected to block registration or glasses connection.
    let hasBlockingIssues: Bool

    /// Safe redacted single-line summary for console/NSLog output (never contains raw ClientToken or TeamID).
    var logSummary: String {
        let schemesText = registeredURLSchemes.isEmpty ? "<none>" : registeredURLSchemes.joined(separator: ",")
        let appLinkText = appLinkURLScheme.isEmpty ? "<empty>" : appLinkURLScheme
        let bundleText = bundleIdentifier.isEmpty ? "<empty>" : bundleIdentifier
        return "mode=\(mode.rawValue), MetaAppID=\(metaAppIDState.rawValue), ClientToken=\(clientTokenState.rawValue), TeamID=\(teamIDState.rawValue), AppLinkURLScheme=\(appLinkText), CFBundleURLSchemes=[\(schemesText)], BundleID=\(bundleText), fb-viewapp=\(hasMetaAIQueryScheme), btClassic=\(hasBluetoothClassic), issues=\(issues.count)"
    }

    /// Human-readable Vietnamese mode label for Settings UI.
    var uiModeLabel: String {
        switch mode {
        case .developer:
            return "Developer Mode (0)"
        case .production:
            return "Production (Meta Developer Center)"
        case .invalidPlaceholder:
            return "Lỗi placeholder chưa cấu hình"
        case .invalidFormat:
            return "Lỗi định dạng cấu hình"
        }
    }

    /// Human-readable Vietnamese TeamID status for Settings UI (never exposes the raw Team ID).
    var uiTeamIDLabel: String {
        switch teamIDState {
        case .configured:
            return "Đã đặt"
        case .empty, .missing, .developerDefault:
            return mode == .developer ? "Trống (Developer Mode)" : "Chưa đặt"
        case .placeholder:
            return "Lỗi placeholder"
        case .invalid:
            return "Sai định dạng"
        }
    }
}

enum MWDATConfigurationValidator {
    /// Detects unreplaced template placeholders (e.g. YOUR_META_APP_ID, $(META_APP_ID), ${CLIENT_TOKEN}, XXXXXXXXXX).
    /// Intentionally checks "your_" (with underscore) so valid bundle IDs like "com.yourcompany.openvision" pass.
    static func containsPlaceholder(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("your_")
            || value.contains("$(")
            || value.contains("${")
            || lower.contains("xxxxxxxxxx")
    }

    /// Returns true only for Meta AI Wearables callback URLs carrying the `metaWearablesAction` query item.
    static func isMetaWearablesCallbackURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return false
        }
        return queryItems.contains(where: { $0.name == "metaWearablesAction" })
    }

    /// Inspects an app Info.plist dictionary and produces a redacted diagnostic report.
    static func inspect(infoDictionary: [String: Any]?) -> MWDATConfigurationReport {
        guard let info = infoDictionary else {
            return MWDATConfigurationReport(
                mode: .invalidFormat,
                metaAppIDState: .missing,
                clientTokenState: .missing,
                teamIDState: .missing,
                appLinkURLScheme: "",
                registeredURLSchemes: [],
                bundleIdentifier: "",
                hasMetaAIQueryScheme: false,
                hasBluetoothClassic: false,
                issues: ["Không đọc được Info.plist của ứng dụng."],
                hasBlockingIssues: true
            )
        }

        var issues: [String] = []
        var hasOtherPlaceholder = false
        var hasURLSchemeError = false

        let bundleIdentifier = (info["CFBundleIdentifier"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if bundleIdentifier.isEmpty {
            issues.append("Thiếu CFBundleIdentifier trong Info.plist.")
        } else if containsPlaceholder(bundleIdentifier) {
            hasOtherPlaceholder = true
            issues.append("CFBundleIdentifier đang chứa giá trị mẫu (placeholder).")
        } else if hasWhitespace(bundleIdentifier) {
            issues.append("CFBundleIdentifier không được chứa khoảng trắng.")
        }

        let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let registeredURLSchemes: [String] = urlTypes.flatMap { entry in
            (entry["CFBundleURLSchemes"] as? [String] ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        for entry in urlTypes {
            if let urlName = entry["CFBundleURLName"] as? String, containsPlaceholder(urlName) {
                hasOtherPlaceholder = true
                issues.append("CFBundleURLTypes.CFBundleURLName đang chứa giá trị mẫu (placeholder).")
                break
            }
        }

        let querySchemes = info["LSApplicationQueriesSchemes"] as? [String] ?? []
        let hasMetaAIQueryScheme = querySchemes.contains("fb-viewapp")
        if !hasMetaAIQueryScheme {
            issues.append("Thiếu \"fb-viewapp\" trong LSApplicationQueriesSchemes — không thể mở app Meta AI.")
        }

        let backgroundModes = info["UIBackgroundModes"] as? [String] ?? []
        let eaProtocols = info["UISupportedExternalAccessoryProtocols"] as? [String] ?? []
        let hasBluetoothClassic = backgroundModes.contains("bluetooth-central")
            && backgroundModes.contains("external-accessory")
            && eaProtocols.contains("com.meta.ar.wearable")
        if !hasBluetoothClassic {
            issues.append("Thiếu cấu hình Bluetooth Classic (bluetooth-central, external-accessory, com.meta.ar.wearable) trong Info.plist.")
        }

        guard let mwdat = info["MWDAT"] as? [String: Any] else {
            issues.append("Thiếu mục cấu hình MWDAT trong Info.plist.")
            return MWDATConfigurationReport(
                mode: hasOtherPlaceholder ? .invalidPlaceholder : .invalidFormat,
                metaAppIDState: .missing,
                clientTokenState: .missing,
                teamIDState: .missing,
                appLinkURLScheme: "",
                registeredURLSchemes: registeredURLSchemes,
                bundleIdentifier: bundleIdentifier,
                hasMetaAIQueryScheme: hasMetaAIQueryScheme,
                hasBluetoothClassic: hasBluetoothClassic,
                issues: issues,
                hasBlockingIssues: true
            )
        }

        // 1. MetaAppID
        let metaAppIDState: MWDATFieldState
        let trimmedMetaAppID: String
        if let rawMetaAppID = mwdat["MetaAppID"] as? String {
            trimmedMetaAppID = rawMetaAppID.trimmingCharacters(in: .whitespacesAndNewlines)
            if containsPlaceholder(trimmedMetaAppID) {
                metaAppIDState = .placeholder
                issues.append("MWDAT.MetaAppID đang chứa giá trị mẫu (placeholder). Cần đặt 0 cho Developer Mode hoặc Meta App ID thật.")
            } else if trimmedMetaAppID.isEmpty {
                metaAppIDState = .empty
            } else if trimmedMetaAppID == "0" {
                metaAppIDState = .developerDefault
            } else if isPositiveASCIIInteger(trimmedMetaAppID) {
                metaAppIDState = .configured
            } else {
                metaAppIDState = .invalid
                issues.append("MWDAT.MetaAppID không hợp lệ (chỉ chấp nhận 0/trống cho Developer Mode hoặc chuỗi chữ số cho Production).")
            }
        } else {
            trimmedMetaAppID = ""
            metaAppIDState = .missing
            issues.append("Thiếu MWDAT.MetaAppID trong Info.plist.")
        }

        let isDeveloperAppID = (metaAppIDState == .developerDefault || metaAppIDState == .empty)
        let isProductionAppID = (metaAppIDState == .configured)

        // 2. ClientToken (redacted — never stored or included in issues)
        let clientTokenState: MWDATFieldState
        if mwdat["ClientToken"] == nil {
            clientTokenState = .missing
            if isProductionAppID {
                issues.append("Chế độ Production yêu cầu MWDAT.ClientToken (định dạng AR|<MetaAppID>|<token>).")
            }
        } else if let rawClientToken = mwdat["ClientToken"] as? String {
            let trimmedToken = rawClientToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if containsPlaceholder(trimmedToken) {
                clientTokenState = .placeholder
                issues.append("MWDAT.ClientToken đang chứa giá trị mẫu (placeholder). Hãy để trống cho Developer Mode hoặc dùng token thật cho Production.")
            } else if trimmedToken.isEmpty {
                clientTokenState = .empty
                if isProductionAppID {
                    issues.append("Chế độ Production yêu cầu MWDAT.ClientToken (định dạng AR|<MetaAppID>|<token>).")
                }
            } else if isDeveloperAppID {
                clientTokenState = .invalid
                issues.append("Developer Mode yêu cầu MWDAT.ClientToken để trống để tránh lỗi đăng ký.")
            } else if isProductionAppID {
                if isValidClientToken(trimmedToken, metaAppID: trimmedMetaAppID) {
                    clientTokenState = .configured
                } else {
                    clientTokenState = .invalid
                    issues.append("MWDAT.ClientToken không đúng định dạng AR|<MetaAppID>|<token>.")
                }
            } else {
                clientTokenState = isValidGeneralClientToken(trimmedToken) ? .configured : .invalid
                if clientTokenState == .invalid {
                    issues.append("MWDAT.ClientToken không đúng định dạng AR|<MetaAppID>|<token>.")
                }
            }
        } else {
            clientTokenState = .invalid
            issues.append("MWDAT.ClientToken phải là chuỗi ký tự.")
        }

        // 3. TeamID (redacted — never stored or included in issues)
        let teamIDState: MWDATFieldState
        if mwdat["TeamID"] == nil {
            teamIDState = .missing
            if isProductionAppID {
                issues.append("Chế độ Production yêu cầu MWDAT.TeamID (10 ký tự Apple Team ID).")
            }
        } else if let rawTeamID = mwdat["TeamID"] as? String {
            let trimmedTeamID = rawTeamID.trimmingCharacters(in: .whitespacesAndNewlines)
            if containsPlaceholder(trimmedTeamID) {
                teamIDState = .placeholder
                issues.append("MWDAT.TeamID đang chứa giá trị mẫu (placeholder).")
            } else if trimmedTeamID.isEmpty {
                teamIDState = .empty
                if isProductionAppID {
                    issues.append("Chế độ Production yêu cầu MWDAT.TeamID (10 ký tự Apple Team ID).")
                }
            } else if isValidAppleTeamID(trimmedTeamID) {
                teamIDState = .configured
            } else {
                teamIDState = .invalid
                issues.append("MWDAT.TeamID không hợp lệ (cần đúng 10 ký tự chữ in hoa/số hoặc để trống ở Developer Mode).")
            }
        } else {
            teamIDState = .invalid
            issues.append("MWDAT.TeamID phải là chuỗi ký tự.")
        }

        // 4. CFBundleURLSchemes & MWDAT.AppLinkURLScheme
        let appLinkURLScheme = (mwdat["AppLinkURLScheme"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if registeredURLSchemes.isEmpty {
            hasURLSchemeError = true
            issues.append("Thiếu CFBundleURLSchemes trong Info.plist để nhận phản hồi từ app Meta AI.")
        } else if registeredURLSchemes.contains(where: { containsPlaceholder($0) }) {
            hasOtherPlaceholder = true
            hasURLSchemeError = true
            issues.append("CFBundleURLSchemes đang chứa giá trị mẫu (placeholder).")
        } else if !isValidURLScheme(registeredURLSchemes[0]) {
            hasURLSchemeError = true
            issues.append("CFBundleURLSchemes[0] không phải URL scheme hợp lệ.")
        }

        if appLinkURLScheme.isEmpty {
            hasURLSchemeError = true
            issues.append("Thiếu MWDAT.AppLinkURLScheme trong Info.plist.")
        } else if containsPlaceholder(appLinkURLScheme) {
            hasOtherPlaceholder = true
            hasURLSchemeError = true
            issues.append("MWDAT.AppLinkURLScheme đang chứa giá trị mẫu (placeholder).")
        } else if hasWhitespace(appLinkURLScheme) {
            hasURLSchemeError = true
            issues.append("MWDAT.AppLinkURLScheme không được chứa khoảng trắng.")
        } else if isProductionAppID {
            let primaryScheme = registeredURLSchemes.first ?? ""
            let matchesCustom = !primaryScheme.isEmpty
                && appLinkURLScheme.lowercased() == "\(primaryScheme.lowercased())://"
            if !isValidHTTPSUniversalLink(appLinkURLScheme) && !matchesCustom {
                hasURLSchemeError = true
                issues.append("MWDAT.AppLinkURLScheme ở chế độ Production phải là đường dẫn https:// (Universal Link) hoặc khớp <CFBundleURLSchemes>://.")
            }
        } else {
            if !appLinkURLScheme.hasSuffix("://") {
                hasURLSchemeError = true
                issues.append("MWDAT.AppLinkURLScheme phải kết thúc bằng \"://\" (ví dụ: openvision://).")
            } else if let primaryScheme = registeredURLSchemes.first,
                      isValidURLScheme(primaryScheme),
                      appLinkURLScheme.lowercased() != "\(primaryScheme.lowercased())://" {
                hasURLSchemeError = true
                issues.append("MWDAT.AppLinkURLScheme không khớp với CFBundleURLSchemes trong Info.plist.")
            }
        }

        // 5. Overall mode classification
        let hasPlaceholder = (metaAppIDState == .placeholder)
            || (clientTokenState == .placeholder)
            || (teamIDState == .placeholder)
            || hasOtherPlaceholder

        let mode: MWDATConfigMode
        if hasPlaceholder {
            mode = .invalidPlaceholder
        } else if isDeveloperAppID {
            if clientTokenState == .invalid || teamIDState == .invalid || hasURLSchemeError {
                mode = .invalidFormat
            } else {
                mode = .developer
            }
        } else if isProductionAppID {
            if clientTokenState != .configured || teamIDState != .configured || hasURLSchemeError {
                mode = .invalidFormat
            } else {
                mode = .production
            }
        } else {
            mode = .invalidFormat
        }

        let hasBlockingIssues = !issues.isEmpty || mode == .invalidPlaceholder || mode == .invalidFormat

        return MWDATConfigurationReport(
            mode: mode,
            metaAppIDState: metaAppIDState,
            clientTokenState: clientTokenState,
            teamIDState: teamIDState,
            appLinkURLScheme: appLinkURLScheme,
            registeredURLSchemes: registeredURLSchemes,
            bundleIdentifier: bundleIdentifier,
            hasMetaAIQueryScheme: hasMetaAIQueryScheme,
            hasBluetoothClassic: hasBluetoothClassic,
            issues: issues,
            hasBlockingIssues: hasBlockingIssues
        )
    }

    // MARK: - Validation Helpers

    private static func hasWhitespace(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
    }

    private static func isPositiveASCIIInteger(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        var hasNonZero = false
        for scalar in value.unicodeScalars {
            guard scalar.value >= 48 && scalar.value <= 57 else { return false }
            if scalar.value != 48 { hasNonZero = true }
        }
        return hasNonZero
    }

    private static func isValidAppleTeamID(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        return value.unicodeScalars.allSatisfy { s in
            (s.value >= 65 && s.value <= 90) || (s.value >= 48 && s.value <= 57)
        }
    }

    private static func isValidURLScheme(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        let firstIsAlpha = (first.value >= 65 && first.value <= 90) || (first.value >= 97 && first.value <= 122)
        guard firstIsAlpha else { return false }
        return value.unicodeScalars.allSatisfy { s in
            (s.value >= 65 && s.value <= 90)
                || (s.value >= 97 && s.value <= 122)
                || (s.value >= 48 && s.value <= 57)
                || s.value == 43 // '+'
                || s.value == 45 // '-'
                || s.value == 46 // '.'
        }
    }

    private static func isValidHTTPSUniversalLink(_ value: String) -> Bool {
        guard !hasWhitespace(value),
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    private static func isValidClientToken(_ token: String, metaAppID: String) -> Bool {
        guard !hasWhitespace(token) else { return false }
        let prefix = "AR|\(metaAppID)|"
        guard token.hasPrefix(prefix) else { return false }
        let secretPart = token.dropFirst(prefix.count)
        return !secretPart.isEmpty
    }

    private static func isValidGeneralClientToken(_ token: String) -> Bool {
        guard !hasWhitespace(token) else { return false }
        let parts = token.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "AR",
              isPositiveASCIIInteger(String(parts[1])),
              !parts[2].isEmpty else {
            return false
        }
        return true
    }
}
