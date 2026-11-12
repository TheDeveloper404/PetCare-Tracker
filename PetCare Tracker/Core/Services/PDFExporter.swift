import Foundation
import UIKit

struct PDFHealthSnapshot {
    let name: String
    let identification: [String]
    let sections: [(String, [String])]
}

enum PDFExporter {
    @MainActor static func snapshot(pet: Pet, unit: WeightUnit) -> PDFHealthSnapshot {
        var identity = [L10n.text(pet.species)]
        if !pet.breed.isEmpty { identity.append(L10n.text("Breed") + ": " + pet.breed) }
        if let birth = pet.birthDay.flatMap({ CalendarDay(iso: $0) }) { identity.append(L10n.text("Date of birth") + ": " + birth.date().formatted(date: .abbreviated, time: .omitted)) }
        if !pet.sex.isEmpty { identity.append(L10n.text("Sex") + ": " + L10n.text(pet.sex)) }
        if !pet.microchip.isEmpty { identity.append(L10n.text("Microchip") + ": " + pet.microchip) }
        let veterinarian = [pet.vetName, pet.vetPhone, pet.vetAddress].filter { !$0.isEmpty }
        if !veterinarian.isEmpty { identity.append(L10n.text("Veterinarian") + ": " + veterinarian.joined(separator: ", ")) }
        var sections: [(String, [String])] = []
        for category in RecordCategory.allCases {
            let rows = pet.records.filter { $0.category == category }.sorted { $0.day < $1.day }.map { record in
                let date = record.appointmentAt?.formatted(date: .abbreviated, time: .shortened)
                    ?? CalendarDay(iso: record.day)?.date().formatted(date: .abbreviated, time: .omitted) ?? record.day
                return date + " — " + record.title + (record.notes.isEmpty ? "" : "\n" + record.notes)
            }
            if !rows.isEmpty { sections.append((category.title, rows)) }
        }
        if !pet.weights.isEmpty {
            sections.append((L10n.text("Weight history"), pet.weights.sorted { $0.day < $1.day }.map {
                let date = CalendarDay(iso: $0.day)?.date().formatted(date: .abbreviated, time: .omitted) ?? $0.day
                return date + " — " + unit.display($0.kilograms).formatted(.number.precision(.fractionLength(0...2))) + " " + unit.rawValue + ($0.notes.isEmpty ? "" : "\n" + $0.notes)
            }))
        }
        if !pet.notes.isEmpty { sections.append((L10n.text("Notes"), [pet.notes])) }
        return PDFHealthSnapshot(name: pet.name, identification: identity, sections: sections)
    }
    @MainActor static func export(pet: Pet, unit: WeightUnit, premium: Bool) async throws -> URL {
        guard premium else { throw CareError.premiumRequired }
        let value = snapshot(pet: pet, unit: unit)
        return try ExportFiles.write(render(value), extension: "pdf")
    }
    @MainActor static func render(_ snapshot: PDFHealthSnapshot) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            var y: CGFloat = 56
            var pageNumber = 0
            func beginPage() {
                context.beginPage(); pageNumber += 1; y = 56
                let footer = L10n.text("Owner-maintained records. Not a certified veterinary document.") + " · " + String(pageNumber)
                footer.draw(in: CGRect(x: 44, y: 800, width: 507, height: 28), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
            }
            func line(_ text: String, font: UIFont, gap: CGFloat = 8) {
                // Render line fragments independently, including very long notes that span pages.
                let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.black])
                let storage = NSTextStorage(attributedString: attributed)
                let layout = NSLayoutManager()
                let container = NSTextContainer(size: CGSize(width: 507, height: CGFloat.greatestFiniteMagnitude))
                container.lineFragmentPadding = 0; layout.addTextContainer(container); storage.addLayoutManager(layout)
                layout.ensureLayout(for: container)
                let range = layout.glyphRange(for: container)
                layout.enumerateLineFragments(forGlyphRange: range) { _, used, _, glyphs, _ in
                    if y + used.height > 772 { beginPage() }
                    let characterRange = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                    let fragment = attributed.attributedSubstring(from: characterRange)
                    fragment.draw(in: CGRect(x: 44, y: y, width: 507, height: used.height + 2))
                    y += used.height
                }
                y += gap
            }
            beginPage()
            line(L10n.text("Pet health history"), font: .boldSystemFont(ofSize: 24), gap: 16)
            line(snapshot.name, font: .boldSystemFont(ofSize: 18))
            for text in snapshot.identification { line(text, font: .systemFont(ofSize: 11)) }
            y += 12
            for (title, rows) in snapshot.sections {
                if y + 64 > 772 { beginPage() }
                line(title, font: .boldSystemFont(ofSize: 15), gap: 12)
                for text in rows { line(text, font: .systemFont(ofSize: 11), gap: 12) }
                y += 8
            }
        }
    }
}
