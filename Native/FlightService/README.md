# Flight service

This small TypeScript service keeps the AeroDataBox key off the iPhone and Mac. The Swift app sends a flight number and the departure airport's local day. The service returns a versioned, provider-independent schedule. Trip names, booking references, expenses, and traveler details stay on the device.

## Run locally

Install Node.js 24.11 or later. There are no runtime package dependencies. From this directory, run:

```sh
npm ci
cp .env.example .env
```

Enter a provider key in the ignored `.env` file, then run `npm start`. The default gateway is AeroDataBox direct, using `X-Api-Key`. An existing API.Market subscription can use `AERODATABOX_GATEWAY=api-market` and its own key. Keys from the two channels are not interchangeable.

The service listens on `127.0.0.1:8787`. In Xcode, choose **Product → Scheme → Edit Scheme → Run → Arguments**, then add the environment variable `TRAVEL_VIEW_FLIGHT_SERVICE_URL` with value `http://localhost:8787`. This Debug override works on My Mac and the iPhone simulator. For an actual iPhone, use an HTTPS service reachable from the phone and set the `TRAVEL_VIEW_FLIGHT_SERVICE_URL` build setting to that address. The build setting is written to `FlightServiceURL` in the app's Info.plist.

To try the full flow without a key, run `npm run demo` and search for **TV100** on any departure date. Its fictional JFK–LHR flight is labeled **Sample data** throughout the app. The demo entry point never contacts AeroDataBox. Stop either service with Control-C before starting the other on the same port.

## Contract and behavior

`GET /v1/flights?number=BA178&date=2027-03-04` returns `{ "version": 1, "flights": [...] }`. Each result has a flight number, airline, departure and arrival airport codes, optional airport-local timestamps and zone identifiers, provider attribution, status at lookup, and a UTC `fetchedAt` timestamp. An empty array means no matching schedule. Dates are validated before provider access. Repeated legs are removed and different legs remain separate choices.

The adapter reads **scheduled** times. It preserves the local clock directly, including overnight and date-line crossings. It never substitutes estimated times or invents missing times. The app stores the reviewed flight plan and its last lookup separately. There is no automatic status refresh in this milestone.

Errors distinguish invalid input (400), throttling (429), provider unavailability (503), and unreadable provider responses (502). Provider credentials and raw error bodies never reach the client. Upstream calls time out after 15 seconds, reject redirects, and have a 1 MB response limit.

The local process allows ten lookups per minute and defaults to at most 50 provider attempts per UTC day. Simultaneous identical lookups share an in-flight request. There is no retained response cache. Limits reset on process restart and apply to this one process.

## Hosting later

This entry point is a loopback-only development service. Before hosting, add authenticated access, HTTPS, shared durable usage limits, and deployment secret storage. Those controls belong at the service boundary. Confirm that the selected provider plan permits the intended mobile use and retention of selected schedule details. No account, paid subscription, or hosting deployment is created by this project.

The direct AeroDataBox gateway is the initial choice because it supports the number-and-local-date lookup already suited to this app and removes the marketplace dependency. API.Market remains an optional migration path. Another provider can implement `FlightProvider` without changing the native database or screens.

Primary references checked November 11, 2026:

- [Subscription channels and API specification](https://aerodatabox.com/api-spec)
- [Direct OpenAPI contract](https://doc.aerodatabox.com/docs/openapi-direct-v1.json)
- [Coverage and future schedule limits](https://aerodatabox.com/data-coverage)
- [Plans and permitted usage](https://aerodatabox.com/pricing)

## Code and checks

- `src/provider.ts` validates requests and adapts the documented AeroDataBox response.
- `src/server.ts` owns the HTTP contract, error mapping, and local usage limits.
- `src/main.ts` loads server-only configuration and starts the real adapter.
- `src/demo.ts` provides explicit fictional data for interface development.

Run `npm run typecheck` and `npm test`. Tests use synthetic provider responses and a temporary loopback HTTP server. They make no paid API calls.
