# Travel View

The new native Swift version is in [`Native`](Native/README.md). Open [`Travel View Native.xcodeproj`](Native/Travel%20View%20Native.xcodeproj) for its SwiftUI interface and SQLite storage.

## Python version

Open `Travel View.xcodeproj` and select the **Travel View** scheme. Choose **My Mac** or an iPhone simulator as the run destination, then press **⌘R**. The deployment targets are macOS 14 and iOS 17.

- **Mac** uses the Python runtime bundled with Xcode.
- **iPhone and Simulator** embed a pinned BeeWare Python runtime. On a fresh checkout, run `bash scripts/setup-ios-python.sh` from the project folder before the first iOS build.
- **Physical iPhone** needs an Apple development team selected in the target’s **Signing & Capabilities** tab. Connect or pair the iPhone, enable Developer Mode if prompted, and choose it as the run destination.

Python generates the screens, and the native app displays them in a built-in WebKit view.

1. Open **New trip** from **Upcoming trips**.
2. Enter a name, destination, departure and return dates. The return date must be today or later. Notes are optional.
3. Select **Save trip** to open **Overview**. Return to **Upcoming trips** to reopen any trip whose return date is today or later.

## Where to start reading

- [`app.py`](TravelView/app.py) builds the screens. `upcoming()` draws the list, `create()` draws the form, and `overview()` draws the details. `page()` supplies the shared navigation and styling.
- [`trips.py`](TravelView/trips.py) defines what a trip contains, validates the form, and saves each trip as a JSON file. The Mac build uses `~/Library/Application Support/Travel View/Trips`. The iPhone build uses its own Application Support directory.
- [`style.css`](TravelView/style.css) controls colors, spacing, and layout on both platforms.
- [`main.m`](TravelView/main.m) starts Python and hosts WebKit inside a Mac or iPhone window. The [Xcode configuration](Travel%20View.xcconfig) selects the appropriate Python runtime for each platform.

To follow **Save trip**, start at `render()` near the bottom of `app.py`. The JavaScript at the top sends the form fields through `main.m` to `render()`. Python validates the fields in `Trip.from_form()`, saves through `TripStore.save()`, and returns the Overview HTML for WebKit to display. If validation fails, `render()` returns the form with the draft and an error message.

## Reading the parentheses in `app.py`

- `overview(trip)` calls `overview` and gives it the trip to display. `def overview(trip)` names the input when defining that function.
- `(today + timedelta(days=1)).isoformat()` groups the calculation so Python adds one day before turning the result into a date string.
- `except (OSError, ValueError, TypeError, KeyError)` handles any one of those errors. The commas make the error types a tuple, a fixed sequence.
- In `rows.append(f"""…""")`, the parentheses pass one argument to `append`. The triple quotes enclose a string containing several lines of HTML, and the `f` lets Python substitute expressions inside `{}`. Each call adds one trip card to the list.
