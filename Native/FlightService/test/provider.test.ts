import { test } from 'node:test';
import assert from 'node:assert/strict';
import { AeroDataBoxProvider, parseQuery, ServiceError } from '../src/provider.ts';

const fixture = {
  number: 'NZ 8', airline: { name: 'Air New Zealand' }, status: 'Unknown',
  departure: { airport: { iata: 'AKL', timeZone: 'Pacific/Auckland' }, scheduledTime: { local: '2027-03-05 09:30+13:00' } },
  arrival: { airport: { iata: 'SFO', timeZone: 'America/Los_Angeles' }, scheduledTime: { local: '2027-03-04 22:15-08:00' } }
};

test('validates calendar days and normalizes a flight number before provider access', () => {
  assert.deepEqual(parseQuery(' nz 8 ', '2027-03-05'), { number: 'NZ8', date: '2027-03-05' });
  for (const [number, date] of [['../../key', '2027-03-05'], ['NZ8', '2027-02-30'], ['12345', '2027-03-05']]) {
    assert.throws(() => parseQuery(number!, date!), ServiceError);
  }
});

test('direct gateway authenticates server-side, preserves local times and deduplicates legs', async () => {
  const fetcher: typeof fetch = async (input, options) => {
    const url = new URL(String(input));
    assert.equal(url.origin, 'https://api.aerodatabox.com');
    assert.equal(url.pathname, '/flights/number/NZ8/2027-03-05');
    assert.equal(url.searchParams.get('dateLocalRole'), 'Departure');
    assert.equal(new Headers(options?.headers).get('X-Api-Key'), 'test-secret');
    return Response.json([fixture, fixture]);
  };
  const flights = await new AeroDataBoxProvider('test-secret', 'direct', fetcher).lookup(parseQuery('NZ8', '2027-03-05'));
  assert.equal(flights.length, 1);
  assert.equal(flights[0]!.departure.local, '2027-03-05T09:30');
  assert.equal(flights[0]!.arrival.local, '2027-03-04T22:15');
});

test('empty responses, partial times, authentication failures and throttling stay distinct', async () => {
  const query = parseQuery('NZ8', '2027-03-05');
  for (const [status, expected] of [[401, 503], [402, 503], [429, 429], [500, 502]]) {
    const provider = new AeroDataBoxProvider('secret', 'direct', async () => new Response('private provider error', { status }));
    await assert.rejects(provider.lookup(query), (error: ServiceError) => error.status === expected && !error.message.includes('private'));
  }
  assert.deepEqual(await new AeroDataBoxProvider('key', 'direct', async () => new Response(null, { status: 204 })).lookup(query), []);
  const partial = { ...fixture, arrival: { airport: { iata: 'SFO' } } };
  const flights = await new AeroDataBoxProvider('key', 'direct', async () => Response.json([partial])).lookup(query);
  assert.equal(flights[0]!.arrival.local, null);
});

test('API.Market remains an explicit optional gateway and does not receive a direct header', async () => {
  const provider = new AeroDataBoxProvider('market-test-key', 'api-market', async (input, options) => {
    assert.equal(new URL(String(input)).origin, 'https://prod.api.market');
    assert.equal(new Headers(options?.headers).get('x-api-market-key'), 'market-test-key');
    assert.equal(new Headers(options?.headers).has('X-Api-Key'), false);
    return Response.json([]);
  });
  assert.deepEqual(await provider.lookup(parseQuery('BA178', '2027-03-05')), []);
});
