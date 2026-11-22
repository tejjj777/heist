// Generate synthetic compatibility vectors using the inspected original client.
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
const source = await readFile('../js/sync.js','utf8');
const helpers = source.slice(source.indexOf('const TXT_E'), source.indexOf('/* ---------- Talking to Supabase'));
const context = vm.createContext({crypto:webcrypto,TextEncoder,TextDecoder,Uint8Array,Response,Blob,btoa,atob,window:{CompressionStream,DecompressionStream},KDF_ITER:600000});
const vector = await vm.runInContext(helpers + `
(async()=>{
  const password='synthetic-test-passphrase', keys=await newVaultKeys(password);
  const document={version:1,currency:'INR',budget:{categories:[],expenses:[]},compatibility:'original JavaScript ↔ Flutter'};
  return {password,recovery:keys.recovery,key:keys.dek,row:{...keys.fields,data:await lockData(JSON.stringify(document),keys.dek)}};
})()`,context);
await mkdir('test/fixtures',{recursive:true});
await writeFile('test/fixtures/legacy-vault.json',JSON.stringify(vector,null,2));
console.log('Generated synthetic vault with the original JavaScript crypto helpers.');
