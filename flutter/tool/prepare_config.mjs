import { readFile, writeFile } from 'node:fs/promises';
const source = await readFile('../js/sync.js', 'utf8');
const url = source.match(/const SYNC_URL = '([^']+)'/)?.[1];
const key = source.match(/const SYNC_KEY = '([^']+)'/)?.[1];
if (!url?.startsWith('https://') || !key?.startsWith('sb_publishable_')) throw Error('Expected public HEIST backend configuration, never a service-role secret.');
await writeFile('config.local.json', JSON.stringify({SUPABASE_URL: url, SUPABASE_PUBLISHABLE_KEY: key, AUTH_REDIRECT_URL: 'https://tejjj777.github.io/heist/', AI_URL: `${url}/functions/v1/ai`, VISION_URL: `${url}/functions/v1/vision`}, null, 2));
console.log('Public backend configuration prepared.');
