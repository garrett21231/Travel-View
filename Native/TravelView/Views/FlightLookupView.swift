import SwiftUI
import TravelCore

struct FlightLookupView: View {
    let onChoose: (FlightSchedule, TravelDay) -> Void
    @State private var number: String
    @State private var day: Date
    @State private var request: SearchRequest?
    @State private var searching = false
    @State private var searched = false
    @State private var results: [FlightSchedule] = []
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private struct SearchRequest {
        let id = UUID()
        let query: FlightQuery
    }

    init(number: String, day: TravelDay, onChoose: @escaping (FlightSchedule, TravelDay) -> Void) {
        self.onChoose = onChoose
        _number = State(initialValue: number)
        _day = State(initialValue: day.date())
    }

    /// Configuration contains our service address, never a provider credential.
    private var service: FlightService? {
        #if DEBUG
        let override = ProcessInfo.processInfo.environment["TRAVEL_VIEW_FLIGHT_SERVICE_URL"]
        #else
        let override: String? = nil
        #endif
        let text = override ?? Bundle.main.object(forInfoDictionaryKey: "FlightServiceURL") as? String ?? ""
        guard !text.isEmpty, let url = URL(string: text) else { return nil }
        return FlightService(baseURL: url)
    }

    var body: some View {
        NavigationStack {
            Group {
                if service == nil {
                    ContentUnavailableView {
                        Label("Flight lookup isn’t connected yet", systemImage: "airplane")
                    } description: {
                        Text("You can still add a flight and its schedule manually.")
                    } actions: {
                        Button("Enter flight manually") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    Form {
                        Section {
                            TextField("Flight number, e.g. BA178", text: $number)
                                .accessibilityIdentifier("lookup-flight-number")
                                #if os(iOS)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                #endif
                            DatePicker("Departure date", selection: $day, displayedComponents: .date)
                            Button("Find flights", systemImage: "magnifyingglass", action: search)
                                .disabled(searching || number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } header: { Text("Search by flight number") } footer: {
                            Text("Use the departure airport’s local date. Schedule availability varies by airline and date.")
                        }
                        if searching { Section { ProgressView("Finding flights…") } }
                        if let error { Section { Text(error).foregroundStyle(.red) } }
                        if searched && !searching && error == nil {
                            Section("Matching flights") {
                                if results.isEmpty {
                                    Text("No schedule found for this flight and date. Check the number or enter the flight manually.")
                                }
                                ForEach(results) { schedule in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("\(schedule.number) · \(schedule.airline)").font(.headline)
                                        Text("\(schedule.departure.airport) → \(schedule.arrival.airport)").font(.title3)
                                        Text("Departs \(schedule.departure.local?.formatted ?? "time unavailable")")
                                        Text("Arrives \(schedule.arrival.local?.formatted ?? "time unavailable")")
                                        Text("Airport local times · \(schedule.provider)")
                                            .font(.caption).foregroundStyle(TravelTheme.secondary)
                                        Button("Use this flight") {
                                            guard let request else { return }
                                            onChoose(schedule, request.query.departureDay)
                                            dismiss()
                                        }.buttonStyle(.bordered)
                                    }.padding(.vertical, 6)
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .onChange(of: number) { _, _ in reset() }
                    .onChange(of: day) { _, _ in reset() }
                }
            }
            .navigationTitle("Find a flight")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task(id: request?.id) {
            guard let request, let service else { return }
            do {
                let flights = try await service.lookup(request.query)
                try Task.checkCancellation()
                results = flights
                searched = true
                searching = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                searching = false
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 450, idealHeight: 620)
        #endif
    }

    private func search() {
        do {
            let query = try FlightQuery(number: number, departureDay: TravelDay(day))
            error = nil; results = []; searched = false; searching = true
            request = SearchRequest(query: query)
        } catch { self.error = error.localizedDescription }
    }
    private func reset() {
        request = nil; results = []; searched = false; searching = false; error = nil
    }
}
