import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { flightServer } from '../src/server.ts';
import { ServiceError } from '../src/provider.ts';
import type { FlightProvider } from '../src/provider.ts';

async function running(provider: FlightProvider, maxCallsPerDay = 50) {
  const server = flightServer(provider, { maxCallsPerDay });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  assert.ok(address && typeof address !== 'string');
  return { server, url: `http://127.0.0.1:${address.port}` };
}

test('HTTP contract rejects invalid input before spending provider calls and enforces a daily cap', async () => {
  let calls = 0;
  const { server, url } = await running({ lookup: async () => { calls++; return []; } }, 1);
  try {
    assert.equal((await fetch(`${url}/v1/flights?number=BA178&date=2027-02-30`)).status, 400);
    assert.equal((await fetch(`${url}/v1/flights?number=BA178&date=2027-03-05&key=unexpected`)).status, 400);
    assert.equal(calls, 0);
    const response = await fetch(`${url}/v1/flights?number=BA178&date=2027-03-05`);
    assert.deepEqual(await response.json(), { version: 1, flights: [] });
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal((await fetch(`${url}/v1/flights?number=BA179&date=2027-03-05`)).status, 429);
    assert.equal(calls, 1);
  } finally { server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve())); }
});

test('provider details and credentials are absent from HTTP errors', async () => {
  const { server, url } = await running({ lookup: async () => { throw new ServiceError(503, 'provider_unavailable'); } });
  try {
    const response = await fetch(`${url}/v1/flights?number=BA178&date=2027-03-05`);
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'provider_unavailable' });
  } finally { server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve())); }
});
