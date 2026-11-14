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
                Label(event.title, systemImage: event.item.symbol)
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
            NavigationLink(value: ItinerarySelection(id: event.item.id, tripID: event.item.tripID)) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 9) {
                        if event.day != nil {
                            Text(event.timeText).font(.subheadline.weight(.medium))
                                .foregroundStyle(event.time == nil ? TravelTheme.secondary : TravelTheme.ink)
                        }
                        Text(event.item.title).font(.headline).foregroundStyle(TravelTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        BookingStateBadge(state: event.item.bookingState)
                        if let flight = event.item.flight {
                            Text("\(flight.number) · \(airport(flight.departureAirport)) → \(airport(flight.arrivalAirport))")
                                .font(.subheadline).foregroundStyle(TravelTheme.secondary)
                        } else if let transport = event.item.transport {
                            Text("\(transport.mode.title) · \(transport.routeText)")
                                .font(.subheadline).foregroundStyle(TravelTheme.secondary)
                        } else if !event.item.location.isEmpty {
                            Label(event.item.location, systemImage: "mappin.and.ellipse")
                                .font(.subheadline).foregroundStyle(TravelTheme.secondary)
                        }
                        if event.item.start != event.item.end, let start = event.item.start, let end = event.item.end {
                            Text("\(start.formatted) – \(end.formatted)").font(.caption).foregroundStyle(TravelTheme.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(TravelTheme.secondary).padding(.top, 4).accessibilityHidden(true)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibleSummary)
            .accessibilityHint("Open \(event.item.kind.title.lowercased()) details")
            .accessibilityIdentifier("open-itinerary-\(event.id)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("itinerary-event-\(event.id)")
    }

    private func airport(_ value: String) -> String { value.isEmpty ? "TBD" : value }

    /// Keep the visible timing and planning state available when VoiceOver treats the row as one link.
    private var accessibleSummary: String {
        var parts = [event.item.title, event.timeText, "Booking state: \(event.item.bookingState.title)"]
        if let flight = event.item.flight {
            parts.append("\(flight.number), \(airport(flight.departureAirport)) to \(airport(flight.arrivalAirport))")
        } else if let transport = event.item.transport {
            parts.append("\(transport.mode.title), \(transport.routeText)")
        } else if !event.item.location.isEmpty { parts.append(event.item.location) }
        return parts.joined(separator: ". ")
    }
}
