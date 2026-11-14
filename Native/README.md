# Travel View Native

A new Swift and SwiftUI app for iPhone, iPad, and Mac. Its shared `TravelCore` package uses SQLite through GRDB 7.12.0.

Open `Travel View Native.xcodeproj`, choose the **Travel View Native** scheme, select an iPhone simulator or **My Mac**, and press **⌘R**. Xcode downloads the pinned GRDB dependency on the first build. Physical iPhone installation requires selecting your Apple development team under **Signing & Capabilities**.

## Current native version

- **Upcoming** includes trips happening now, future trips, and plans with undecided dates. **All trips** also retains completed trips.
- **New trip** collects a name, destinations, optional dates, planned traveler count, optional USD budget, and notes. Dates are calendar days, and budgets are stored in whole cents.
- **Overview** displays saved trip details, notes, and the itinerary, and opens **Edit trip**. A failed save keeps the form open with the draft.
- **Day-by-day itinerary** groups plans by local calendar day. Flights show departure and arrival entries, stays show check-in and check-out, and activities can include optional start and end times. Undated plans have their own section at the end. Tap an entry to open its detail screen; editing either end of a flight or stay updates the same saved record.
- **Plan details** show the complete schedule, notes, booking state, and confirmation reference. Flights retain their existing booking-reference field; stays and activities have their own confirmation reference. Choose **Idea**, **Planned**, or **Booked** yourself in the editor. Existing items start as Planned, and neither a reference nor a provider lookup marks a plan as Booked. The timeline displays the saved state too.
- **Open in Maps** searches for the item's saved location or address. It appears when a location is present, opens only when tapped, and does not request the device's current location.
- **Coming up** previews today's scheduled entries or the next dated day, with a button that scrolls to it. The summary uses calendar days, and includes all of today's entries. It does not estimate which event happens next across different time zones. Its Today label follows the device's day and updates when the app becomes active, midnight passes, or the device time zone changes.
- **Flights** can be entered manually or selected by flight number and local departure date through the configurable flight service. Lookup results fill a reviewable draft. Flight clocks retain each airport's local time. The saved lookup is attributed and dated, with no automatic live-status refresh.
- **Check flight updates** is available in each flight entry's menu and its detail screen. Choose a matching schedule, compare Saved and Latest details, then save only the changes you select. Details that differ from the previous matching lookup stay unchecked. For manually entered flights without a comparable lookup, all replacements require selection. Title, notes, location, booking state and booking reference are kept. Missing provider values never clear known details. You can also save the lookup alone.
- The collection’s **Trip backups** menu exports a JSON snapshot or imports one. Import appends missing IDs and preserves the current details of existing IDs. An import can be retried safely.

The app has the bundle identifier `local.travelview.native`. Its database is `Travel View Native/trips.sqlite` inside its Application Support directory. On Mac, the app sandbox supplies that directory inside the app’s container. Numbered SQLite migrations add itinerary storage, optional local times, booking states and reservation references while preserving existing records. Version 4 JSON backups include the reservation fields and activity/stay times. Imports still accept version 1 trip-only backups, version 2 itineraries, and version 3 timed itineraries. Older items default to Planned with empty stay/activity references; existing flight references are retained. Limits are 10 MB, 5,000 trips and 25,000 itinerary records. Imports are atomic and keep existing records with matching IDs.

Within each day, entries with known times appear first in local clock order, followed by entries whose times are undecided. Same-day activities show a time range in one entry; an activity ending on a later date has an end entry on that date. A stay only generates check-in and check-out entries, so a long date range does not create empty days. These are views of the saved items, rather than extra records in the database.

Flight lookup needs the companion [flight service](FlightService/README.md). That guide covers direct AeroDataBox access, the optional existing API.Market gateway, and a no-key sample service. Manual flight entry works before the service is connected.

## Reading the code

| File | Responsibility |
| --- | --- |
| `TravelView/App/TravelViewApp.swift` | Starts the app and shares one observable store across its windows. |
| `TravelView/App/TripStore.swift` | Coordinates loading and saving, and updates the interface after committed writes. |
| `TravelView/Views/TripLibraryView.swift` | Upcoming/All trips, navigation, and backup file pickers. |
| `TravelView/Views/TripEditor.swift` | Local form draft, validation feedback, and save/cancel behavior. |
| `TravelView/Views/TripOverview.swift` | Saved trip details and ordered itinerary, with item actions. |
| `TravelView/Views/ItineraryDayView.swift` | Day headers, local-time summaries, booking-state badges, detail links and item actions. |
| `TravelView/Views/ItineraryDetailView.swift` | Full plan details, Maps links, edit/remove actions and flight-update access. Navigation uses IDs so saved edits appear immediately. |
| `TravelView/Views/ItineraryEditor.swift` | A local item draft and review of selected flight schedules. |
| `TravelView/Views/FlightLookupView.swift` | Search, loading, errors, empty results and explicit flight selection. |
| `TravelView/Views/FlightUpdateView.swift` | Read-only schedule checking and an explicit field-by-field update review. |
| `TravelView/Design/TravelTheme.swift` and `Assets.xcassets` | Shared colors with dark and increased-contrast appearances. |
| `TravelCore/Sources/TravelCore/Trip.swift` | Trip data, validation, sorting, and exact budget parsing. |
| `TravelCore/Sources/TravelCore/TravelDay.swift` | Calendar days and their database/JSON representation. |
| `TravelCore/Sources/TravelCore/TripRepository.swift` | SQLite migrations, transactional saves, and atomic backup imports. |
| `TravelCore/Sources/TravelCore/TripArchive.swift` | Versioned backup encoding and validation. |
| `TravelCore/Sources/TravelCore/ItineraryItem.swift` | Item identities, types, flight plan fields, validation and ordering. |
| `TravelCore/Sources/TravelCore/BookingState.swift` | User-controlled Idea/Planned/Booked labels, independent of provider status. |
| `TravelCore/Sources/TravelCore/LocationLink.swift` | Encodes a saved location as an Apple Maps search URL. |
| `TravelCore/Sources/TravelCore/ItineraryRepository.swift` | Trip-scoped item saves and a consistent trip/itinerary snapshot. |
| `TravelCore/Sources/TravelCore/LocalMoment.swift` | An airport-local wall clock, kept separate from absolute UTC instants. |
| `TravelCore/Sources/TravelCore/LocalClock.swift` | Validated HH:mm local times for activities and stays. |
| `TravelCore/Sources/TravelCore/ItineraryTimeline.swift` | Day grouping, departure/arrival and check-in/out projections, stable ordering and the next planned day. |
| `TravelCore/Sources/TravelCore/FlightService.swift` | The provider-independent flight client and lookup snapshot types. |
| `TravelCore/Sources/TravelCore/FlightUpdate.swift` | Comparison with the previous lookup, manual-edit protection and selection of safe field updates. |
| `FlightService/src` | TypeScript gateway with the server-only provider credential. |

To follow **Save trip**, start at `save()` in `TripEditor.swift`. The form creates a `TripInput`, the store asks the repository to validate and commit it, and the returned `Trip` updates the collection and Overview. The form keeps a stable trip ID for save retries.

To follow **Open plan details**, start at the `NavigationLink` in `ItineraryDayView.swift`. It carries the trip and item IDs through `TripOverview` to `ItineraryDetailView`. The detail page reads the current item from `TripStore`, so saving an edit refreshes the page without passing an outdated record back through navigation. Both ends of a stay or flight carry the same item ID.

To follow **Check flight updates**, start at the flight entry menu in `ItineraryDayView.swift` or the detail page's actions menu. `FlightUpdateView` requests a schedule through the existing lookup screen, then `FlightUpdate` compares it with the saved plan and its previous lookup. The repository checks that the reviewed record is still current inside the save transaction. A review of an edited or deleted flight cannot overwrite newer changes or recreate a deleted record. The dated lookup remains part of `FlightDetails`; the separate reservation migration adds the user-owned booking state and stay/activity reference columns.

## Verification

From the repository root, run `swift test --package-path Native/TravelCore`. The 36 tests cover calendar days, exact money, persistence and save retries, Upcoming filtering, database upgrades, trip-scoped itinerary writes, date-line crossings, old/new backup imports and rollback, reviewed flight details and their source snapshot, day grouping and ordering, local time validation, Coming up selection, flight client responses, selected schedule updates, missing provider data, manual-edit preservation, reservation validation and persistence, legacy reservation defaults, and Maps URL escaping. Stale flight reviews are rejected even if only the booking state changed. The unchanged service has its own type check and six tests.

On November 13, 2026, all 36 core tests passed, and the app compiled for Mac, iOS Simulator and physical iOS devices (the device check used unsigned compilation). Isolated Mac and iPhone simulator apps verified detail navigation, saved references and state, immediate updates after editing, and returning from details through Overview to the trip collection. Both check-in and check-out opened the same stay. The Mac Maps action opened South Bank, London. A version 3 backup imported five items with their times, and a version 4 export retained the new references and states. Actual device installation was not part of this check.

For isolated interface testing, a Debug build accepts the `TRAVEL_VIEW_NATIVE_DATA_DIR` environment variable in its Run scheme. Choose a directory the app can access. On Mac, the sandbox permits a temporary directory inside the app's own container; an arbitrary folder under `/private/tmp` is outside that sandbox.

## Later features remain accounted for

Expenses, richer overview summaries, and individual travelers remain planned. They are not implemented in this milestone. A stable trip ID owns each itinerary item, and each item has its own stable ID. Future expense records and traveler participation can reference those identities without changing saved flight, lodging, or activity records. The current planned traveler count is a planning estimate; it does not stand in for future traveler profiles or assignments. The current USD budget remains a trip-level estimate, separate from future actual expenses.

When those features are added, the overview can derive totals and participation from their records. Further numbered migrations and backup versions will introduce their tables and relationships. No unused expense or traveler tables are created now.
