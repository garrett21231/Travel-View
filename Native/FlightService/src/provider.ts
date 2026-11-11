export interface FlightStop { airport: string; local: string | null; timeZone: string | null }
export interface FlightSchedule {
  number: string; airline: string; departure: FlightStop; arrival: FlightStop;
  status: string; provider: string; fetchedAt: string;
}
export interface FlightQuery { number: string; date: string }
export interface FlightProvider { lookup(query: FlightQuery): Promise<FlightSchedule[]> }

export class ServiceError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string) { super(code); this.status = status; this.code = code; }
}

export function validDay(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith('0000')) return false;
  const date = new Date(`${value}T12:00:00Z`);
  return Number.isFinite(date.valueOf()) && date.toISOString().slice(0, 10) === value;
}

export function parseQuery(number: string, date: string): FlightQuery {
  const normalized = number.toUpperCase().replace(/\s/g, '');
  if (!/^[A-Z0-9]{2,3}[0-9]{1,4}[A-Z]?$/.test(normalized) || !/[A-Z]/.test(normalized.slice(0, 3)) || !validDay(date)) {
    throw new ServiceError(400, 'invalid_query');
  }
  return { number: normalized, date };
}

type ObjectValue = Record<string, unknown>;
const object = (value: unknown): ObjectValue => value !== null && typeof value === 'object' && !Array.isArray(value) ? value as ObjectValue : {};
const text = (value: unknown, limit: number): string => typeof value === 'string' ? value.trim().slice(0, limit) : '';

function stop(value: unknown): FlightStop | null {
  const movement = object(value);
  const airport = object(movement.airport);
  const code = text(airport.iata, 4) || text(airport.icao, 4);
  if (!/^[A-Z0-9]{3,4}$/.test(code)) return null;
  const localText = text(object(movement.scheduledTime).local, 40);
  const local = localText.slice(0, 16).replace(' ', 'T');
  // Slice the wall clock directly. Converting through Date would change airport-local times.
  const hasLocal = /^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d$/.test(local) && validDay(local.slice(0, 10));
  return { airport: code, local: hasLocal ? local : null, timeZone: text(airport.timeZone, 100) || null };
}

/// The direct and marketplace gateways use the same documented data contract.
export class AeroDataBoxProvider implements FlightProvider {
  private key: string;
  private gateway: 'direct' | 'api-market';
  private fetcher: typeof fetch;
  constructor(key: string, gateway: 'direct' | 'api-market' = 'direct', fetcher: typeof fetch = fetch) {
    this.key = key; this.gateway = gateway; this.fetcher = fetcher;
  }
  async lookup(query: FlightQuery): Promise<FlightSchedule[]> {
    if (!this.key) throw new ServiceError(503, 'provider_not_configured');
    const base = this.gateway === 'direct' ? 'https://api.aerodatabox.com' : 'https://prod.api.market/api/v1/aedbx/aerodatabox';
    const url = new URL(`${base}/flights/number/${encodeURIComponent(query.number)}/${query.date}`);
    url.search = new URLSearchParams({ dateLocalRole: 'Departure', withAircraftImage: 'false', withLocation: 'false', withFlightPlan: 'false' }).toString();
    const header = this.gateway === 'direct' ? 'X-Api-Key' : 'x-api-market-key';
    let response: Response;
    try {
      response = await this.fetcher(url, { headers: { [header]: this.key, Accept: 'application/json' }, signal: AbortSignal.timeout(15_000), redirect: 'error' });
    } catch { throw new ServiceError(503, 'provider_unreachable'); }
    if (response.status === 204) return [];
    if (response.status === 429) throw new ServiceError(429, 'provider_busy');
    if ([401, 402, 403].includes(response.status)) throw new ServiceError(503, 'provider_unavailable');
    if (response.status !== 200) throw new ServiceError(502, 'provider_failed');
    const reader = response.body?.getReader();
    if (!reader) throw new ServiceError(502, 'provider_invalid_response');
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 1_000_000) { await reader.cancel(); throw new ServiceError(502, 'provider_response_too_large'); }
        chunks.push(value);
      }
    } catch (error) {
      if (error instanceof ServiceError) throw error;
      throw new ServiceError(503, 'provider_unreachable');
    }
    let payload: unknown;
    try { payload = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch { throw new ServiceError(502, 'provider_invalid_response'); }
    if (!Array.isArray(payload) || payload.length > 100) throw new ServiceError(502, 'provider_invalid_response');
    const fetchedAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
    const results: FlightSchedule[] = [];
    const seen = new Set<string>();
    for (const value of payload) {
      const flight = object(value);
      const departure = stop(flight.departure);
      const arrival = stop(flight.arrival);
      const number = text(flight.number, 12).toUpperCase().replace(/\s/g, '');
      if (!departure || !arrival || !number) continue;
      try { parseQuery(number, query.date); } catch { continue; }
      if (departure.local && departure.local.slice(0, 10) !== query.date) continue;
      const id = [number, departure.airport, departure.local, arrival.airport, arrival.local].join('|');
      if (seen.has(id)) continue;
      seen.add(id);
      results.push({ number, airline: text(object(flight.airline).name, 160), departure, arrival,
        status: text(flight.status, 80) || 'Unknown', provider: 'AeroDataBox', fetchedAt });
    }
    return results.slice(0, 50);
  }
}
