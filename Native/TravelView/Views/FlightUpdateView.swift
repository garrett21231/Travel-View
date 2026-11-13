import SwiftUI
import TravelCore

/// Checking a schedule is read-only until the user saves the explicitly selected changes.
struct FlightUpdateView: View {
    let store: TripStore
    let item: ItineraryItem
    @State private var review: FlightUpdate?
    @State private var selection: Set<FlightUpdate.Field> = []
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let review {
                reviewForm(review)
            } else if let flight = item.flight, let day = item.start {
                FlightLookupView(number: flight.number, day: day, reviewingUpdate: true) { schedule, _ in
                    do {
                        let review = try FlightUpdate(item: item, schedule: schedule)
                        selection = review.defaultSelection
                        self.review = review
                    } catch { self.error = error.localizedDescription }
                }
            } else {
                ContentUnavailableView("Add a departure date", systemImage: "calendar",
                                       description: Text("Edit the flight and add its departure date before checking for updates."))
            }
        }
        .interactiveDismissDisabled(store.isWorking)
        .alert("Couldn’t update flight", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        #if os(macOS)
        .frame(minWidth: 490, idealWidth: 560, minHeight: 580, idealHeight: 720)
        #endif
    }

    private func reviewForm(_ review: FlightUpdate) -> some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.title).font(.headline)
                    Text("\(review.schedule.number) · \(review.schedule.departure.airport) → \(review.schedule.arrival.airport)")
                    Text("\(review.schedule.provider) · \(review.schedule.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(TravelTheme.secondary)
                    Button("Choose another result") { self.review = nil; selection = [] }
                        .buttonStyle(.borderless)
                } header: { Text("Latest lookup") } footer: {
                    Text("All schedule times are local to each airport. A lookup is a dated snapshot, and may have incomplete details.")
                }
                Section {
                    if review.changes.isEmpty {
                        Text("No new schedule details to apply. You can save the lookup date below.")
                    }
                    ForEach(review.changes) { change in
                        Toggle(isOn: Binding(get: { selection.contains(change.field) }, set: { value in
                            if value { selection.insert(change.field) } else { selection.remove(change.field) }
                        })) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(change.field.title).fontWeight(.semibold)
                                Text("Saved: \(change.saved)").foregroundStyle(TravelTheme.secondary)
                                Text("Latest: \(change.latest)")
                                if change.differsFromLookup {
                                    Text("Your saved value differs from the previous lookup. Select to replace it.")
                                        .font(.caption).foregroundStyle(TravelTheme.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityLabel(change.field.title)
                        .accessibilityHint("Saved: \(change.saved). Latest: \(change.latest)." + (change.differsFromLookup ? " Your saved value differs from the previous lookup." : ""))
                        .accessibilityIdentifier("flight-update-\(change.field.rawValue)")
                    }
                } header: { Text("Choose changes to apply") } footer: {
                    Text(review.hasComparableLookup ? "Details that differ from the previous lookup stay unchecked. Your title, notes and booking reference are kept." : "There is no matching earlier lookup to compare. Choose the details you want to replace. Your title, notes and booking reference are kept.")
                }
                Section {
                    Button {
                        Task {
                            do {
                                try await store.applyFlightUpdate(review, selection: selection)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        HStack {
                            if store.isWorking { ProgressView() }
                            Text(selection.isEmpty ? "Save lookup only" : "Save selected changes").fontWeight(.semibold)
                        }.frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("save-flight-update")
                } footer: {
                    Text("With no changes selected, only the dated lookup is saved.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(TravelTheme.background)
            .disabled(store.isWorking)
            .navigationTitle("Review flight changes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isWorking) }
            }
        }
    }
}
