import SwiftUI
import TravelCore

struct ItineraryBrowserSelection: Hashable {
    let tripID: String
    var query = ItineraryQuery()
}

/// A separate browser keeps searches from hiding days in Overview or changing Coming up.
struct ItineraryBrowserView: View {
    let store: TripStore
    let tripID: String
    @State private var query: ItineraryQuery
    @FocusState private var searching: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: TripStore, selection: ItineraryBrowserSelection) {
        self.store = store; tripID = selection.tripID
        _query = State(initialValue: selection.query)
    }

    private var items: [ItineraryItem] { store.items(for: tripID) }

    var body: some View {
        let results = query.matching(items)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if store.trips.contains(where: { $0.id == tripID }) {
                    searchControls
                    if items.isEmpty {
                        ContentUnavailableView {
                            Label("No plans yet", systemImage: "calendar.badge.plus")
                        } description: {
                            Text("Add flights, stays, or activities from Overview.")
                        } actions: { Button("Back to Overview") { dismiss() } }
                    } else {
                        Text("\(results.count) of \(items.count) \(items.count == 1 ? "plan" : "plans")")
                            .font(.subheadline).foregroundStyle(TravelTheme.secondary)
                            .accessibilityIdentifier("itinerary-result-count")
                        if results.isEmpty {
                            ContentUnavailableView {
                                Label("No matching plans", systemImage: "magnifyingglass")
                            } description: {
                                Text("Try another search or reset the filters to see every plan in this trip.")
                            } actions: { Button("Reset search and filters", action: reset) }
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(results) { item in
                                    NavigationLink(value: ItinerarySelection(id: item.id, tripID: item.tripID)) {
                                        ItinerarySearchRow(item: item)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Open \(item.kind.title.lowercased()) details")
                                    .accessibilityIdentifier("browse-itinerary-\(item.id)")
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("This trip is no longer available", systemImage: "suitcase.rolling")
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(TravelTheme.background)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Find a plan")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { searching = false }
            }
        }
        #endif
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(TravelTheme.secondary).accessibilityHidden(true)
                TextField("Search plans, places, references", text: $query.text)
                    .focused($searching).textFieldStyle(.plain)
                    .accessibilityLabel("Search itinerary")
                    .accessibilityIdentifier("search-itinerary")
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
                if !query.text.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { query.text = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain)
                }
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { typeFilter; stateFilter }
                VStack(alignment: .leading, spacing: 14) { typeFilter; stateFilter }
            }
            Toggle("Undated only", isOn: $query.undatedOnly)
                .accessibilityIdentifier("itinerary-undated-filter")
            if query.isActive {
                Button("Reset search and filters", action: reset)
                    .accessibilityIdentifier("reset-itinerary-query")
            }
        }.tripPanel()
    }

    private var typeFilter: some View {
        Picker("Type", selection: $query.kind) {
            Text("All types").tag(nil as ItineraryKind?)
            Text("Flights").tag(ItineraryKind.flight as ItineraryKind?)
            Text("Stays").tag(ItineraryKind.lodging as ItineraryKind?)
            Text("Activities").tag(ItineraryKind.activity as ItineraryKind?)
        }
        .pickerStyle(.menu).accessibilityIdentifier("itinerary-type-filter")
    }

    private var stateFilter: some View {
        Picker("Booking", selection: $query.bookingState) {
            Text("All states").tag(nil as BookingState?)
            ForEach(BookingState.allCases) { state in Text(state.title).tag(state as BookingState?) }
        }
        .pickerStyle(.menu).accessibilityIdentifier("itinerary-state-filter")
    }

    private func reset() { searching = false; query = ItineraryQuery() }
}

private struct ItinerarySearchRow: View {
    let item: ItineraryItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind.symbol).foregroundStyle(TravelTheme.accent)
                .frame(width: 22).padding(.top, 3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                Text(item.title).font(.headline).foregroundStyle(TravelTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.dateText).font(.caption).foregroundStyle(TravelTheme.secondary)
                BookingStateBadge(state: item.bookingState)
                if let flight = item.flight {
                    Text("\(flight.number) · \(flight.departureAirport.isEmpty ? "TBD" : flight.departureAirport) → \(flight.arrivalAirport.isEmpty ? "TBD" : flight.arrivalAirport)")
                        .font(.subheadline).foregroundStyle(TravelTheme.secondary)
                } else if !item.location.isEmpty {
                    Text(item.location).font(.subheadline).foregroundStyle(TravelTheme.secondary)
                }
                if !item.confirmationReference.isEmpty {
                    Text("Reference: \(item.confirmationReference)").font(.caption).foregroundStyle(TravelTheme.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(TravelTheme.secondary)
                .padding(.top, 4).accessibilityHidden(true)
        }
        .tripPanel()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
