# Travel View Native

A new Swift and SwiftUI app for iPhone, iPad, and Mac. Its shared `TravelCore` package uses SQLite through GRDB 7.12.0.

Open `Travel View Native.xcodeproj`, choose the **Travel View Native** scheme, select an iPhone simulator or **My Mac**, and press **⌘R**. Xcode downloads the pinned GRDB dependency on the first build. Physical iPhone installation requires selecting your Apple development team under **Signing & Capabilities**.

## Current native version

- **Upcoming** includes trips happening now, future trips, and plans with undecided dates. **All trips** also retains completed trips.
- **New trip** collects a name, destinations, optional dates, planned traveler count, optional USD budget, and notes. Dates are calendar days, and budgets are stored in whole cents.
- **Overview** displays saved trip details, notes, and the itinerary, and opens **Edit trip**. A failed save keeps the form open with the draft.
- **Itinerary** supports adding and editing flights, lodging, and activities, with optional dates, location and notes. The item menu also offers removal with confirmation.
- **Flights** can be entered manually or selected by flight number and local departure date through the configurable flight service. Lookup results fill a reviewable draft. Flight clocks retain each airport's local time. The saved lookup is attributed and dated, with no automatic live-status refresh.
- The collection’s **Trip backups** menu exports a JSON snapshot or imports one. Import appends missing IDs and preserves the current details of existing IDs. An import can be retried safely.

The app has the bundle identifier `local.travelview.native`. Its database is `Travel View Native/trips.sqlite` inside its Application Support directory. On Mac, the app sandbox supplies that directory inside the app’s container. A second SQLite migration adds itinerary storage while preserving existing trips. Version 2 JSON backups include itinerary records, and imports still accept version 1 trip-only backups. Limits are 10 MB, 5,000 trips and 25,000 itinerary records. Imports are atomic and keep existing records with matching IDs.

Flight lookup needs the companion [flight service](FlightService/README.md). That guide covers direct AeroDataBox access, the optional existing API.Market gateway, and a no-key sample service. Manual flight entry works before the service is connected.

## Reading the code

| File | Responsibility |
| --- | --- |
| `TravelView/App/TravelViewApp.swift` | Starts the app and shares one observable store across its windows. |
| `TravelView/App/TripStore.swift` | Coordinates loading and saving, and updates the interface after committed writes. |
| `TravelView/Views/TripLibraryView.swift` | Upcoming/All trips, navigation, and backup file pickers. |
| `TravelView/Views/TripEditor.swift` | Local form draft, validation feedback, and save/cancel behavior. |
| `TravelView/Views/TripOverview.swift` | Saved trip details and ordered itinerary, with item actions. |
| `TravelView/Views/ItineraryEditor.swift` | A local item draft and review of selected flight schedules. |
| `TravelView/Views/FlightLookupView.swift` | Search, loading, errors, empty results and explicit flight selection. |
| `TravelView/Design/TravelTheme.swift` and `Assets.xcassets` | Shared colors with dark and increased-contrast appearances. |
| `TravelCore/Sources/TravelCore/Trip.swift` | Trip data, validation, sorting, and exact budget parsing. |
| `TravelCore/Sources/TravelCore/TravelDay.swift` | Calendar days and their database/JSON representation. |
| `TravelCore/Sources/TravelCore/TripRepository.swift` | SQLite migrations, transactional saves, and atomic backup imports. |
| `TravelCore/Sources/TravelCore/TripArchive.swift` | Versioned backup encoding and validation. |
| `TravelCore/Sources/TravelCore/ItineraryItem.swift` | Item identities, types, flight plan fields, validation and ordering. |
| `TravelCore/Sources/TravelCore/ItineraryRepository.swift` | Trip-scoped item saves and a consistent trip/itinerary snapshot. |
| `TravelCore/Sources/TravelCore/LocalMoment.swift` | An airport-local wall clock, kept separate from absolute UTC instants. |
| `TravelCore/Sources/TravelCore/FlightService.swift` | The provider-independent flight client and lookup snapshot types. |
| `FlightService/src` | TypeScript gateway with the server-only provider credential. |

To follow **Save trip**, start at `save()` in `TripEditor.swift`. The form creates a `TripInput`, the store asks the repository to validate and commit it, and the returned `Trip` updates the collection and Overview. The form keeps a stable trip ID for save retries.

## Verification

From the repository root, run `swift test --package-path Native/TravelCore`. The 14 tests cover calendar days, exact money, persistence and save retries, Upcoming filtering, database upgrades, trip-scoped itinerary writes, date-line crossings, old/new backup imports and rollback, preservation of reviewed flight details and their source snapshot, plus the flight client's success/error/empty response handling. The service has its own type check and six tests.

For isolated interface testing, a Debug build accepts the `TRAVEL_VIEW_NATIVE_DATA_DIR` environment variable in its Run scheme. Set it to a temporary directory to choose the test database location.

## Later features remain accounted for

Expenses, richer overview summaries, and individual travelers remain planned. They are not implemented in this milestone. A stable trip ID owns each itinerary item, and each item has its own stable ID. Future expense records and traveler participation can reference those identities without changing saved flight, lodging, or activity records. The current planned traveler count is a planning estimate; it does not stand in for future traveler profiles or assignments. The current USD budget remains a trip-level estimate, separate from future actual expenses.

When those features are added, the overview can derive totals and participation from their records. Further numbered migrations and backup versions will introduce their tables and relationships. No unused expense or traveler tables are created now.
