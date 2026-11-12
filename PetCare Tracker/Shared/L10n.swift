import Foundation

nonisolated enum L10n {
    static func text(_ key: String) -> String {
        let language = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        if language != "system", let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}

nonisolated enum CareError: String, LocalizedError, Sendable {
    case nameRequired = "Enter a name."
    case titleRequired = "Enter a title."
    case invalidDate = "Choose a valid date."
    case invalidWeight = "Enter a weight greater than zero."
    case premiumRequired = "Premium is required to add another pet or export a PDF."
    case importPremiumRequired = "Premium is required to import more than one pet profile."
    case persistence = "Your changes could not be saved. Your previous data is unchanged. Please try again."
    case photo = "The photo could not be loaded or saved. Please choose another photo."
    case backup = "The backup is invalid or unsupported. No existing data was changed."
    case backupTooLarge = "Backups must be 64 MB or smaller."
    case export = "The file could not be created. Please try again."
    case purchaseUnavailable = "Purchases are unavailable. Please try again later."
    case verification = "The purchase could not be verified. Please try restoring purchases."
    var errorDescription: String? { L10n.text(rawValue) }
}
