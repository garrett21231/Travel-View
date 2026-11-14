import SwiftUI
import TravelCore

struct ChecklistSelection: Hashable { let tripID: String }

struct ChecklistSummaryView: View {
    let store: TripStore
    let tripID: String

    var body: some View {
        let items = store.checklistItems(for: tripID)
        let completed = items.filter(\.isCompleted).count
        VStack(alignment: .leading, spacing: 12) {
            Text("Checklist").font(.headline).accessibilityAddTraits(.isHeader)
            if items.isEmpty {
                Text("Keep packing and things to do before departure together.")
                    .font(.subheadline).foregroundStyle(TravelTheme.secondary)
            } else {
                Text("\(completed) of \(items.count) completed").font(.subheadline)
                    .accessibilityIdentifier("checklist-progress-count")
                ProgressView(value: Double(completed), total: Double(items.count))
                    .accessibilityLabel("Checklist progress")
                    .accessibilityValue("\(completed) of \(items.count) completed")
            }
            NavigationLink(value: ChecklistSelection(tripID: tripID)) {
                Label(items.isEmpty ? "Make a checklist" : "Open checklist", systemImage: "checklist")
            }.buttonStyle(.bordered).accessibilityIdentifier("open-trip-checklist")
        }.tripPanel()
    }
}

/// Completion changes are committed before the checkbox changes. Failed writes leave the row as it was.
struct TripChecklistView: View {
    let store: TripStore
    let tripID: String
    @State private var editor: EditorSelection?
    @State private var removing: ChecklistItem?
    @State private var error: String?

    private struct EditorSelection: Identifiable {
        let id = UUID()
        let item: ChecklistItem?
    }

    private var trip: Trip? { store.trips.first { $0.id == tripID } }

    var body: some View {
        let items = store.checklistItems(for: tripID)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let trip {
                    Text(trip.name).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    if items.isEmpty {
                        ContentUnavailableView {
                            Label("Your checklist starts here", systemImage: "checklist")
                        } description: {
                            Text("Add packing items or things to do before you go.")
                        } actions: { addButton }
                    } else {
                        Text("\(items.filter(\.isCompleted).count) of \(items.count) completed")
                            .font(.subheadline).foregroundStyle(TravelTheme.secondary)
                            .accessibilityIdentifier("checklist-completed-count")
                        LazyVStack(spacing: 12) {
                            ForEach(items) { item in checklistRow(item) }
                        }
                        Text("Tap an item to check it off. Use its menu to edit or remove it.")
                            .font(.caption).foregroundStyle(TravelTheme.secondary)
                    }
                } else {
                    ContentUnavailableView("This trip is no longer available", systemImage: "suitcase.rolling")
                }
            }
            .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TravelTheme.background).navigationTitle("Checklist")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { if trip != nil { addButton } }
        .sheet(item: $editor) { selection in
            ChecklistEditor(store: store, tripID: tripID, item: selection.item)
        }
        .confirmationDialog("Remove “\(removing?.title ?? "this item")”?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove item", role: .destructive) {
                guard let item = removing else { return }
                Task {
                    do { try await store.deleteChecklistItem(item) }
                    catch { self.error = error.localizedDescription }
                    removing = nil
                }
            }.disabled(!store.canChangeTrips)
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text("Removes this item from this trip’s checklist. This can’t be undone.") }
        .alert("Couldn’t update checklist", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var addButton: some View {
        Button("Add item", systemImage: "plus") { editor = EditorSelection(item: nil) }
            .disabled(!store.canChangeTrips).accessibilityIdentifier("add-checklist-item")
    }

    private func checklistRow(_ item: ChecklistItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task {
                    do { try await store.setChecklistCompletion(item, completed: !item.isCompleted) }
                    catch { self.error = error.localizedDescription }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                        .font(.title2).foregroundStyle(TravelTheme.accent).accessibilityHidden(true)
                    Text(item.title).strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? TravelTheme.secondary : TravelTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 44, alignment: .center).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!store.canChangeTrips)
            .accessibilityLabel(item.title).accessibilityValue(item.isCompleted ? "Completed" : "Not completed")
            .accessibilityHint(item.isCompleted ? "Mark as not completed" : "Mark as completed")
            .accessibilityIdentifier("checklist-item-\(item.id)")
            Menu {
                Button("Edit", systemImage: "pencil") { editor = EditorSelection(item: item) }
                Button("Remove item", systemImage: "trash", role: .destructive) { removing = item }
            } label: { Label("Actions for \(item.title)", systemImage: "ellipsis.circle").labelStyle(.iconOnly) }
                .disabled(!store.canChangeTrips)
                .frame(minHeight: 44)
        }.tripPanel()
    }
}

private struct ChecklistEditor: View {
    let store: TripStore
    let tripID: String
    private let item: ChecklistItem?
    private let originalTitle: String
    @State private var itemID: String
    @State private var title: String
    @State private var error: String?
    @State private var discard = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(store: TripStore, tripID: String, item: ChecklistItem?) {
        self.store = store; self.tripID = tripID; self.item = item
        originalTitle = item?.title ?? ""
        _title = State(initialValue: originalTitle)
        _itemID = State(initialValue: item?.id ?? UUID().uuidString)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Pack chargers", text: $title).focused($focused)
                        .accessibilityLabel("Checklist item").accessibilityIdentifier("checklist-title")
                } header: { Text("Checklist item") } footer: {
                    Text("Use a short title for something to pack or do. Check it off when it’s ready.")
                }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden).background(TravelTheme.background)
            .navigationTitle(item == nil ? "New checklist item" : "Edit checklist item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focused = false
                        if title != originalTitle { discard = true } else { dismiss() }
                    }.disabled(store.isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? "Add" : "Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canChangeTrips)
                        .accessibilityIdentifier("save-checklist-item")
                }
            }
        }
        .disabled(store.isWorking).interactiveDismissDisabled(title != originalTitle || store.isWorking)
        .confirmationDialog("Discard your changes?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .alert("Couldn’t save checklist item", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 500, minHeight: 270, idealHeight: 300)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func save() {
        focused = false
        Task {
            do {
                try await store.saveChecklistItem(ChecklistInput(title: title), id: itemID, tripID: tripID, expectingExisting: item != nil)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
