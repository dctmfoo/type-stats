import Foundation
import XCTest
@testable import TypeStatsCore

@MainActor
final class AppUpdateTests: XCTestCase {
    private final class Service: AppUpdateService {
        var version = AppVersion("0.2.0")!
        var failure: Error?
        var checks = 0
        var upgrades = 0
        func latestVersion() async throws -> AppVersion {
            checks += 1
            if let failure { throw failure }
            return version
        }
        func upgrade(to version: AppVersion) async throws {
            upgrades += 1
            if let failure { throw failure }
        }
    }

    func testNumericVersionsAndCaskParsing() {
        XCTAssertGreaterThan(AppVersion("0.10.0")!, AppVersion("0.9.9")!)
        XCTAssertGreaterThan(AppVersion("20261009.1")!, AppVersion("20261008.1")!)
        XCTAssertEqual(AppVersion("1.2"), AppVersion("1.2.0"))
        for invalid in ["", "1", "v1.2.3", "1..2", "1.2.beta", "1.2.3.4", "１.２"] {
            XCTAssertNil(AppVersion(invalid), invalid)
        }
        XCTAssertEqual(AppVersion.published(in: "cask \"type-stats\" do\n  version \"0.2.0\"\nend"), AppVersion("0.2.0"))
        XCTAssertNil(AppVersion.published(in: "# version \"9.9.9\""))
        XCTAssertNil(AppVersion.published(in: "version \"latest\""))
    }

    func testFooterDialogAndActionAgreeForEachVersionState() async {
        let service = Service()
        let update = AppUpdate(currentVersion: "0.2.0", service: service)
        XCTAssertEqual(update.footerLabel, "Version 0.2.0")
        XCTAssertEqual(update.status, "Check for the latest Homebrew release.")
        await update.check()
        XCTAssertFalse(update.updateAvailable)
        XCTAssertEqual(update.buttonLabel, "Check for Updates")
        XCTAssertEqual(update.status, "You're using the latest release.")
        await update.update()
        XCTAssertEqual(service.upgrades, 0)
        service.version = AppVersion("0.3.0")!
        await update.check()
        XCTAssertEqual(update.footerLabel, "Update available")
        XCTAssertEqual(update.buttonLabel, "Update from Homebrew")
        await update.update()
        XCTAssertEqual(service.upgrades, 1)
        XCTAssertFalse(update.isUpdating)
        service.version = AppVersion("0.1.0")!
        await update.check()
        XCTAssertFalse(update.updateAvailable)
        XCTAssertEqual(update.status, "This version is newer than the Homebrew release.")
    }

    func testFailuresRemainVisibleAndCanBeRetried() async {
        let service = Service()
        let update = AppUpdate(currentVersion: "0.1.0", service: service)
        await update.check()
        service.failure = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "network unavailable"])
        await update.update()
        XCTAssertTrue(update.error?.contains("network unavailable") == true)
        XCTAssertTrue(update.updateAvailable)
        XCTAssertFalse(update.isUpdating)
        await update.check()
        XCTAssertNil(update.latest)
        XCTAssertTrue(update.error?.contains("Could not check") == true)
        XCTAssertFalse(update.isChecking)
        service.failure = nil
        await update.check()
        XCTAssertNil(update.error)
        XCTAssertTrue(update.updateAvailable)
    }

    func testPopupChecksAreThrottledButManualCheckIsFresh() async {
        let service = Service()
        let update = AppUpdate(currentVersion: "0.1.0", service: service)
        await update.checkIfNeeded()
        await update.checkIfNeeded()
        XCTAssertEqual(service.checks, 1)
        await update.check()
        XCTAssertEqual(service.checks, 2)
    }
}
