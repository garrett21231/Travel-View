"""Validate trip details and persist them as local JSON files."""

import json
from dataclasses import asdict, dataclass
from datetime import date
from pathlib import Path
from uuid import uuid4


@dataclass(frozen=True)
class Trip:
    """A trip with dates represented as Python date objects."""

    id: str
    name: str
    destination: str
    start: date
    end: date
    notes: str = ""

    @classmethod
    def from_form(cls, name, destination, start_text, end_text, notes):
        """Validate the form text, then assign a unique ID to the new trip."""
        name, destination = name.strip(), destination.strip()
        if not name or not destination:
            raise ValueError("Enter a trip name and destination.")

        try:
            start = date.fromisoformat(start_text.strip())
            end = date.fromisoformat(end_text.strip())
            if start.isoformat() != start_text.strip() or end.isoformat() != end_text.strip():
                raise ValueError
        except ValueError:
            raise ValueError("Enter both dates in YYYY-MM-DD format.") from None

        if end < start:
            raise ValueError("The return date must be on or after departure.")
        if end < date.today():
            raise ValueError("The return date must be today or later.")
        return cls(uuid4().hex, name, destination, start, end, notes.strip())


class TripStore:
    """Keep one JSON file per trip, named after the trip's ID."""

    def __init__(self, directory: Path):
        self.directory = directory

    def upcoming(self, today: date):
        """Load current and future trips in departure-date order."""
        trips = []
        for path in self.directory.glob("*.json"):
            data = json.loads(path.read_text(encoding="utf-8"))
            data["start"] = date.fromisoformat(data["start"])
            data["end"] = date.fromisoformat(data["end"])
            trip = Trip(**data)
            if trip.end >= today:
                trips.append(trip)
        return sorted(trips, key=lambda trip: (trip.start, trip.end, trip.name.casefold()))

    def save(self, trip: Trip):
        """Write the trip after converting its date objects to ISO strings."""
        self.directory.mkdir(parents=True, exist_ok=True)
        path = self.directory / f"{trip.id}.json"
        temporary = self.directory / f".{uuid4().hex}.tmp"
        data = asdict(trip)
        data["start"] = trip.start.isoformat()
        data["end"] = trip.end.isoformat()
        # Publish the file only after the write finishes, so readers see complete JSON.
        try:
            temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
