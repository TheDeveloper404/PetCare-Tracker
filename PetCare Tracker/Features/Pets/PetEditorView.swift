import SwiftUI
import PhotosUI

struct PetEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var model: PetEditorModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var paywall = false
    init(pet: Pet? = nil) { _model = State(initialValue: PetEditorModel(pet: pet)) }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $model.draft.name).textContentType(.name).accessibilityIdentifier("petName")
                    Picker("Species", selection: $model.speciesChoice) {
                        ForEach(PetEditorModel.species, id: \.self) { Text(L10n.text($0)).tag($0) }
                    }.accessibilityIdentifier("petSpecies")
                    if model.speciesChoice == "Other" {
                        TextField("Species name (optional)", text: $model.customSpecies).accessibilityIdentifier("customSpecies")
                    }
                    TextField("Breed (optional)", text: $model.draft.breed)
                    Toggle("Add date of birth", isOn: Binding(get: { model.draft.birthDay != nil },
                        set: { model.draft.birthDay = $0 ? CalendarDay(Date()).iso : nil }))
                    if model.draft.birthDay != nil {
                        DayPicker(title: "Date of birth", iso: Binding(get: { model.draft.birthDay ?? CalendarDay(Date()).iso },
                                                                    set: { model.draft.birthDay = $0 }))
                    }
                    Picker("Sex (optional)", selection: $model.draft.sex) {
                        ForEach(["", "Female", "Male"], id: \.self) { Text(L10n.text($0.isEmpty ? "Not specified" : $0)).tag($0) }
                    }
                    TextField("Microchip (optional)", text: $model.draft.microchip).textInputAutocapitalization(.never)
                }
                Section("Veterinarian") {
                    if services.premium.isPremium || model.hasSavedVeterinarian {
                        TextField("Clinic or veterinarian name", text: $model.draft.vetName).accessibilityIdentifier("vetName")
                        TextField("Phone", text: $model.draft.vetPhone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                            .accessibilityIdentifier("vetPhone")
                        TextField("Address", text: $model.draft.vetAddress, axis: .vertical).textContentType(.fullStreetAddress)
                    } else {
                        Button("Add veterinarian contact with premium", systemImage: "cross.case") { paywall = true }
                            .disabled(services.premium.isRefreshing).accessibilityIdentifier("vetLocked")
                    }
                }
                Section("Photo") {
                    if let data = model.previewData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160).accessibilityLabel("Selected pet photo")
                    } else if let pet = model.pet, !model.draft.removePhoto { PetAvatar(pet: pet, photos: services.store.photos, size: 80) }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Choose photo", systemImage: "photo") }
                    if model.isLoadingPhoto { ProgressView("Loading photo") }
                    if model.draft.photoData != nil || (model.pet?.photoName != nil && !model.draft.removePhoto) {
                        Button("Remove photo", role: .destructive) {
                            model.draft.photoData = nil; model.previewData = nil; model.draft.removePhoto = true
                        }.disabled(model.isLoadingPhoto)
                    }
                }
                Section("Notes") { TextField("Notes", text: $model.draft.notes, axis: .vertical).lineLimit(3...8) }
                if model.error != nil { Section { InlineError(message: model.error) } }
            }
            .navigationTitle(L10n.text(model.pet == nil ? "Add pet" : "Edit pet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if model.save(using: services) { dismiss() } }
                        .disabled(model.isLoadingPhoto || services.premium.isRefreshing)
                        .accessibilityIdentifier("savePet")
                }
            }
            .task(id: selectedPhoto) { await model.loadPhoto(selectedPhoto) }
            .sheet(isPresented: $paywall) { PremiumView() }
        }
    }
}
