import { flightServer } from './server.ts';

// Explicit development fixture. It never contacts a provider or represents a real flight.
const server = flightServer({ lookup: async query => query.number === 'TV100' ? [{
  number: 'TV100', airline: 'Sample airline',
  departure: { airport: 'JFK', local: `${query.date}T19:30`, timeZone: 'America/New_York' },
  arrival: { airport: 'LHR', local: `${new Date(new Date(`${query.date}T12:00:00Z`).valueOf() + 86_400_000).toISOString().slice(0, 10)}T07:20`, timeZone: 'Europe/London' },
  status: 'Sample', provider: 'Sample data', fetchedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
}] : [] });
server.listen(8787, '127.0.0.1', () => console.log('Sample flight service on http://localhost:8787. Search TV100 for any departure date.'));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close());
