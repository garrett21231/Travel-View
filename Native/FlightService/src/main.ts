import { AeroDataBoxProvider } from './provider.ts';
import { flightServer } from './server.ts';

const gateway = process.env.AERODATABOX_GATEWAY ?? 'direct';
if (!['direct', 'api-market'].includes(gateway)) throw new Error('Choose direct or api-market for AERODATABOX_GATEWAY.');
const port = Number(process.env.PORT ?? 8787);
const maximum = Number(process.env.MAX_PROVIDER_CALLS_PER_DAY ?? 50);
if (!Number.isInteger(port) || port < 1 || port > 65535 || !Number.isInteger(maximum) || maximum < 1) {
  throw new Error('Use a valid PORT and a positive daily call limit.');
}
const provider = new AeroDataBoxProvider(process.env.AERODATABOX_API_KEY ?? '', gateway as 'direct' | 'api-market');
const server = flightServer(provider, { maxCallsPerDay: maximum });
server.listen(port, '127.0.0.1', () => console.log(`Travel View flight service listening on http://localhost:${port}`));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close());
