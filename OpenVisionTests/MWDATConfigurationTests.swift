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
