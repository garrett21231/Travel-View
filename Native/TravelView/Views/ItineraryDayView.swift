import SwiftUI
import TravelCore

/// Each day displays projected entries. Edit and Remove always act on the underlying item.
struct ItineraryDayView: View {
    let group: ItineraryDay
    let today: TravelDay
    let canEdit: Bool
    let onEdit: (ItineraryItem) -> Void
    let onRemove: (ItineraryItem) -> Void
    let onCheckFlight: (ItineraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.day?.formatted ?? "Undated plans").font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if group.day == today {
                    Text("Today").font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundStyle(TravelTheme.accent)
                        .background(TravelTheme.tint, in: Capsule())
                }
            }
            if group.day == nil {
                Text("Add dates whenever you’re ready.").font(.subheadline).foregroundStyle(TravelTheme.secondary)
            }
            ForEach(group.events) { event in
                Divider()
                ItineraryEventRow(event: event, canEdit: canEdit,
                                  onEdit: { onEdit(event.item) }, onRemove: { onRemove(event.item) },
                                  onCheckFlight: { onCheckFlight(event.item) })
            }
        }
        .tripPanel()
        .id(group.id)
        .accessibilityIdentifier("itinerary-day-\(group.id)")
    }
}

private struct ItineraryEventRow: View {
    let event: ItineraryEvent
    let canEdit: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onCheckFlight: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(event.title, systemImage: event.item.kind.symbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(TravelTheme.accent)
                Spacer(minLength: 8)
                Menu {
                    if event.item.kind == .flight {
                        Button("Check flight updates", systemImage: "arrow.clockwise", action: onCheckFlight)
                    }
                    Button("Edit", systemImage: "pencil", action: onEdit)
                    Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Label("Actions for \(event.item.title), \(event.title.lowercased())", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                }.disabled(!canEdit)
            }
            if event.day != nil {
                Text(event.timeText).font(.subheadline.weight(.medium))
                    .foregroundStyle(event.time == nil ? TravelTheme.secondary : TravelTheme.ink)
            }
            Text(event.item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            if let flight = event.item.flight {
                Text("\(flight.number) · \(airport(flight.departureAirport)) → \(airport(flight.arrivalAirport))")
                    .font(.subheadline).foregroundStyle(TravelTheme.secondary)
            } else if !event.item.location.isEmpty {
                Label(event.item.location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline).foregroundStyle(TravelTheme.secondary)
            }
            if event.item.start != event.item.end, let start = event.item.start, let end = event.item.end {
                Text("\(start.formatted) – \(end.formatted)").font(.caption).foregroundStyle(TravelTheme.secondary)
            }
            if hasDetails {
                DisclosureGroup("Details") { details.padding(.top, 8) }
                    .font(.subheadline)
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("itinerary-event-\(event.id)")
    }

    private var hasDetails: Bool { event.item.flight != nil || !event.item.notes.isEmpty }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let flight = event.item.flight {
                if let departure = flight.departureLocal { Text("Departs \(departure.formatted)") }
                if let arrival = flight.arrivalLocal { Text("Arrives \(arrival.formatted)") }
                Text("Airport local times").font(.caption)
                if !flight.airline.isEmpty { Text(flight.airline) }
                if !flight.bookingReference.isEmpty { Text("Booking reference: \(flight.bookingReference)") }
                if let snapshot = flight.lastLookup {
                    Text("Schedule from \(snapshot.provider), looked up \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)). Review with your airline before travel.")
                        .font(.caption)
                }
            }
            if !event.item.notes.isEmpty { Text(event.item.notes) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(TravelTheme.secondary)
    }

    private func airport(_ value: String) -> String { value.isEmpty ? "TBD" : value }
}
