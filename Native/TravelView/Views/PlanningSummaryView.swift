import SwiftUI
import TravelCore

/// Every total comes from saved items, not the separate timeline entries for their start and end.
struct PlanningSummaryView: View {
    let tripID: String
    let summary: ItinerarySummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Planning overview").font(.headline).accessibilityAddTraits(.isHeader)
            Text("\(summary.total) \(summary.total == 1 ? "plan" : "plans")")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("planning-total")
            Text("\(summary.flights) \(summary.flights == 1 ? "flight" : "flights") · \(summary.stays) \(summary.stays == 1 ? "stay" : "stays") · \(summary.activities) \(summary.activities == 1 ? "activity" : "activities")")
                .font(.subheadline).foregroundStyle(TravelTheme.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), alignment: .leading, spacing: 12) {
                stateLink(.idea, count: summary.ideas)
                stateLink(.planned, count: summary.planned)
                stateLink(.booked, count: summary.booked)
            }
            Text("Booking states are labels you choose for your plans.")
                .font(.caption).foregroundStyle(TravelTheme.secondary)
            if summary.undated > 0 {
                NavigationLink(value: ItineraryBrowserSelection(tripID: tripID, query: ItineraryQuery(undatedOnly: true))) {
                    Label("\(summary.undated) \(summary.undated == 1 ? "plan needs" : "plans need") dates", systemImage: "calendar.badge.questionmark")
                }
                .accessibilityIdentifier("browse-undated-plans")
            }
            NavigationLink(value: ItineraryBrowserSelection(tripID: tripID)) {
                Label("Find a plan", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered).accessibilityIdentifier("browse-all-plans")
        }
        .tripPanel()
        .accessibilityIdentifier("planning-summary")
    }

    private func stateLink(_ state: BookingState, count: Int) -> some View {
        NavigationLink(value: ItineraryBrowserSelection(tripID: tripID, query: ItineraryQuery(bookingState: state))) {
            VStack(alignment: .leading, spacing: 6) {
                Text(count.formatted()).font(.title3.weight(.semibold))
                Label(state.title, systemImage: state.symbol).font(.caption)
            }
            .foregroundStyle(TravelTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(TravelTheme.tint, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) \(state.title.lowercased()) \(count == 1 ? "plan" : "plans")")
        .accessibilityHint("Show plans with this booking state")
        .accessibilityIdentifier("browse-state-\(state.rawValue)")
    }
}
