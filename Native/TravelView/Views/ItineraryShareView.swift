import SwiftUI
import TravelCore

/// The preview and ShareLink use the same text; Save freezes that text for the file picker.
struct ItineraryShareView: View {
    let store: TripStore
    let tripID: String
    @State private var options = ItineraryTextOptions()
    @State private var exporting = false
    @State private var document = ItineraryTextDocument(text: "")
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let trip = store.trips.first(where: { $0.id == tripID }) {
                    let text = ItineraryText.make(trip: trip, items: store.items(for: tripID), options: options)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Choose what to include").font(.headline).accessibilityAddTraits(.isHeader)
                                Toggle("Include notes", isOn: $options.includeNotes)
                                    .accessibilityIdentifier("share-include-notes")
                                Toggle("Include booking references", isOn: $options.includeReferences)
                                    .accessibilityIdentifier("share-include-references")
                                Text("Notes and references start off. Review the preview before sharing or saving.")
                                    .font(.caption).foregroundStyle(TravelTheme.secondary)
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 12) { actions(text: text) }
                                    VStack(alignment: .leading, spacing: 12) { actions(text: text) }
                                }
                            }.tripPanel()
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Preview").font(.headline).accessibilityAddTraits(.isHeader)
                                Text(text).font(.body).foregroundStyle(TravelTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                    .accessibilityIdentifier("shared-itinerary-preview")
                            }.tripPanel()
                        }
                        .padding(20)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ContentUnavailableView("This trip is no longer available", systemImage: "suitcase.rolling")
                }
            }
            .background(TravelTheme.background)
            .navigationTitle("Share itinerary")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .plainText,
                      defaultFilename: "Travel View Itinerary") { result in
            if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                self.error = error.localizedDescription
            }
        }
        .alert("Couldn’t save itinerary", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 680, minHeight: 600, idealHeight: 760)
        #endif
    }

    @ViewBuilder private func actions(text: String) -> some View {
        ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("share-itinerary-text")
        Button("Save text file", systemImage: "doc.badge.arrow.up") {
            document = ItineraryTextDocument(text: text)
            exporting = true
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("save-itinerary-text")
    }
}
