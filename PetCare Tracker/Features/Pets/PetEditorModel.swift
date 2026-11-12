import Foundation
import Observation
import PhotosUI
import SwiftUI

@MainActor @Observable final class PetEditorModel {
    var draft: PetDraft
    var error: String?
    var isLoadingPhoto = false
    var previewData: Data?
    private var photoLoadID = UUID()
    let pet: Pet?
    static let species = ["Dog", "Cat", "Bird", "Rabbit", "Hamster", "Guinea pig", "Fish", "Turtle", "Reptile", "Horse", "Ferret", "Other"]
    /// The picker choice; "Other" combined with `customSpecies` stores the owner's own text.
    var speciesChoice: String
    var customSpecies: String
    init(pet: Pet?) {
        let draft = pet.map(PetDraft.init) ?? PetDraft()
        let known = Self.species.contains(draft.species)
        self.pet = pet; self.draft = draft
        speciesChoice = known ? draft.species : "Other"
        customSpecies = known ? "" : draft.species
    }
    /// Contact details saved while premium was active stay editable afterwards.
    var hasSavedVeterinarian: Bool {
        pet.map { !$0.vetName.isEmpty || !$0.vetPhone.isEmpty || !$0.vetAddress.isEmpty } ?? false
    }
    func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let loadID = UUID(); photoLoadID = loadID
        isLoadingPhoto = true; error = nil
        defer { if photoLoadID == loadID { isLoadingPhoto = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw CareError.photo }
            guard !Task.isCancelled, photoLoadID == loadID else { return }
            draft.photoData = data; draft.removePhoto = false; previewData = data
        } catch { self.error = CareError.photo.localizedDescription }
    }
    func save(using services: AppServices) -> Bool {
        let custom = customSpecies.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.species = speciesChoice == "Other" && !custom.isEmpty ? custom : speciesChoice
        do { try services.store.savePet(draft, pet: pet, premium: services.premium.isPremium); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}
