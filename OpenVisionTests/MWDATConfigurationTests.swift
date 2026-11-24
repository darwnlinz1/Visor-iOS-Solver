// OpenVision - MWDATConfigurationTests.swift
// Unit and host-bundle tests for MWDATConfigurationValidator (Info.plist MWDAT validation,
// secret redaction, and Meta AI callback URL filtering).

import XCTest
@testable import OpenVision

final class MWDATConfigurationTests: XCTestCase {
    private func makeInfoDictionary(
        bundleID: String = "com.yourcompany.openvision",
        metaAppID: String? = "0",
        clientToken: String? = "",
        teamID: String? = "",
        appLinkURLScheme: String? = "openvision://",
        urlSchemes: [String] = ["openvision"],
        urlName: String? = "com.yourcompany.openvision",
        querySchemes: [String] = ["fb-viewapp"],
        backgroundModes: [String] = ["audio", "bluetooth-central", "external-accessory"],
        eaProtocols: [String] = ["com.meta.ar.wearable"]
    ) -> [String: Any] {
        var mwdat: [String: Any] = [:]
        if let metaAppID { mwdat["MetaAppID"] = metaAppID }
        if let clientToken { mwdat["ClientToken"] = clientToken }
        if let teamID { mwdat["TeamID"] = teamID }
        if let appLinkURLScheme { mwdat["AppLinkURLScheme"] = appLinkURLScheme }

        var urlType: [String: Any] = [
            "CFBundleTypeRole": "Editor",
            "CFBundleURLSchemes": urlSchemes,
        ]
        if let urlName { urlType["CFBundleURLName"] = urlName }

        return [
            "CFBundleIdentifier": bundleID,
            "CFBundleURLTypes": [urlType],
            "LSApplicationQueriesSchemes": querySchemes,
            "UIBackgroundModes": backgroundModes,
            "UISupportedExternalAccessoryProtocols": eaProtocols,
            "MWDAT": mwdat,
        ]
    }

    func testValidDeveloperModeWithZeroMetaAppID() {
        let info = makeInfoDictionary(metaAppID: "0", clientToken: "", teamID: "")
        let report = MWDATConfigurationValidator.inspect(infoDictionary: info)

        XCTAssertEqual(report.mode, .developer)
        XCTAssertEqual(report.metaAppIDState, .developerDefault)
        XCTAssertEqual(report.clientTokenState, .empty)
        XCTAssertEqual(report.teamIDState, .empty)
        XCTAssertEqual(report.appLinkURLScheme, "openvision://")
        XCTAssertEqual(report.registeredURLSchemes, ["openvision"])
        XCTAssertEqual(report.bundleIdentifier, "com.yourcompany.openvision")
        XCTAssertTrue(report.hasMetaAIQueryScheme)
        XCTAssertTrue(report.hasBluetoothClassic)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertFalse(report.hasBlockingIssues)
    }

    func testValidDeveloperModeWithEmptyMetaAppIDAndOmittedOptionalKeys() {
        let info = makeInfoDictionary(metaAppID: "", clientToken: nil, teamID: nil)
        let report = MWDATConfigurationValidator.inspect(infoDictionary: info)

        XCTAssertEqual(report.mode, .developer)
        XCTAssertEqual(report.metaAppIDState, .empty)
        XCTAssertEqual(report.clientTokenState, .missing)
        XCTAssertEqual(report.teamIDState, .missing)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertFalse(report.hasBlockingIssues)
    }

    func testValidProductionModeWithUniversalLink() {
        let secretToken = "AR|123456789|secret_tok_prod_987"
        let teamID = "AB12CD34EF"
        let info = makeInfoDictionary(
            metaAppID: "123456789",
            clientToken: secretToken,
            teamID: teamID,
            appLinkURLScheme: "https://example.com/app",
            urlSchemes: ["openvision"]
        )
        let report = MWDATConfigurationValidator.inspect(infoDictionary: info)

        XCTAssertEqual(report.mode, .production)
        XCTAssertEqual(report.metaAppIDState, .configured)
        XCTAssertEqual(report.clientTokenState, .configured)
        XCTAssertEqual(report.teamIDState, .configured)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertFalse(report.hasBlockingIssues)
        XCTAssertFalse(report.logSummary.contains(secretToken))
        XCTAssertFalse(report.logSummary.contains("secret_tok_prod_987"))
        XCTAssertFalse(report.logSummary.contains(teamID))
    }

    func testDeveloperModeRejectsNonEmptyClientToken() {
        let leakedToken = "AR|0|dev_mode_should_not_have_token"
        let info = makeInfoDictionary(metaAppID: "0", clientToken: leakedToken, teamID: "")
        let report = MWDATConfigurationValidator.inspect(infoDictionary: info)

        XCTAssertEqual(report.mode, .invalidFormat)
        XCTAssertEqual(report.clientTokenState, .invalid)
        XCTAssertTrue(report.hasBlockingIssues)
        XCTAssertFalse(report.logSummary.contains(leakedToken))
        XCTAssertFalse(report.issues.joined(separator: " ").contains(leakedToken))
    }

    func testProductionModeRequiresClientTokenAndTeamID() {
        let info = makeInfoDictionary(
            metaAppID: "123456789",
            clientToken: "",
            teamID: "",
            appLinkURLScheme: "https://example.com/dat"
        )
        let report = MWDATConfigurationValidator.inspect(infoDictionary: info)

        XCTAssertEqual(report.mode, .invalidFormat)
        XCTAssertEqual(report.metaAppIDState, .configured)
        XCTAssertEqual(report.clientTokenState, .empty)
        XCTAssertEqual(report.teamIDState, .empty)
        XCTAssertTrue(report.hasBlockingIssues)
        XCTAssertGreaterThanOrEqual(report.issues.count, 2)
    }

    func testBrokenPlaceholdersAreDetected() {
        let info = makeInfoDictionary(
            metaAppID: "YOUR_META_APP_ID",
            clientToken: "AR|YOUR_META_APP_ID|YOUR_CLIENT_TOKEN",
            teamID: "YOUR_TEAM_ID"
        )
        let report = MWDATConfigurationValidator.inspect(infoDictionary: info)

        XCTAssertEqual(report.mode, .invalidPlaceholder)
        XCTAssertEqual(report.metaAppIDState, .placeholder)
        XCTAssertEqual(report.clientTokenState, .placeholder)
        XCTAssertEqual(report.teamIDState, .placeholder)
        XCTAssertTrue(report.hasBlockingIssues)
        XCTAssertFalse(report.issues.isEmpty)
    }

    func testUnexpandedBuildSettingVariablesAreDetectedAsPlaceholders() {
        XCTAssertTrue(MWDATConfigurationValidator.containsPlaceholder("$(META_APP_ID)"))
        XCTAssertTrue(MWDATConfigurationValidator.containsPlaceholder("${CLIENT_TOKEN}"))
        XCTAssertTrue(MWDATConfigurationValidator.containsPlaceholder("YOUR_TEAM_ID"))
        XCTAssertTrue(MWDATConfigurationValidator.containsPlaceholder("XXXXXXXXXX"))
        XCTAssertFalse(MWDATConfigurationValidator.containsPlaceholder("com.yourcompany.openvision"))

        let info = makeInfoDictionary(metaAppID: "$(META_APP_ID)", clientToken: "${CLIENT_TOKEN}", teamID: "")
        let report = MWDATConfigurationValidator.inspect(infoDictionary: info)

        XCTAssertEqual(report.mode, .invalidPlaceholder)
        XCTAssertEqual(report.metaAppIDState, .placeholder)
        XCTAssertEqual(report.clientTokenState, .placeholder)
        XCTAssertTrue(report.hasBlockingIssues)
    }

    func testURLSchemeMissingSuffixOrMismatchIsFlagged() {
        let missingSuffix = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(appLinkURLScheme: "openvision", urlSchemes: ["openvision"])
        )
        XCTAssertEqual(missingSuffix.mode, .invalidFormat)
        XCTAssertTrue(missingSuffix.hasBlockingIssues)

        let mismatched = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(appLinkURLScheme: "otherapp://", urlSchemes: ["openvision"])
        )
        XCTAssertEqual(mismatched.mode, .invalidFormat)
        XCTAssertTrue(mismatched.hasBlockingIssues)
    }

    func testMissingMetaAIQuerySchemeAndBluetoothClassicAreFlagged() {
        let missingMetaAI = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(querySchemes: [])
        )
        XCTAssertFalse(missingMetaAI.hasMetaAIQueryScheme)
        XCTAssertTrue(missingMetaAI.hasBlockingIssues)

        let missingExternalAccessory = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(backgroundModes: ["audio", "bluetooth-central"])
        )
        XCTAssertFalse(missingExternalAccessory.hasBluetoothClassic)
        XCTAssertTrue(missingExternalAccessory.hasBlockingIssues)

        let missingProtocol = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(eaProtocols: [])
        )
        XCTAssertFalse(missingProtocol.hasBluetoothClassic)
        XCTAssertTrue(missingProtocol.hasBlockingIssues)
    }

    func testSecretsNeverAppearInLogSummaryOrIssues() {
        let validToken = "AR|987654321|TOP_SECRET_VALID_TOKEN_XYZ"
        let invalidToken = "AR|111111111|TOP_SECRET_INVALID_TOKEN_ABC"
        let validTeam = "ZX98CV76BN"
        let invalidTeam = "bad_team_secret_123"

        let cases: [MWDATConfigurationReport] = [
            MWDATConfigurationValidator.inspect(infoDictionary: makeInfoDictionary(
                metaAppID: "987654321", clientToken: validToken, teamID: validTeam, appLinkURLScheme: "https://example.com/dat"
            )),
            MWDATConfigurationValidator.inspect(infoDictionary: makeInfoDictionary(
                metaAppID: "0", clientToken: invalidToken, teamID: invalidTeam
            )),
            MWDATConfigurationValidator.inspect(infoDictionary: makeInfoDictionary(
                metaAppID: "987654321", clientToken: invalidToken, teamID: invalidTeam
            )),
        ]

        let forbiddenSecrets = [
            validToken,
            "TOP_SECRET_VALID_TOKEN_XYZ",
            invalidToken,
            "TOP_SECRET_INVALID_TOKEN_ABC",
            validTeam,
            invalidTeam,
        ]

        for report in cases {
            let combinedOutput = ([report.logSummary, report.uiModeLabel, report.uiTeamIDLabel] + report.issues)
                .joined(separator: "\n")
            for secret in forbiddenSecrets {
                XCTAssertFalse(
                    combinedOutput.contains(secret),
                    "Secret \(secret) leaked into redacted MWDAT report output"
                )
            }
        }
    }

    func testIsMetaWearablesCallbackURLFiltering() {
        let registerURL = URL(string: "openvision://?metaWearablesAction=register")!
        let permissionURL = URL(string: "openvision://callback?foo=1&metaWearablesAction=permission")!
        let unrelatedURL = URL(string: "openvision://other?foo=bar")!
        let emptyQueryURL = URL(string: "openvision://")!

        XCTAssertTrue(MWDATConfigurationValidator.isMetaWearablesCallbackURL(registerURL))
        XCTAssertTrue(MWDATConfigurationValidator.isMetaWearablesCallbackURL(permissionURL))
        XCTAssertFalse(MWDATConfigurationValidator.isMetaWearablesCallbackURL(unrelatedURL))
        XCTAssertFalse(MWDATConfigurationValidator.isMetaWearablesCallbackURL(emptyQueryURL))
    }

    func testDeveloperAndProductionRejectHTTPAndHTTPSAsCustomURLSchemes() {
        for webScheme in ["http", "https", "HTTP", "HTTPS"] {
            let devReport = MWDATConfigurationValidator.inspect(
                infoDictionary: makeInfoDictionary(
                    metaAppID: "0",
                    clientToken: "",
                    teamID: "",
                    appLinkURLScheme: "\(webScheme)://",
                    urlSchemes: [webScheme]
                )
            )
            XCTAssertEqual(devReport.mode, .invalidFormat, "Dev mode must reject \(webScheme)://")
            XCTAssertTrue(devReport.hasBlockingIssues)

            let prodReport = MWDATConfigurationValidator.inspect(
                infoDictionary: makeInfoDictionary(
                    metaAppID: "123456789",
                    clientToken: "AR|123456789|valid_tok",
                    teamID: "AB12CD34EF",
                    appLinkURLScheme: "\(webScheme)://",
                    urlSchemes: [webScheme]
                )
            )
            XCTAssertEqual(prodReport.mode, .invalidFormat, "Prod mode must reject \(webScheme)://")
            XCTAssertTrue(prodReport.hasBlockingIssues)
        }
    }

    func testStrictHTTPSUniversalLinkValidation() {
        let validLinks = [
            "https://example.com/dat",
            "https://example.com:8443/dat?v=1",
            "HTTPS://openvision.example.com/callback",
            "https://[::1]/dat",
        ]
        for link in validLinks {
            let report = MWDATConfigurationValidator.inspect(
                infoDictionary: makeInfoDictionary(
                    metaAppID: "123456789",
                    clientToken: "AR|123456789|valid_tok",
                    teamID: "AB12CD34EF",
                    appLinkURLScheme: link
                )
            )
            XCTAssertEqual(report.mode, .production, "Expected valid Universal Link: \(link)")
            XCTAssertFalse(report.hasBlockingIssues, "Unexpected issues for \(link): \(report.issues)")
        }

        let invalidLinks = [
            "https://user@/dat",
            "https://user:pass@example.com/dat",
            "https://:443/dat",
            "https://example.com:0/dat",
            "https://example.com:99999/dat",
            "https://example.com:abc/dat",
            "https://example.com:/dat",
            "https://;rm",
            "https://foo|bar",
            "https://[::1/dat",
        ]
        for link in invalidLinks {
            let report = MWDATConfigurationValidator.inspect(
                infoDictionary: makeInfoDictionary(
                    metaAppID: "123456789",
                    clientToken: "AR|123456789|valid_tok",
                    teamID: "AB12CD34EF",
                    appLinkURLScheme: link
                )
            )
            XCTAssertEqual(report.mode, .invalidFormat, "Expected invalid Universal Link: \(link)")
            XCTAssertTrue(report.hasBlockingIssues)
        }
    }

    func testLeadingTrailingWhitespaceAndEmptyFirstURLSchemeRejected() {
        let wsMeta = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(metaAppID: " 0\n")
        )
        XCTAssertEqual(wsMeta.mode, .invalidFormat)
        XCTAssertEqual(wsMeta.metaAppIDState, .invalid)
        XCTAssertTrue(wsMeta.hasBlockingIssues)

        let wsBundle = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(bundleID: " com.yourcompany.openvision ")
        )
        XCTAssertTrue(wsBundle.hasBlockingIssues)

        let wsAppLink = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(appLinkURLScheme: " openvision://\n")
        )
        XCTAssertEqual(wsAppLink.mode, .invalidFormat)
        XCTAssertTrue(wsAppLink.hasBlockingIssues)

        let wsScheme = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(urlSchemes: [" openvision\n"])
        )
        XCTAssertEqual(wsScheme.mode, .invalidFormat)
        XCTAssertTrue(wsScheme.hasBlockingIssues)

        let emptyFirstScheme = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(urlSchemes: ["", "openvision"])
        )
        XCTAssertEqual(emptyFirstScheme.mode, .invalidFormat)
        XCTAssertTrue(emptyFirstScheme.hasBlockingIssues)

        let wsTeam = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(teamID: " Q9W8E7R6T5\n")
        )
        XCTAssertEqual(wsTeam.mode, .invalidFormat)
        XCTAssertEqual(wsTeam.teamIDState, .invalid)
        XCTAssertFalse(wsTeam.logSummary.contains("Q9W8E7R6T5"))

        let wsToken = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(
                metaAppID: "123456789",
                clientToken: " AR|123456789|SECRET_WS_VAL\n",
                teamID: "AB12CD34EF",
                appLinkURLScheme: "https://example.com/dat"
            )
        )
        XCTAssertEqual(wsToken.mode, .invalidFormat)
        XCTAssertEqual(wsToken.clientTokenState, .invalid)
        XCTAssertFalse(wsToken.logSummary.contains("SECRET_WS_VAL"))
    }

    func testNonStringMetaAppIDClassifiedAsInvalidNotMissing() {
        var info = makeInfoDictionary()
        var mwdat = info["MWDAT"] as! [String: Any]
        mwdat["MetaAppID"] = 0
        info["MWDAT"] = mwdat

        let nonStringReport = MWDATConfigurationValidator.inspect(infoDictionary: info)
        XCTAssertEqual(nonStringReport.metaAppIDState, .invalid)
        XCTAssertEqual(nonStringReport.mode, .invalidFormat)
        XCTAssertTrue(nonStringReport.hasBlockingIssues)

        let missingReport = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(metaAppID: nil)
        )
        XCTAssertEqual(missingReport.metaAppIDState, .missing)
        XCTAssertEqual(missingReport.mode, .invalidFormat)
        XCTAssertTrue(missingReport.hasBlockingIssues)
    }

    func testUITeamIDLabelDistinguishesMissingVsEmptyInDeveloperMode() {
        let omittedReport = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(metaAppID: "0", clientToken: "", teamID: nil)
        )
        XCTAssertEqual(omittedReport.teamIDState, .missing)
        XCTAssertEqual(omittedReport.uiTeamIDLabel, "Đã bỏ qua (Developer Mode)")

        let emptyReport = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(metaAppID: "0", clientToken: "", teamID: "")
        )
        XCTAssertEqual(emptyReport.teamIDState, .empty)
        XCTAssertEqual(emptyReport.uiTeamIDLabel, "Trống (Developer Mode)")

        let configuredReport = MWDATConfigurationValidator.inspect(
            infoDictionary: makeInfoDictionary(metaAppID: "0", clientToken: "", teamID: "AB12CD34EF")
        )
        XCTAssertEqual(configuredReport.teamIDState, .configured)
        XCTAssertEqual(configuredReport.uiTeamIDLabel, "Đã đặt")
    }

    func testShouldForwardToWearablesSDKAndRedactedURLSummary() {
        let registered = ["openvision"]

        let withAction = URL(string: "openvision://callback?metaWearablesAction=register&secret=TOP_SECRET_VAL")!
        let universalWithAction = URL(string: "https://example.com/dat?metaWearablesAction=permission&token=SECRET_2")!
        let registeredNoAction = URL(string: "openvision://callback?error=user_cancelled&code=42")!
        let unrelatedScheme = URL(string: "otherapp://callback?secret=TOP_SECRET_VAL")!
        let unrelatedWeb = URL(string: "https://example.com/page?token=SECRET_3")!

        XCTAssertTrue(MWDATConfigurationValidator.shouldForwardToWearablesSDK(withAction, registeredSchemes: registered))
        XCTAssertTrue(MWDATConfigurationValidator.shouldForwardToWearablesSDK(universalWithAction, registeredSchemes: registered))
        XCTAssertTrue(MWDATConfigurationValidator.shouldForwardToWearablesSDK(registeredNoAction, registeredSchemes: registered))
        XCTAssertFalse(MWDATConfigurationValidator.shouldForwardToWearablesSDK(unrelatedScheme, registeredSchemes: registered))
        XCTAssertFalse(MWDATConfigurationValidator.shouldForwardToWearablesSDK(unrelatedWeb, registeredSchemes: ["openvision", "https"]))

        let summary = MWDATConfigurationValidator.redactedURLSummary(withAction)
        XCTAssertEqual(summary, "scheme=openvision, hasMetaWearablesAction=true, queryKeys=[metaWearablesAction,secret]")
        XCTAssertFalse(summary.contains("TOP_SECRET_VAL"))
        XCTAssertFalse(summary.contains("register"))

        let errorSummary = MWDATConfigurationValidator.redactedURLSummary(registeredNoAction)
        XCTAssertEqual(errorSummary, "scheme=openvision, hasMetaWearablesAction=false, queryKeys=[code,error]")
        XCTAssertFalse(errorSummary.contains("user_cancelled"))
        XCTAssertFalse(errorSummary.contains("42"))
    }

    func testHostAppBundleHasValidNonPlaceholderMWDATConfiguration() {
        // OpenVisionTests uses TEST_HOST = OpenVision.app, so Bundle.main is the built app bundle.
        guard let info = Bundle.main.infoDictionary, info["MWDAT"] != nil else {
            XCTFail("Expected OpenVision.app host bundle Info.plist to include MWDAT")
            return
        }
        let report = MWDATConfigurationValidator.inspect(infoDictionary: info)
        XCTAssertNotEqual(report.mode, .invalidPlaceholder, "Built app contains placeholder MWDAT keys: \(report.logSummary)")
        XCTAssertTrue(
            report.mode == .developer || report.mode == .production,
            "Expected built app MWDAT mode to be developer or production: \(report.logSummary)"
        )
        XCTAssertFalse(
            report.hasBlockingIssues,
            "Built app has blocking MWDAT issues: \(report.issues.joined(separator: " | "))"
        )
        XCTAssertTrue(report.hasMetaAIQueryScheme, "Host app must declare fb-viewapp in LSApplicationQueriesSchemes")
        XCTAssertTrue(report.hasBluetoothClassic, "Host app must keep Bluetooth Classic keys (PLAN.md D2)")
    }
}
