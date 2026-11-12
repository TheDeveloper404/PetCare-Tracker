import XCTest

@MainActor final class PetCareTrackerUITests: XCTestCase {
    let appID = ProcessInfo.processInfo.environment["PETCARE_APP_BUNDLE_ID"] ?? "ro.acl-smartsoftware.petcaretracker"
    func launch(reset: Bool = true, language: String = "en", premium: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: appID)
        app.launchArguments = ["--ui-testing", "-hasCompletedOnboarding", "YES", "-appLanguage", language, "-AppleLanguages", "(\(language))"]
        if reset { app.launchArguments.append("--reset-ui-testing") }
        if premium { app.launchArguments.append("--ui-testing-premium") }
        app.launch()
        return app
    }
    func addPet(_ app: XCUIApplication, name: String) {
        app.tabBars.buttons["Pets"].tap()
        app.buttons["addPet"].tap()
        let field = app.textFields["petName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(name)
        let save = app.buttons["savePet"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 5))
    }
    // "Users can manage pet profiles." / "Users can maintain care and health records."
    func testPetRecordPersistenceAndConfirmedDeletion() {
        continueAfterFailure = false
        var app = launch()
        addPet(app, name: "Milo")
        app.staticTexts["Milo"].firstMatch.tap()
        app.buttons["addRecord"].tap()
        let title = app.textFields["recordTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Annual vaccination")
        app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.staticTexts["Annual vaccination"].waitForExistence(timeout: 5))
        let history = XCTAttachment(screenshot: app.screenshot())
        history.name = "Pet health history"; history.lifetime = .keepAlways; add(history)
        app.terminate()
        app = launch(reset: false)
        app.tabBars.buttons["Pets"].tap()
        app.staticTexts["Milo"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Annual vaccination"].waitForExistence(timeout: 5))
        app.buttons["editPet"].tap()
        let name = app.textFields["petName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText(" updated")
        app.buttons["savePet"].tap()
        XCTAssertTrue(app.navigationBars["Milo updated"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["Delete pet"].tap()
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.2)).tap() }
        XCTAssertEqual(app.buttons.matching(identifier: "Delete pet").count, 1)
        XCTAssertTrue(app.navigationBars["Milo updated"].exists)
        app.buttons["Delete pet"].tap()
        let confirmation = app.popovers.buttons["Delete pet"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(app.staticTexts["Meet your care companion"].waitForExistence(timeout: 5))
        app.terminate()
    }

    // "The dashboard should show: ... Quick actions"
    func testDashboardQuickActionsSaveForTheSelectedPet() {
        continueAfterFailure = false
        let app = launch()
        addPet(app, name: "Milo")
        app.tabBars.buttons["Today"].tap()
        app.buttons["dashboardAddRecord"].tap()
        let title = app.textFields["recordTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Dashboard vaccination")
        app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.buttons["dashboardAddReminder"].tap()
        let reminder = app.textFields["reminderTitle"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        reminder.tap(); reminder.typeText("Dashboard care")
        app.swipeUp()
        let enabled = app.switches["Enabled"]
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(enabled.value as? String, "0")
        app.buttons["saveReminder"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.buttons["dashboardAddWeight"].tap()
        let weight = app.textFields["weightValue"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.tap(); weight.typeText("4.7")
        XCTAssertEqual(weight.value as? String, "4.7")
        app.buttons["Save"].tap()
        app.tabBars.buttons["Pets"].tap()
        app.staticTexts["Milo"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Dashboard vaccination"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["4.7 kg"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Dashboard care"].exists)
        app.terminate()
    }

    // "Allow users to: Add records Edit records Delete records Filter by category"
    func testRecordFilteringEditingAndConfirmedDeletion() {
        continueAfterFailure = false
        var app = launch()
        addPet(app, name: "Milo")
        app.staticTexts["Milo"].firstMatch.tap()
        app.buttons["addRecord"].tap()
        var title = app.textFields["recordTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Annual vaccination")
        app.buttons["saveRecord"].tap()
        app.buttons["addRecord"].tap()
        app.buttons["recordCategory"].tap()
        app.buttons["Care note"].tap()
        title = app.textFields["recordTitle"]
        title.tap(); title.typeText("Grooming note")
        app.buttons["saveRecord"].tap()
        app.buttons["historyCategory"].tap()
        app.buttons["Care note"].tap()
        XCTAssertTrue(app.staticTexts["Grooming note"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Annual vaccination"].exists)
        app.buttons["historyCategory"].tap()
        app.buttons["All records"].tap()
        app.staticTexts["Annual vaccination"].tap()
        app.buttons["Edit record"].tap()
        title = app.textFields["recordTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText(" updated")
        app.buttons["saveRecord"].tap()
        XCTAssertTrue(app.navigationBars["Annual vaccination updated"].waitForExistence(timeout: 5))
        app.buttons["Delete record"].tap()
        app.popovers.buttons["Delete record"].tap()
        XCTAssertTrue(app.navigationBars["Milo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Annual vaccination updated"].exists)
        XCTAssertTrue(app.staticTexts["Grooming note"].exists)
        app.terminate()
        app = launch(reset: false)
        app.tabBars.buttons["Pets"].tap()
        app.staticTexts["Milo"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Grooming note"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Annual vaccination updated"].exists)
        app.terminate()
    }

    // "Profile photo (optional)" / "Users can create and manage multiple pet profiles."
    func testPhotoSelectionReplacementAndRemoval() {
        continueAfterFailure = false
        let app = launch()
        addPet(app, name: "Milo")
        app.staticTexts["Milo"].firstMatch.tap()
        app.buttons["editPet"].tap()
        app.buttons["Choose photo"].tap()
        let photos = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(photos.element(boundBy: 0).waitForExistence(timeout: 20), "Run scripts/verify.sh to seed the simulator photo fixtures.\n" + app.debugDescription)
        photos.element(boundBy: 0).tap()
        let preview = app.images["Selected pet photo"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), app.debugDescription)
        let firstPhoto = preview.screenshot().pngRepresentation
        app.buttons["savePet"].tap()
        XCTAssertTrue(app.navigationBars["Milo"].waitForExistence(timeout: 5))
        app.buttons["editPet"].tap()
        XCTAssertTrue(app.buttons["Remove photo"].waitForExistence(timeout: 5))
        app.buttons["Choose photo"].tap()
        XCTAssertTrue(photos.element(boundBy: 1).waitForExistence(timeout: 15))
        photos.element(boundBy: 1).tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertNotEqual(firstPhoto, preview.screenshot().pngRepresentation)
        app.buttons["savePet"].tap()
        app.terminate()
        let reopened = launch(reset: false)
        reopened.tabBars.buttons["Pets"].tap()
        reopened.staticTexts["Milo"].firstMatch.tap()
        reopened.buttons["editPet"].tap()
        XCTAssertTrue(reopened.buttons["Remove photo"].waitForExistence(timeout: 5))
        reopened.buttons["Remove photo"].tap()
        reopened.buttons["savePet"].tap()
        XCTAssertTrue(reopened.navigationBars["Milo"].waitForExistence(timeout: 5))
        reopened.buttons["editPet"].tap()
        XCTAssertFalse(reopened.buttons["Remove photo"].exists)
        reopened.terminate()
    }

    // "pauza mementourilor asociate la mutarea programarii (cu mesaj pentru revizuire)"
    func testMovingAppointmentShowsPausedReminderNotice() {
        continueAfterFailure = false
        let app = launch()
        addPet(app, name: "Milo")
        app.staticTexts["Milo"].firstMatch.tap()
        app.buttons["addRecord"].tap()
        app.buttons["recordCategory"].tap()
        app.buttons["Appointment"].tap()
        let title = app.textFields["recordTitle"]
        title.tap(); title.typeText("Vet appointment")
        app.buttons["saveRecord"].tap()
        app.staticTexts["Vet appointment"].tap()
        app.buttons["Add reminder"].tap()
        app.buttons["saveReminder"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.buttons["Edit record"].waitForExistence(timeout: 10))
        app.buttons["Edit record"].tap()
        app.datePickers["appointmentDate"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["DatePicker.NextMonth"].waitForExistence(timeout: 5))
        let calendar = Calendar(identifier: .gregorian)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date())!
        var components = calendar.dateComponents([.year, .month], from: nextMonth)
        components.day = 15
        let movedDate = calendar.date(from: components)!
        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US")
        dayFormat.dateFormat = "EEEE, d MMMM"
        app.buttons["DatePicker.NextMonth"].tap()
        let day = app.buttons[dayFormat.string(from: movedDate)]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        if app.buttons["PopoverDismissRegion"].exists { app.buttons["PopoverDismissRegion"].tap() }
        let month = movedDate.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "en_US")))
        XCTAssertTrue(app.datePickers["appointmentDate"].buttons.matching(NSPredicate(format: "label CONTAINS %@", month)).firstMatch.waitForExistence(timeout: 5))
        app.buttons["saveRecord"].tap()
        let notice = app.alerts["Associated reminders paused"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(notice.staticTexts["The appointment date changed. Open Reminders to review the dates and enable its reminders again."].exists)
        notice.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Inactive"].waitForExistence(timeout: 5))
        app.terminate()
        let reopened = launch(reset: false)
        reopened.tabBars.buttons["Reminders"].tap()
        XCTAssertTrue(reopened.staticTexts["Vet appointment"].waitForExistence(timeout: 5))
        XCTAssertTrue(reopened.staticTexts["Inactive"].exists)
        reopened.terminate()
    }

    // "Implement local data export and import/restore where practical."
    func testBackupExportAndImportFromSettings() {
        continueAfterFailure = false
        // Restoring next to an existing pet needs premium: free import cannot exceed one profile.
        let app = launch(premium: true)
        addPet(app, name: "Backup Milo")
        app.staticTexts["Backup Milo"].firstMatch.tap()
        app.buttons["addRecord"].tap()
        let title = app.textFields["recordTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Restored vaccination")
        app.buttons["saveRecord"].tap()
        app.tabBars.buttons["Settings"].tap()
        app.swipeUp()
        app.buttons["Export full backup"].tap()
        let saveToFiles = app.cells.matching(NSPredicate(format: "label == %@", "Save to Files")).firstMatch
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 10))
        let saveIcon = saveToFiles.images["activityImageView"]
        let saveReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: saveIcon)
        XCTAssertEqual(XCTWaiter.wait(for: [saveReady], timeout: 5), .completed)
        saveIcon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 15), app.debugDescription)
        let exportedName = filename.value as? String ?? ""
        XCTAssertFalse(exportedName.isEmpty)
        app.buttons["DOCPicker.actionButton"].tap()
        XCTAssertTrue(app.buttons["Import backup"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Pets"].tap()
        app.swipeUp()
        app.buttons["Delete pet"].tap()
        app.popovers.buttons["Delete pet"].tap()
        XCTAssertTrue(app.staticTexts["Meet your care companion"].waitForExistence(timeout: 5))
        addPet(app, name: "Local Luna")
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Import backup"].tap()
        let file = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", exportedName)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15), "Missing exported file \(exportedName)\n" + app.debugDescription)
        file.tap()
        let confirm = app.popovers.buttons["Import backup"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        confirm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let imported = app.staticTexts["Imported pets"]
        XCTAssertTrue(imported.waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["Pets"].tap()
        XCTAssertTrue(app.staticTexts["Backup Milo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Local Luna"].exists)
        app.tabBars.buttons["Today"].tap()
        app.buttons["dashboardAddRecord"].tap()
        let chosenPet = app.popovers.buttons["Local Luna"]
        XCTAssertTrue(chosenPet.waitForExistence(timeout: 5))
        chosenPet.tap()
        let chosenTitle = app.textFields["recordTitle"]
        XCTAssertTrue(chosenTitle.waitForExistence(timeout: 5))
        chosenTitle.tap(); chosenTitle.typeText("Local only")
        app.buttons["saveRecord"].tap()
        app.tabBars.buttons["Pets"].tap()
        app.staticTexts["Backup Milo"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Restored vaccination"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Local only"].exists)
        app.navigationBars.buttons["Pets"].tap()
        app.staticTexts["Local Luna"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Local only"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Restored vaccination"].exists)
        app.terminate()
    }

    // "English and Romanian localization work."
    func testRomanianProfileFlowAndSettings() {
        continueAfterFailure = false
        let app = launch(language: "ro")
        XCTAssertTrue(app.tabBars.buttons["Animale"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Animale"].tap()
        app.buttons["addPet"].tap()
        let field = app.textFields["petName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.placeholderValue, "Nume")
        field.tap(); field.typeText("Luna")
        app.buttons["savePet"].tap()
        XCTAssertTrue(app.staticTexts["Luna"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Câine"].exists)
        app.tabBars.buttons["Astăzi"].tap()
        app.buttons["dashboardAddWeight"].tap()
        let weight = app.textFields["weightValue"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.tap(); weight.typeText("4,7")
        XCTAssertEqual(weight.value as? String, "4,7")
        app.buttons["Salvează"].tap()
        app.tabBars.buttons["Animale"].tap()
        app.staticTexts["Luna"].firstMatch.tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["4,7 kg"].waitForExistence(timeout: 5), app.debugDescription)
        app.tabBars.buttons["Setări"].tap()
        XCTAssertTrue(app.navigationBars["Setări"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Preferințe"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Romanian settings"; image.lifetime = .keepAlways; add(image)
        app.terminate()
    }

    // "Search records; ... weight chart" (docs/PRODUCT_ROADMAP.md, Daily care improvements)
    // "Weight chart | Free: No (opens paywall) | Premium: Yes" (docs/APPLICATION.md)
    func testHistorySearchAndWeightChart() {
        continueAfterFailure = false
        let app = launch()
        addPet(app, name: "Milo")
        app.staticTexts["Milo"].firstMatch.tap()
        for name in ["Annual vaccination", "Grooming note"] {
            app.buttons["addRecord"].tap()
            let title = app.textFields["recordTitle"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            title.tap(); title.typeText(name)
            app.buttons["saveRecord"].tap()
        }
        // A category without records is a filter miss, not an empty history.
        app.buttons["historyCategory"].tap()
        app.buttons["Medication"].tap()
        XCTAssertTrue(app.staticTexts["No matching records."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No records yet. Add your first care record."].exists)
        app.buttons["historyCategory"].tap()
        app.buttons["All records"].tap()
        let search = app.searchFields["Search records"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("groom")
        XCTAssertTrue(app.staticTexts["Grooming note"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Annual vaccination"].exists)
        search.typeText("zzz")
        XCTAssertTrue(app.staticTexts["No matching records."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Grooming note"].exists)
        // The search bar's dismiss button is "Close" on current iOS and "Cancel" on older systems.
        (app.buttons["Close"].exists ? app.buttons["Close"] : app.buttons["Cancel"]).tap()
        XCTAssertTrue(app.staticTexts["Annual vaccination"].waitForExistence(timeout: 5))
        let chart = app.descendants(matching: .any)["weightChart"]
        for value in ["4.2", "4.5"] {
            XCTAssertFalse(chart.exists)
            app.buttons["Add weight"].tap()
            let weight = app.textFields["weightValue"]
            XCTAssertTrue(weight.waitForExistence(timeout: 5))
            weight.tap(); weight.typeText(value)
            app.buttons["Save"].tap()
            XCTAssertTrue(app.buttons["Add weight"].waitForExistence(timeout: 5))
        }
        // "Weight chart" is listed under "Included with premium": free shows the upgrade row instead.
        app.swipeUp()
        XCTAssertTrue(app.buttons["weightChartLocked"].waitForExistence(timeout: 5))
        XCTAssertFalse(chart.exists)
        app.terminate()
        let premium = launch(reset: false, premium: true)
        premium.tabBars.buttons["Pets"].tap()
        premium.staticTexts["Milo"].firstMatch.tap()
        XCTAssertTrue(premium.buttons["addRecord"].waitForExistence(timeout: 5))
        premium.swipeUp()
        XCTAssertTrue(premium.descendants(matching: .any)["weightChart"].waitForExistence(timeout: 5))
        XCTAssertFalse(premium.buttons["weightChartLocked"].exists)
        let image = XCTAttachment(screenshot: premium.screenshot())
        image.name = "Weight chart"; image.lifetime = .keepAlways; add(image)
        premium.terminate()
    }

    // "Species: a fixed list plus Other, where the owner can type their own species name." (docs/APPLICATION.md)
    func testListedAndCustomSpecies() {
        continueAfterFailure = false
        let app = launch()
        app.tabBars.buttons["Pets"].tap()
        app.buttons["addPet"].tap()
        let name = app.textFields["petName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Spike")
        XCTAssertFalse(app.textFields["customSpecies"].exists)
        app.buttons["petSpecies"].tap()
        XCTAssertTrue(app.buttons["Hamster"].waitForExistence(timeout: 5))
        app.buttons["Other"].tap()
        let custom = app.textFields["customSpecies"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.tap(); custom.typeText("Hedgehog")
        app.buttons["savePet"].tap()
        XCTAssertTrue(app.staticTexts["Hedgehog"].waitForExistence(timeout: 5))
        app.staticTexts["Spike"].firstMatch.tap()
        app.buttons["editPet"].tap()
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        XCTAssertEqual(custom.value as? String, "Hedgehog")
        app.buttons["petSpecies"].tap()
        app.buttons["Hamster"].tap()
        app.buttons["savePet"].tap()
        XCTAssertTrue(app.staticTexts["Hamster"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Hedgehog"].exists)
        app.terminate()
    }

    // "Custom reminder intervals | Free: No (opens paywall) | Premium: Yes" and
    // "Veterinarian contact | Free: No (opens paywall) | Premium: Yes" (docs/APPLICATION.md)
    func testVeterinarianContactAndCustomIntervalRequirePremium() {
        continueAfterFailure = false
        var app = launch()
        addPet(app, name: "Milo")
        app.staticTexts["Milo"].firstMatch.tap()
        app.buttons["editPet"].tap()
        XCTAssertTrue(app.buttons["vetLocked"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["vetName"].exists)
        app.buttons["Cancel"].tap()
        app.buttons["Add reminder"].tap()
        XCTAssertTrue(app.buttons["reminderRepeat"].waitForExistence(timeout: 5))
        app.buttons["reminderRepeat"].tap()
        app.buttons["Monthly"].tap()
        XCTAssertTrue(app.buttons["intervalLocked"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.steppers["reminderInterval"].exists)
        app.buttons["Cancel"].tap()
        app.terminate()

        app = launch(reset: false, premium: true)
        app.tabBars.buttons["Pets"].tap()
        app.staticTexts["Milo"].firstMatch.tap()
        app.buttons["editPet"].tap()
        let clinic = app.textFields["vetName"]
        XCTAssertTrue(clinic.waitForExistence(timeout: 5))
        clinic.tap(); clinic.typeText("Happy Paws")
        let phone = app.textFields["vetPhone"]
        phone.tap(); phone.typeText("0215550142")
        app.buttons["savePet"].tap()
        XCTAssertTrue(app.staticTexts["Happy Paws"].waitForExistence(timeout: 5))
        app.buttons["Add reminder"].tap()
        let title = app.textFields["reminderTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Flea treatment")
        app.buttons["reminderRepeat"].tap()
        app.buttons["Monthly"].tap()
        let increment = app.buttons["reminderInterval-Increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        increment.tap(); increment.tap()
        XCTAssertTrue(app.staticTexts["Every 3 months"].waitForExistence(timeout: 5))
        // Disabled so the system notification permission alert does not interrupt the flow.
        app.swipeUp()
        app.switches["Enabled"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["saveReminder"].tap()
        app.terminate()

        app = launch(reset: false, premium: true)
        app.tabBars.buttons["Pets"].tap()
        app.staticTexts["Milo"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Happy Paws"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.links["0215550142"].exists, app.debugDescription)
        app.tabBars.buttons["Reminders"].tap()
        XCTAssertTrue(app.staticTexts["Flea treatment"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Every 3 months"].exists)
        app.terminate()

        // "Values already saved stay visible and keep working" after premium is lost: still editable.
        app = launch(reset: false)
        app.tabBars.buttons["Pets"].tap()
        app.staticTexts["Milo"].firstMatch.tap()
        app.buttons["editPet"].tap()
        let savedClinic = app.textFields["vetName"]
        XCTAssertTrue(savedClinic.waitForExistence(timeout: 5))
        XCTAssertEqual(savedClinic.value as? String, "Happy Paws")
        XCTAssertFalse(app.buttons["vetLocked"].exists)
        app.terminate()
    }

    // "Persist reminder definitions independently from scheduled system notifications."
    func testWeightAndReminderRemainVisibleWithoutAlerts() {
        continueAfterFailure = false
        let app = launch()
        addPet(app, name: "Milo")
        app.staticTexts["Milo"].firstMatch.tap()
        app.buttons["Add weight"].tap()
        let weight = app.textFields["weightValue"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.tap(); weight.typeText("4.2")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Add reminder"].waitForExistence(timeout: 5))
        app.buttons["Add reminder"].tap()
        let title = app.textFields["reminderTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Custom care")
        app.swipeUp()
        let enabled = app.switches["Enabled"]
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(enabled.value as? String, "0")
        app.buttons["saveReminder"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Custom care"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Inactive"].exists)
        app.tabBars.buttons["Reminders"].tap()
        XCTAssertTrue(app.staticTexts["Custom care"].waitForExistence(timeout: 5))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Persisted reminder"; image.lifetime = .keepAlways; add(image)
        app.terminate()
    }
}

/// Produces App Store screenshots from sample data. Skipped unless PETCARE_SCREENSHOTS is set
/// (see docs/store/APP_STORE_LISTING.md); it is not a regression test.
@MainActor final class StoreScreenshots: XCTestCase {
    func testCaptureStoreScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PETCARE_SCREENSHOTS"] != nil)
        continueAfterFailure = false
        for language in ["en", "ro"] {
            let app = XCUIApplication(bundleIdentifier: ProcessInfo.processInfo.environment["PETCARE_APP_BUNDLE_ID"] ?? "ro.acl-smartsoftware.petcaretracker")
            app.launchArguments = ["--ui-testing", "--reset-ui-testing", "--ui-testing-premium", "--ui-testing-demo",
                                   "-hasCompletedOnboarding", "YES", "-appLanguage", language, "-AppleLanguages", "(\(language))"]
            app.launch()
            func capture(_ name: String) {
                Thread.sleep(forTimeInterval: 1)
                let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                image.name = language + "-" + name; image.lifetime = .keepAlways; add(image)
            }
            let tabs = app.tabBars.buttons
            XCTAssertTrue(app.staticTexts["Luna"].firstMatch.waitForExistence(timeout: 10))
            capture("1-today")
            tabs.element(boundBy: 1).tap()
            app.staticTexts["Luna"].firstMatch.tap()
            XCTAssertTrue(app.buttons["addRecord"].waitForExistence(timeout: 5))
            capture("2-pet")
            let chart = app.descendants(matching: .any)["weightChart"]
            for _ in 0..<4 where !chart.isHittable { app.swipeUp(velocity: .slow) }
            capture("3-weight")
            tabs.element(boundBy: 2).tap()
            capture("4-reminders")
            tabs.element(boundBy: 3).tap()
            capture("5-settings")
            app.terminate()
        }
    }
}
