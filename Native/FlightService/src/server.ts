import { createServer } from 'node:http';
import type { ServerResponse } from 'node:http';
import { parseQuery, ServiceError } from './provider.ts';
import type { FlightProvider, FlightSchedule } from './provider.ts';

interface Options { maxCallsPerDay?: number; requestsPerMinute?: number; now?: () => number }

/** Local development gateway. No trip, traveler, expense or booking-reference data is accepted. */
export function flightServer(provider: FlightProvider, options: Options = {}) {
  const now = options.now ?? Date.now;
  const maximum = options.maxCallsPerDay ?? 50;
  const perMinute = options.requestsPerMinute ?? 10;
  const pending = new Map<string, Promise<FlightSchedule[]>>();
  let minute = 0, requests = 0, day = '', calls = 0;

  function send(response: ServerResponse, status: number, body: unknown) {
    response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    response.end(JSON.stringify(body));
  }

  const server = createServer(async (request, response) => {
    try {
      if (request.method !== 'GET') { send(response, 405, { error: 'method_not_allowed' }); return; }
      const url = new URL(request.url ?? '/', 'http://localhost');
      if (url.pathname === '/health') { send(response, 200, { status: 'ok' }); return; }
      if (url.pathname !== '/v1/flights') { send(response, 404, { error: 'not_found' }); return; }
      if ([...url.searchParams.keys()].some(key => !['number', 'date'].includes(key)) ||
          url.searchParams.getAll('number').length !== 1 || url.searchParams.getAll('date').length !== 1) {
        throw new ServiceError(400, 'invalid_query');
      }
      const query = parseQuery(url.searchParams.get('number') ?? '', url.searchParams.get('date') ?? '');
      const currentMinute = Math.floor(now() / 60_000);
      if (minute !== currentMinute) { minute = currentMinute; requests = 0; }
      if (++requests > perMinute) throw new ServiceError(429, 'lookup_limit');
      const key = `${query.number}/${query.date}`;
      let lookup = pending.get(key);
      if (!lookup) {
        const currentDay = new Date(now()).toISOString().slice(0, 10);
        if (day !== currentDay) { day = currentDay; calls = 0; }
        if (calls >= maximum) throw new ServiceError(429, 'daily_limit');
        calls++;
        lookup = provider.lookup(query);
        pending.set(key, lookup);
      }
      let flights: FlightSchedule[];
      try { flights = await lookup; }
      finally { if (pending.get(key) === lookup) pending.delete(key); }
      send(response, 200, { version: 1, flights });
    } catch (error) {
      const failure = error instanceof ServiceError ? error : new ServiceError(500, 'service_failed');
      // Provider errors and secrets are deliberately absent from client responses and logs.
      send(response, failure.status, { error: failure.code });
    }
  });
  server.requestTimeout = 25_000;
  server.headersTimeout = 10_000;
  return server;
}
