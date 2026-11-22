import test from 'node:test';
import assert from 'node:assert/strict';
import {GroqPool, objectFromText, safeSources} from '../supabase/functions/_shared/groq_pool.ts';

test('quota fallback preserves the full request and cools exhausted keys',async()=>{
  const seen=[]; let now=0;
  const send=async(_url,options)=>{
    seen.push({key:options.headers.Authorization,body:options.body});
    return options.headers.Authorization==='Bearer primary'
      ?new Response('{}',{status:429,headers:{'retry-after':'120'}})
      :Response.json({choices:[{message:{content:'ok'}}]});
  };
  const pool=new GroqPool(['primary','fallback','fallback'],send,()=>now);
  const payload={messages:[{role:'user',content:'saved research and original brief'}]};
  await pool.complete(payload);await pool.complete(payload);
  assert.deepEqual(seen.map(x=>x.key),['Bearer primary','Bearer fallback','Bearer fallback']);
  assert.equal(seen[0].body,seen[1].body);
  now=121000;await pool.complete(payload);
  assert.equal(seen[3].key,'Bearer primary');
});
test('configuration errors do not burn through every key',async()=>{
  let calls=0;
  const pool=new GroqPool(['one','two'],async()=>{calls++;return new Response('{}',{status:400});});
  await assert.rejects(pool.complete({}),/configuration/);assert.equal(calls,1);
});
test('network failures fall back; no raw credential or provider error leaks',async()=>{
  const pool=new GroqPool(['secret-one','secret-two'],async()=>{throw new Error('secret-one');});
  await assert.rejects(pool.complete({}),e=>!e.message.includes('secret')&&e.message.includes('saved progress'));
});
test('search JSON extraction and safe links reject malformed / dangerous sources',()=>{
  assert.equal(objectFromText('Search snippets\n```json\n{"summary":"ok"}\n```').summary,'ok');
  assert.throws(()=>objectFromText('unfinished {"summary":'));
  assert.equal(safeSources([{url:'javascript:alert(1)'},{url:'https://a:b@example.com'},
    {url:'https://tourism.gov.in',title:'Tourism'},{url:'https://tourism.gov.in'}]).length,1);
});

let handler;let modelCalls=0;
globalThis.Deno={env:{get:name=>({SUPABASE_URL:'https://example.supabase.co',SUPABASE_ANON_KEY:'public',GROQ_API_KEY:'fake'})[name]},serve:fn=>handler=fn};
const originalFetch=globalThis.fetch;
globalThis.fetch=async(url,options)=>{
  if(String(url).endsWith('/auth/v1/user'))return Response.json({id:'test-user'});
  modelCalls++;
  const body=JSON.parse(options.body);
  if(body.tools) {
    assert.equal(body.tool_choice,'required');
    return Response.json({choices:[{message:{content:JSON.stringify({summary:'Official visitor information.',sources:[{title:'Tourism',url:'https://tourism.gov.in'},{title:'Rail',url:'https://www.irctc.co.in'}]})}}]});
  }
  return Response.json({choices:[{message:{content:JSON.stringify({days:[{day:1,stops:[{name:'Museum',cost:100,sourceUrl:'https://invented.invalid'}]}],budget:[{category:'Transport',amount:100}]})}}]});
};
await import('../supabase/functions/travel/index.ts');
test('endpoint rejects anonymous, foreign-origin and invalid trip requests',async()=>{
  assert.equal((await handler(new Request('https://local',{method:'POST',body:'{}'}))).status,401);
  assert.equal((await handler(new Request('https://local',{method:'POST',headers:{origin:'https://evil.example'},body:'{}'}))).status,403);
  assert.equal((await handler(new Request('https://local',{method:'POST',headers:{authorization:'Bearer test'},body:'{"stage":"research","trip":{}}'}))).status,400);
  assert.equal(modelCalls,0);
});
test('endpoint researches with browser search then builds only from saved citations',async()=>{
  const trip={destination:'Hyderabad',startDate:'2026-12-01',days:1,travelers:2,budget:5000,currency:'INR'};
  const request=body=>new Request('https://local',{method:'POST',headers:{authorization:'Bearer test'},body:JSON.stringify(body)});
  const r=await handler(request({stage:'research',trip}));assert.equal(r.status,200);
  const research=await r.json();assert.equal(research.sources.length,2);
  const p=await handler(request({stage:'plan',trip,research}));assert.equal(p.status,200);
  assert.equal((await p.json()).plan.days[0].stops[0].sourceUrl,'');
  assert.equal(modelCalls,2);
});
test.after(()=>{globalThis.fetch=originalFetch;delete globalThis.Deno;});
