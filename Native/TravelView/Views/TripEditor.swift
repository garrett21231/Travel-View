import SwiftUI
import TravelCore

/// Form values stay local until the repository successfully commits the save.
struct TripEditor: View {
    let store: TripStore
    let onSaved: (Trip) -> Void
    @State private var tripID: String
    private let isEditing: Bool
    private let initial: Draft
    @State private var draft: Draft
    @State private var showDiscard = false
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, destinations, budget, notes }

    private struct Draft: Equatable {
        var name = ""
        var destinations = ""
        var hasDates = true
        var start = TravelDay().date()
        var end = Calendar.current.date(byAdding: .day, value: 1, to: TravelDay().date())!
        var travelers = 1
        var budget = ""
        var notes = ""

        init(trip: Trip?) {
            if let trip {
                name = trip.name
                destinations = trip.destinations.joined(separator: "\n")
                hasDates = trip.start != nil
                start = trip.start?.date() ?? start
                end = trip.end?.date() ?? end
                travelers = trip.plannedTravelers
                budget = Money.editable(trip.budgetCents)
                notes = trip.notes
            }
        }

        func input() throws -> TripInput {
            TripInput(name: name, destinations: destinations.components(separatedBy: .newlines),
                      start: hasDates ? TravelDay(start) : nil, end: hasDates ? TravelDay(end) : nil,
                      plannedTravelers: travelers, budgetCents: try Money.parse(budget), notes: notes)
        }
    }

    init(store: TripStore, trip: Trip? = nil, onSaved: @escaping (Trip) -> Void) {
        self.store = store
        self.onSaved = onSaved
        _tripID = State(initialValue: trip?.id ?? UUID().uuidString)
        isEditing = trip != nil
        let draft = Draft(trip: trip)
        initial = draft
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip details") {
                    TextField("Trip name", text: $draft.name)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("trip-name")
                    TextField("Destinations, one per line", text: $draft.destinations, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focusedField, equals: .destinations)
                        .accessibilityIdentifier("trip-destinations")
                }

                Section {
                    Toggle("Add dates", isOn: $draft.hasDates)
                    if draft.hasDates {
                        DatePicker("Departure", selection: $draft.start, displayedComponents: .date)
                        DatePicker("Return", selection: $draft.end, in: draft.start..., displayedComponents: .date)
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    Text("You can leave dates open while you plan.")
                }

                Section("Travelers & budget") {
                    Stepper("\(draft.travelers) \(draft.travelers == 1 ? "traveler" : "travelers") planned",
                            value: $draft.travelers, in: 1...999)
                    TextField("Budget in USD (optional)", text: $draft.budget)
                        .focused($focusedField, equals: .budget)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                Section("Notes") {
                    TextField("Anything you want to remember", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...7)
                        .focused($focusedField, equals: .notes)
                        .accessibilityIdentifier("trip-notes")
                }

                Section {
                    Button(action: save) {
                        HStack {
                            if store.isWorking { ProgressView() }
                            Text(isEditing ? "Save changes" : "Save trip").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("save-trip")
                } footer: {
                    Text("Saved on this device. You can export your trips from the collection menu.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(TravelTheme.background)
            .disabled(store.isWorking)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit trip" : "New trip")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
                        if draft != initial { showDiscard = true } else { dismiss() }
                    }
                    .disabled(store.isWorking)
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done", systemImage: "checkmark") { focusedField = nil }
                }
                #endif
            }
            .onChange(of: draft.start) { _, start in
                if draft.end < start { draft.end = start }
            }
        }
        .interactiveDismissDisabled(draft != initial || store.isWorking)
        .confirmationDialog("Discard your changes?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .alert("Couldn’t save trip", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 560, idealHeight: 650)
        #endif
    }

    private func save() {
        focusedField = nil
        Task {
            do {
                let input = try draft.input()
                let saved = try await store.save(input, id: tripID)
                onSaved(saved)
                dismiss()
            } catch { saveError = error.localizedDescription }
        }
    }
}
