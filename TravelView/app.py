"""Build the three Travel View screens and route actions from WebKit."""

import json
from datetime import date, timedelta
from html import escape
from pathlib import Path

from trips import Trip, TripStore


DIRECTORY = Path.home() / "Library" / "Application Support" / "Travel View" / "Trips"
STORE = TripStore(DIRECTORY)

# Xcode bundles the stylesheet alongside this file. Each page includes it directly.
STYLE = Path(__file__).with_name("style.css").read_text(encoding="utf-8")
ICONS = {
    "plus": "M12 5v14M5 12h14",
    "back": "m15 5-7 7 7 7",
    "next": "m9 5 7 7-7 7",
    "suitcase": "M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M8 19v2m8-2v2M7 7h10a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2Zm2 3v6m6-6v6",
}

# WebKit runs this JavaScript. The travelView handler in main.m forwards its
# button clicks and form submissions to render() below.
SCRIPT = """
document.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-action]');
    if (button) {
        window.webkit.messageHandlers.travelView.postMessage({ ...button.dataset });
    }
});
document.addEventListener('submit', (event) => {
    event.preventDefault();
    const fields = Object.fromEntries(new FormData(event.target));
    if (event.submitter) event.submitter.disabled = true;
    window.webkit.messageHandlers.travelView.postMessage({ ...fields, action: 'save' });
});
"""


def display_date(day):
    return day.strftime("%b %d, %Y").replace(" 0", " ")


def icon(name):
    """Turn one of the path definitions above into an inline SVG icon."""
    return f'''<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
        stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{ICONS[name]}"/></svg>'''


def page(title, content, *, leading="", trailing="", large_title=False):
    """Wrap a screen in the shared navigation bar, stylesheet, and script."""
    inline_title = "" if large_title else f"<h1>{title}</h1>"
    heading = f'<h1 class="large-title">{title}</h1>' if large_title else ""
    return f"""<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; form-action 'none'; base-uri 'none'">
<title>{title} | Travel View</title>
<style>{STYLE}</style>
<header class="navigation">
    <div class="navigation-content"><div>{leading}</div><div>{inline_title}</div><div>{trailing}</div></div>
</header>
<main>
    {heading}
    {content}
</main>
<script>{SCRIPT}</script>
</html>"""


def upcoming(trips, error=""):
    """Show trip cards, an empty state, or a message if loading failed."""
    if error:
        content = f'<p class="error" role="alert">{escape(error)}</p>'
    elif trips:
        rows = []
        today = date.today()
        for trip in trips:
            in_progress = trip.start <= today <= trip.end
            status = '<span class="status">In progress</span>' if in_progress else ""
            rows.append(f"""<li>
                <button class="panel trip-row{' in-progress' if in_progress else ''}" data-action="overview" data-id="{escape(trip.id)}">
                    <span class="thumbnail">{icon('suitcase')}</span>
                    <span class="trip-copy"><strong>{escape(trip.name)}</strong>{status}
                        <span>{escape(trip.destination)}</span>
                        <span>{display_date(trip.start)} – {display_date(trip.end)}</span></span>
                    <span class="chevron">{icon('next')}</span>
                </button>
            </li>""")
        count = f"{len(trips)} {'trip' if len(trips) == 1 else 'trips'}"
        content = f'<p class="trip-count">{count}</p><ul class="trip-list">{"".join(rows)}</ul>'
    else:
        content = f"""<section class="empty">
            <span class="empty-icon">{icon('suitcase')}</span>
            <h2>Where to next?</h2><p>Your upcoming trips will appear here.</p>
            <button class="tinted" data-action="create">{icon('plus')} New trip</button>
        </section>"""
    return page("Upcoming trips", content, large_title=True,
                trailing=f'<button class="toolbar-icon" data-action="create" aria-label="Create new trip">{icon("plus")}</button>')


def create(fields=None, error=""):
    """Show the New trip form, keeping the draft if saving fails."""
    if fields is None:
        today = date.today()
        fields = {"name": "", "destination": "", "start": today.isoformat(),
                  "end": (today + timedelta(days=1)).isoformat(), "notes": ""}
    # Keep typed characters like < and & as text when inserting them into HTML.
    values = {key: escape(value) for key, value in fields.items()}
    feedback = f'<p class="error" role="alert">{escape(error)}</p>' if error else ""
    content = f"""<form class="trip-form">
        <section class="panel field-group">
            <label class="field">Trip name
                <input name="name" value="{values['name']}" placeholder="A weekend in Boston" required>
            </label>
            <label class="field">Destination
                <input name="destination" value="{values['destination']}" placeholder="Boston, MA" required>
            </label>
        </section>
        <section>
            <h2 class="section-label">Dates</h2>
            <div class="panel field-group">
                <label class="field date-field">Departure<input type="date" name="start" value="{values['start']}" required></label>
                <label class="field date-field">Return<input type="date" name="end" value="{values['end']}" required></label>
            </div>
        </section>
        <section class="panel field-group">
            <label class="field"><span>Notes <span class="optional">(optional)</span></span>
                <textarea name="notes" rows="3" placeholder="Add any details you want to remember">{values['notes']}</textarea>
            </label>
        </section>
        {feedback}
        <button type="submit" class="primary">Save trip</button>
    </form>"""
    return page("New trip", content, leading='<button class="toolbar-link" data-action="upcoming">Cancel</button>')


def overview(trip):
    """Show a saved trip's destination, dates, and notes."""
    content = f"""<div class="overview">
        <div class="detail-heading"><h2>{escape(trip.name)}</h2>
            <p>{escape(trip.destination)}</p></div>
        <section class="panel details">
            <h3>Trip dates</h3>
            <dl>
                <div><dt>Departure</dt><dd>{display_date(trip.start)}</dd></div>
                <div><dt>Return</dt><dd>{display_date(trip.end)}</dd></div>
            </dl>
        </section>
        <section class="panel details">
            <h3>Notes</h3><p class="notes">{escape(trip.notes or 'No notes added.')}</p>
        </section>
    </div>"""
    return page("Overview", content,
                leading=f'<button class="toolbar-link" data-action="upcoming" aria-label="Back to Upcoming trips">{icon("back")}<span>Upcoming</span></button>')


def render(payload):
    """Turn one JSON request from main.m into the next screen's HTML."""
    request = json.loads(payload)
    action = request.get("action")
    if action == "create":
        return create()
    if action == "save":
        fields = {name: request.get(name, "") for name in ("name", "destination", "start", "end", "notes")}
        try:
            trip = Trip.from_form(fields["name"], fields["destination"], fields["start"], fields["end"], fields["notes"])
            STORE.save(trip)
        except ValueError as error:
            return create(fields, str(error))
        except OSError as error:
            return create(fields, f"Couldn’t save the trip. {error}")
        return overview(trip)

    # Launch sends no action. Launch and Back both fall through to Upcoming.
    try:
        trips = STORE.upcoming(date.today())
    except (OSError, ValueError, TypeError, KeyError) as error:
        return upcoming([], f"Couldn’t load saved trips. {error}")
    if action == "overview":
        for trip in trips:
            if trip.id == request.get("id"):
                return overview(trip)
    return upcoming(trips)
