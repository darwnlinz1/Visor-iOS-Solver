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
        case .missing:
            return mode == .developer ? "Đã bỏ qua (Developer Mode)" : "Chưa đặt"
        case .empty, .developerDefault:
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

    /// Returns true when an incoming URL should be forwarded to `Wearables.shared.handleUrl(_:)`.
    /// Forwards any URL carrying `metaWearablesAction` OR matching one of the app's registered custom
    /// URL schemes (excluding web schemes `http`/`https`) so legitimate Meta AI callbacks without
    /// `metaWearablesAction` (e.g., error or unregistration redirects) are never silently dropped.
    static func shouldForwardToWearablesSDK(_ url: URL, registeredSchemes: [String]) -> Bool {
        if isMetaWearablesCallbackURL(url) {
            return true
        }
        guard let incomingScheme = url.scheme?.lowercased(),
              !incomingScheme.isEmpty,
              incomingScheme != "http",
              incomingScheme != "https" else {
            return false
        }
        return registeredSchemes.contains { registered in
            let candidate = registered.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !candidate.isEmpty
                && candidate != "http"
                && candidate != "https"
                && candidate == incomingScheme
        }
    }

    /// Safe redacted telemetry summary of an incoming callback URL for Release and Debug logging.
    /// Includes only the URL scheme, whether `metaWearablesAction` is present, and sorted query
    /// parameter NAMES (never query values, host/path secrets, or user text).
    static func redactedURLSummary(_ url: URL) -> String {
        let scheme = url.scheme ?? "none"
        let hasAction = isMetaWearablesCallbackURL(url)
        let queryNames: [String]
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            queryNames = Array(Set(items.map(\.name))).sorted()
        } else {
            queryNames = []
        }
        let keysText = queryNames.isEmpty ? "<none>" : queryNames.joined(separator: ",")
        return "scheme=\(scheme), hasMetaWearablesAction=\(hasAction), queryKeys=[\(keysText)]"
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

        let rawBundleIdentifier = info["CFBundleIdentifier"] as? String
        let bundleIdentifier = (rawBundleIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if info["CFBundleIdentifier"] == nil {
            issues.append("Thiếu CFBundleIdentifier trong Info.plist.")
        } else if let rawBundle = rawBundleIdentifier {
            if rawBundle.isEmpty {
                issues.append("Thiếu CFBundleIdentifier trong Info.plist.")
            } else if containsPlaceholder(rawBundle) {
                hasOtherPlaceholder = true
                issues.append("CFBundleIdentifier đang chứa giá trị mẫu (placeholder).")
            } else if hasWhitespace(rawBundle) {
                issues.append("CFBundleIdentifier không được chứa khoảng trắng.")
            }
        } else {
            issues.append("CFBundleIdentifier phải là chuỗi ký tự.")
        }

        let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let rawPrimarySchemes = urlTypes.first?["CFBundleURLSchemes"] as? [String] ?? []
        let rawFirstScheme = rawPrimarySchemes.first
        let allRawSchemes: [String] = urlTypes.flatMap { entry in
            entry["CFBundleURLSchemes"] as? [String] ?? []
        }
        let registeredURLSchemes: [String] = allRawSchemes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

        // 1. MetaAppID (check raw unstripped string; distinguish missing vs non-String)
        let metaAppIDState: MWDATFieldState
        let validatedMetaAppID: String
        if mwdat["MetaAppID"] == nil {
            validatedMetaAppID = ""
            metaAppIDState = .missing
            issues.append("Thiếu MWDAT.MetaAppID trong Info.plist.")
        } else if let rawMetaAppID = mwdat["MetaAppID"] as? String {
            if containsPlaceholder(rawMetaAppID) {
                validatedMetaAppID = ""
                metaAppIDState = .placeholder
                issues.append("MWDAT.MetaAppID đang chứa giá trị mẫu (placeholder). Cần đặt 0 cho Developer Mode hoặc Meta App ID thật.")
            } else if hasWhitespace(rawMetaAppID) {
                validatedMetaAppID = ""
                metaAppIDState = .invalid
                issues.append("MWDAT.MetaAppID không được chứa khoảng trắng.")
            } else if rawMetaAppID.isEmpty {
                validatedMetaAppID = ""
                metaAppIDState = .empty
            } else if rawMetaAppID == "0" {
                validatedMetaAppID = "0"
                metaAppIDState = .developerDefault
            } else if isPositiveASCIIInteger(rawMetaAppID) {
                validatedMetaAppID = rawMetaAppID
                metaAppIDState = .configured
            } else {
                validatedMetaAppID = ""
                metaAppIDState = .invalid
                issues.append("MWDAT.MetaAppID không hợp lệ (chỉ chấp nhận 0/trống cho Developer Mode hoặc chuỗi chữ số cho Production).")
            }
        } else {
            validatedMetaAppID = ""
            metaAppIDState = .invalid
            issues.append("MWDAT.MetaAppID phải là chuỗi ký tự.")
        }

        let isDeveloperAppID = (metaAppIDState == .developerDefault || metaAppIDState == .empty)
        let isProductionAppID = (metaAppIDState == .configured)

        // 2. ClientToken (redacted — never stored or included in issues; check raw unstripped string)
        let clientTokenState: MWDATFieldState
        if mwdat["ClientToken"] == nil {
            clientTokenState = .missing
            if isProductionAppID {
                issues.append("Chế độ Production yêu cầu MWDAT.ClientToken (định dạng AR|<MetaAppID>|<token>).")
            }
        } else if let rawClientToken = mwdat["ClientToken"] as? String {
            if containsPlaceholder(rawClientToken) {
                clientTokenState = .placeholder
                issues.append("MWDAT.ClientToken đang chứa giá trị mẫu (placeholder). Hãy để trống cho Developer Mode hoặc dùng token thật cho Production.")
            } else if hasWhitespace(rawClientToken) {
                clientTokenState = .invalid
                issues.append("MWDAT.ClientToken không được chứa khoảng trắng.")
            } else if rawClientToken.isEmpty {
                clientTokenState = .empty
                if isProductionAppID {
                    issues.append("Chế độ Production yêu cầu MWDAT.ClientToken (định dạng AR|<MetaAppID>|<token>).")
                }
            } else if isDeveloperAppID {
                clientTokenState = .invalid
                issues.append("Developer Mode yêu cầu MWDAT.ClientToken để trống để tránh lỗi đăng ký.")
            } else if isProductionAppID {
                if isValidClientToken(rawClientToken, metaAppID: validatedMetaAppID) {
                    clientTokenState = .configured
                } else {
                    clientTokenState = .invalid
                    issues.append("MWDAT.ClientToken không đúng định dạng AR|<MetaAppID>|<token>.")
                }
            } else {
                clientTokenState = isValidGeneralClientToken(rawClientToken) ? .configured : .invalid
                if clientTokenState == .invalid {
                    issues.append("MWDAT.ClientToken không đúng định dạng AR|<MetaAppID>|<token>.")
                }
            }
        } else {
            clientTokenState = .invalid
            issues.append("MWDAT.ClientToken phải là chuỗi ký tự.")
        }

        // 3. TeamID (redacted — never stored or included in issues; check raw unstripped string)
        let teamIDState: MWDATFieldState
        if mwdat["TeamID"] == nil {
            teamIDState = .missing
            if isProductionAppID {
                issues.append("Chế độ Production yêu cầu MWDAT.TeamID (10 ký tự Apple Team ID).")
            }
        } else if let rawTeamID = mwdat["TeamID"] as? String {
            if containsPlaceholder(rawTeamID) {
                teamIDState = .placeholder
                issues.append("MWDAT.TeamID đang chứa giá trị mẫu (placeholder).")
            } else if hasWhitespace(rawTeamID) {
                teamIDState = .invalid
                issues.append("MWDAT.TeamID không được chứa khoảng trắng.")
            } else if rawTeamID.isEmpty {
                teamIDState = .empty
                if isProductionAppID {
                    issues.append("Chế độ Production yêu cầu MWDAT.TeamID (10 ký tự Apple Team ID).")
                }
            } else if isValidAppleTeamID(rawTeamID) {
                teamIDState = .configured
            } else {
                teamIDState = .invalid
                issues.append("MWDAT.TeamID không hợp lệ (cần đúng 10 ký tự chữ in hoa/số hoặc để trống ở Developer Mode).")
            }
        } else {
            teamIDState = .invalid
            issues.append("MWDAT.TeamID phải là chuỗi ký tự.")
        }

        // 4. CFBundleURLSchemes & MWDAT.AppLinkURLScheme (inspect raw values BEFORE trimming/filtering)
        let rawAppLinkValue = mwdat["AppLinkURLScheme"] as? String
        let appLinkURLScheme = (rawAppLinkValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if allRawSchemes.contains(where: { containsPlaceholder($0) }) {
            hasOtherPlaceholder = true
            hasURLSchemeError = true
            issues.append("CFBundleURLSchemes đang chứa giá trị mẫu (placeholder).")
        } else if rawPrimarySchemes.isEmpty {
            hasURLSchemeError = true
            issues.append("Thiếu CFBundleURLSchemes trong Info.plist để nhận phản hồi từ app Meta AI.")
        } else if let firstScheme = rawFirstScheme {
            if firstScheme.isEmpty || hasWhitespace(firstScheme) {
                hasURLSchemeError = true
                issues.append("CFBundleURLSchemes[0] không được trống hoặc chứa khoảng trắng.")
            } else if !isValidURLScheme(firstScheme) {
                hasURLSchemeError = true
                issues.append("CFBundleURLSchemes[0] không phải custom URL scheme hợp lệ (không được dùng http/https).")
            }
        }

        if mwdat["AppLinkURLScheme"] == nil {
            hasURLSchemeError = true
            issues.append("Thiếu MWDAT.AppLinkURLScheme trong Info.plist.")
        } else if let rawAppLink = rawAppLinkValue {
            if rawAppLink.isEmpty {
                hasURLSchemeError = true
                issues.append("Thiếu MWDAT.AppLinkURLScheme trong Info.plist.")
            } else if containsPlaceholder(rawAppLink) {
                hasOtherPlaceholder = true
                hasURLSchemeError = true
                issues.append("MWDAT.AppLinkURLScheme đang chứa giá trị mẫu (placeholder).")
            } else if hasWhitespace(rawAppLink) {
                hasURLSchemeError = true
                issues.append("MWDAT.AppLinkURLScheme không được chứa khoảng trắng.")
            } else if isProductionAppID {
                let primaryScheme = rawFirstScheme ?? ""
                let matchesCustom = !hasWhitespace(primaryScheme)
                    && isValidURLScheme(primaryScheme)
                    && rawAppLink.lowercased() == "\(primaryScheme.lowercased())://"
                if !isValidHTTPSUniversalLink(rawAppLink) && !matchesCustom {
                    hasURLSchemeError = true
                    issues.append("MWDAT.AppLinkURLScheme ở chế độ Production phải là đường dẫn https:// (Universal Link) hợp lệ hoặc khớp <CFBundleURLSchemes>://.")
                }
            } else {
                if !rawAppLink.hasSuffix("://") {
                    hasURLSchemeError = true
                    issues.append("MWDAT.AppLinkURLScheme phải kết thúc bằng \"://\" (ví dụ: openvision://).")
                } else if let primaryScheme = rawFirstScheme,
                          !hasWhitespace(primaryScheme),
                          isValidURLScheme(primaryScheme),
                          rawAppLink.lowercased() != "\(primaryScheme.lowercased())://" {
                    hasURLSchemeError = true
                    issues.append("MWDAT.AppLinkURLScheme không khớp với CFBundleURLSchemes trong Info.plist.")
                }
            }
        } else {
            hasURLSchemeError = true
            issues.append("MWDAT.AppLinkURLScheme phải là chuỗi ký tự.")
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

    private static func hasControlOrForbiddenURLChars(_ value: String) -> Bool {
        for scalar in value.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || scalar.value < 0x20
                || scalar.value == 0x7F {
                return true
            }
            switch scalar.value {
            case 0x22, // '"'
                 0x27, // '\''
                 0x3B, // ';'
                 0x3C, // '<'
                 0x3E, // '>'
                 0x5C, // '\\'
                 0x5E, // '^'
                 0x60, // '`'
                 0x7B, // '{'
                 0x7C, // '|'
                 0x7D: // '}'
                return true
            default:
                continue
            }
        }
        return false
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
        let lower = value.lowercased()
        if lower == "http" || lower == "https" {
            return false
        }
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

    private static func isValidDNSLabel(_ label: Substring) -> Bool {
        guard !label.isEmpty, label.count <= 63 else { return false }
        let scalars = Array(label.unicodeScalars)
        guard let first = scalars.first, let last = scalars.last else { return false }
        func isASCIIAlnum(_ s: Unicode.Scalar) -> Bool {
            (s.value >= 65 && s.value <= 90)
                || (s.value >= 97 && s.value <= 122)
                || (s.value >= 48 && s.value <= 57)
        }
        guard isASCIIAlnum(first), isASCIIAlnum(last) else { return false }
        return scalars.allSatisfy { s in isASCIIAlnum(s) || s.value == 45 } // '-'
    }

    private static func isValidIPv4Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard !part.isEmpty, part.count <= 3,
                  part.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
                  let octet = Int(part), octet >= 0 && octet <= 255 else {
                return false
            }
            if part.count > 1 && part.hasPrefix("0") { return false }
        }
        return true
    }

    private static func isValidIPv6Host(_ host: String) -> Bool {
        guard host.contains(":"), host.count <= 45, !host.contains(":::") else { return false }
        guard host.unicodeScalars.allSatisfy({ s in
            (s.value >= 48 && s.value <= 57)
                || (s.value >= 65 && s.value <= 70)
                || (s.value >= 97 && s.value <= 102)
                || s.value == 58 // ':'
        }) else {
            return false
        }
        let doubleColonParts = host.components(separatedBy: "::")
        guard doubleColonParts.count <= 2 else { return false }
        let groups: [Substring]
        if doubleColonParts.count == 2 {
            let left: [Substring] = doubleColonParts[0].isEmpty
                ? []
                : doubleColonParts[0].split(separator: ":", omittingEmptySubsequences: false)
            let right: [Substring] = doubleColonParts[1].isEmpty
                ? []
                : doubleColonParts[1].split(separator: ":", omittingEmptySubsequences: false)
            guard left.count + right.count < 8 else { return false }
            groups = left + right
        } else {
            let parts = host.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 8 else { return false }
            groups = parts
        }
        return groups.allSatisfy { !$0.isEmpty && $0.count <= 4 }
    }

    private static func isValidHTTPSHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }
        if isValidIPv4Host(host) {
            return true
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.allSatisfy(isValidDNSLabel) else { return false }
        let allNumeric = labels.allSatisfy { label in
            label.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
        }
        return !allNumeric
    }

    private static func isValidHTTPSUniversalLink(_ value: String) -> Bool {
        guard value.lowercased().hasPrefix("https://"),
              !containsPlaceholder(value),
              !hasControlOrForbiddenURLChars(value),
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        let afterScheme = value.dropFirst("https://".count)
        let authorityEnd = afterScheme.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? afterScheme.endIndex
        let authority = afterScheme[..<authorityEnd]
        if authority.contains("@") || authority.hasSuffix(":") {
            return false
        }
        if host.contains(":") {
            guard authority.hasPrefix("[") else { return false }
            let bareHost = (host.hasPrefix("[") && host.hasSuffix("]"))
                ? String(host.dropFirst().dropLast())
                : host
            guard isValidIPv6Host(bareHost) else { return false }
            if let closeBracket = authority.firstIndex(of: "]") {
                let afterBracket = authority[authority.index(after: closeBracket)...]
                if !afterBracket.isEmpty {
                    guard afterBracket.hasPrefix(":") else { return false }
                    let portChars = afterBracket.dropFirst()
                    guard !portChars.isEmpty,
                          portChars.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
                          let parsedPort = Int(portChars),
                          parsedPort >= 1 && parsedPort <= 65535 else {
                        return false
                    }
                }
            } else {
                return false
            }
        } else {
            guard isValidHTTPSHost(host) else { return false }
            if let colonIndex = authority.lastIndex(of: ":") {
                let portChars = authority[authority.index(after: colonIndex)...]
                guard !portChars.isEmpty,
                      portChars.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
                      let parsedPort = Int(portChars),
                      parsedPort >= 1 && parsedPort <= 65535 else {
                    return false
                }
            }
        }
        if let port = components.port {
            guard port >= 1 && port <= 65535 else { return false }
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
