import { GroqPool } from '../_shared/groq_pool.ts';
const groqPool = new GroqPool([Deno.env.get('GROQ_API_KEY') || '', ...(Deno.env.get('GROQ_FALLBACK_KEYS') || '').split(',')]);
// HEIST · AI helper (Supabase Edge Function "ai").
// The app sends { task: "command", input: { text, context, today } }, or { task: "plan", input: { messages, currency, today } } for the planner. This asks an AI model to
// understand the message and answers with JSON the app can act on, plus a short reply to show.
// Secrets (Edge Functions → Secrets):
//   GEMINI_API_KEY (needed for Gemini), GEMINI_MODEL (optional, tried first)
//   GROQ_API_KEY (recommended: fast, free at console.groq.com), GROQ_MODEL (optional)
// Order: Groq (if GROQ_API_KEY is set), then GEMINI_MODEL, then other Gemini Flash models on this key
// (each has its own free quota). A busy (503) or out-of-quota (429) model is skipped, so one bad model can't take the AI down.
// Usage limits (so nobody else can burn the AI quota):
//   ALLOWED_ORIGINS (optional secret): comma-separated sites allowed to call this. Defaults below.
//   AI_PER_10_MIN / AI_PER_DAY (optional secrets): requests allowed per person (by IP). Defaults 20 and 150.
const ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ||
  "https://tejjj777.github.io,capacitor://localhost,https://localhost,http://localhost")
  .split(",").map((o) => o.trim()).filter(Boolean);
const okOrigin = (o: string | null) => !!o && ORIGINS.some((a) => o === a || (a.endsWith("localhost") && o.startsWith(a)));
let CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": ORIGINS[0],
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

// Per-IP counters. They live in this function's memory, so they reset when Supabase restarts it;
// good enough to stop one person or script from draining the free quota.
const PER_10 = Number(Deno.env.get("AI_PER_10_MIN") || 20), PER_DAY = Number(Deno.env.get("AI_PER_DAY") || 150);
const hits = new Map<string, number[]>();
function overLimit(ip: string) {
  const now = Date.now(), day = 24 * 60 * 60 * 1000;
  const list = (hits.get(ip) || []).filter((t) => now - t < day);
  const recent = list.filter((t) => now - t < 10 * 60 * 1000).length;
  if (recent >= PER_10 || list.length >= PER_DAY) { hits.set(ip, list); return true; }
  list.push(now); hits.set(ip, list);
  if (hits.size > 5000) for (const k of hits.keys()) { hits.delete(k); if (hits.size < 4000) break; }
  return false;
}

const SYSTEM = (today: string, currency: string) => `You are the friendly money buddy inside a budgeting app for college students.
Today is ${today}. The student's money is in ${currency}. Always write amounts in ${currency}, never another currency.
Read the student's message and the CONTEXT (their real numbers), then reply with ONLY one JSON object:
{"intent":"add|afford|ask|budget|whatif|chat","amount":number,"note":string,"categoryName":string,"withPerson":string,"split":boolean,"item":string,"dayOffset":number,"period":"today|this week|this month","reductionAmount":number,"reply":string}
Pick the intent:
- add: they spent or paid something ("spent 120 on chai"). note = what it was, 1 to 4 words. split=true and withPerson when they split it with someone.
- afford: "can I afford ...". amount, item, dayOffset = days from today until it happens (0 = today).
- ask: "how much did I spend on ...". categoryName and period.
- budget: set a limit for a category. amount and categoryName.
- whatif: "what if I stop/cut ...". categoryName and reductionAmount = money saved per day.
- chat: anything else: planning something (a trip, a party, a month, a savings plan), tips, how-to and why questions, greetings, explaining their numbers. A message that asks to PLAN something is chat, not afford, even when it has a budget in it.
Leave out fields that don't apply.
"reply" is ALWAYS required. Usually 1 to 3 short, warm, plain sentences. For a plan or a list of tips, use up to 10 short lines, each starting with "- ", separated by \n. A plan with a budget splits the money into rough amounts that add up to that budget, and says if the budget looks tight. Use CONTEXT to say whether they can afford it.
Write "reply" in the SAME language as the MESSAGE. A message written in English gets an English reply, even if category names in CONTEXT are in another language. Only reply in Hinglish when the message itself is Hinglish, and then use English letters, not Devanagari.
Use only numbers from CONTEXT; never invent balances or spending. No em dashes. At most one emoji.
Don't give investment or loan advice beyond simple saving tips.`;

// task "plan": the planner asks every question that changes the plan or the cost, then returns a costed plan.
// It plans from what the student wants to do, never from their balance (the app sends no balance for this task).
const PLAN_SYSTEM = (today: string, currency: string) => `You are the planner inside HEIST, a money app for students. Today is ${today}.
The student tells you something they want to do: a trip, a movie, a party, a date, a concert, a fest, a birthday, a gift, a purchase, anything.
Your job: ask every question that changes the plan or what it costs, then build the plan and the budget it needs.
Plan from what they want to do. Never ask about or use their balance, savings or money in hand.
All money is in ${currency}. Write every amount in ${currency}.
Reply with ONLY one JSON object, in one of two shapes.

1) Questions:
{"stage":"ask","title":string,"reply":string,"questions":[{"id":string,"q":string,"type":"text"|"number"|"choice"|"date","options":[string],"placeholder":string}]}
- Ask everything you need in ONE go, most important first, 6 to 14 questions. Cover who, where, when, how long, how many people and who pays, how they get there and around, where they stay, food and drinks, tickets and activities, shopping and gifts, anything already booked or paid, and a budget they have in mind (optional).
  Movie example: which movie and theatre or format, how many people, who pays, seat type, snacks, getting there and back, food before or after.
  Trip example: from where to where, dates and nights, how many people and how costs are shared, travel mode and class, stay type, rooms, meals, activities, local transport, shopping, travel insurance or extras.
- Use "choice" with 2 to 5 short options where it fits, "number" for counts and money, "date" for dates. Keep each question short and plain.
- Never ask something the conversation already answers.
- A second round is allowed only when an answer opens new questions that change the cost a lot (at most 5 more). After two rounds of questions, always make the plan.

2) The plan:
{"stage":"plan","title":string,"reply":string,"items":[{"name":string,"group":string,"qty":number,"unit":number,"note":string}],"bufferPct":number,"assumptions":[string],"tips":[string]}
- List every cost as its own line: qty times unit price, with realistic prices for that place, date and style. group is one of Travel, Stay, Food, Tickets, Activities, Shopping, Other.
- If costs are shared, plan the student's own share and say so in assumptions.
- If an answer was "not sure" or blank, pick a sensible default and say it in assumptions.
- bufferPct: 5 to 15, for things that cost more than expected.
- tips: up to 5 short ways to spend less on this plan.
- reply: 1 to 3 short sentences. If they gave a budget, say whether the plan fits it and what to cut if not.
- Prices are estimates; never claim they are exact. Do not add up the total; the app does the math.

No em dashes. At most one emoji in reply.`;

const DEADLINE_MS = 14000;   // total time for all attempts; the app waits a little longer than this

// Gemini models this key can use, found once per warm instance (no guessing model names).
let geminiModels: string[] | null = null;
async function listGeminiModels(key: string): Promise<string[]> {
  if (geminiModels) return geminiModels;
  try {
    const r = await fetch("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200", {
      headers: { "x-goog-api-key": key },
      signal: AbortSignal.timeout(3000),
    });
    if (!r.ok) return [];
    const d = await r.json();
    const names: string[] = (d.models || [])
      .filter((m: any) => (m.supportedGenerationMethods || []).includes("generateContent"))
      .map((m: any) => String(m.name || "").replace(/^models\//, ""))
      .filter((n: string) => /^gemini-[\d.]+-flash/.test(n) && !/image|tts|audio|live|thinking|exp/.test(n));
    // newest first, full Flash before Flash-Lite
    names.sort((a, b) => {
      const va = parseFloat(a.slice(7)), vb = parseFloat(b.slice(7));
      if (vb !== va) return vb - va;
      return Number(/lite/.test(a)) - Number(/lite/.test(b)) || a.length - b.length;
    });
    geminiModels = names;
    return names;
  } catch {
    return [];
  }
}

type Attempt = { provider: string; model: string; status: number | string; detail?: string };

// Remembered while this instance stays warm: models to skip for now, and the last one that worked.
const skipUntil = new Map<string, number>();
let lastGood = "";
function rest(model: string, status: number | string, detail = "") {
  let ms = 60_000;
  if (status === 429) {
    const m = detail.match(/retry in (?:(\d+)h)?(?:(\d+)m)?(?:([\d.]+)s)?/);
    if (m) ms = ((+(m[1] || 0)) * 3600 + (+(m[2] || 0)) * 60 + Math.ceil(+(m[3] || 0))) * 1000 || ms;
  } else if (status === 400 || status === 403 || status === 404) ms = 6 * 3600_000;   // model not usable on this key
  else if (status === "timeout") ms = 3 * 60_000;
  skipUntil.set(model, Date.now() + Math.min(ms, 24 * 3600_000));
}

async function askGemini(key: string, model: string, system: string, user: string, ms: number) {
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
    method: "POST",
    signal: AbortSignal.timeout(ms),
    headers: { "Content-Type": "application/json", "x-goog-api-key": key },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: "user", parts: [{ text: user }] }],
      generationConfig: { responseMimeType: "application/json", temperature: 0.4, maxOutputTokens: 2500 },
    }),
  });
  if (!r.ok) return { ok: false as const, status: r.status, detail: (await r.text()).slice(0, 500) };
  const g = await r.json();
  const out = g?.candidates?.[0]?.content?.parts?.map((p: any) => p.text || "").join("") || "";
  return out ? { ok: true as const, out } : { ok: false as const, status: "empty", detail: JSON.stringify(g).slice(0, 300) };
}

async function askGroq(_key: string, model: string, system: string, user: string, ms: number) {
  try {
    const g = await groqPool.complete({model, messages: [{role:'system', content:system}, {role:'user', content:user}],
      response_format: {type:'json_object'}, temperature:0.4, max_tokens:4000,
      ...(model.startsWith('openai/gpt-oss') ? {reasoning_effort:'low'} : {})}, ms);
    const out = g?.choices?.[0]?.message?.content || '';
    return out ? {ok:true as const, out} : {ok:false as const, status:'empty', detail:'Empty result'};
  } catch {
    return {ok:false as const, status:503, detail:'Groq keys unavailable; trying the next configured provider.'};
  }
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  CORS = { ...CORS, "Access-Control-Allow-Origin": okOrigin(origin) ? origin! : ORIGINS[0] };
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!okOrigin(origin)) return json({ error: "not allowed from this site" }, 403);
  const ip = (req.headers.get("x-forwarded-for") || req.headers.get("cf-connecting-ip") || "unknown").split(",")[0].trim();
  if (overLimit(ip)) return json({ error: "limit", reply: "You’ve asked a lot today. Try again in a bit." }, 429);
  const gKey = Deno.env.get("GEMINI_API_KEY");
  const qKey = Deno.env.get("GROQ_API_KEY") || groqPool.keys[0];
  if (!gKey && !qKey) return json({ error: "No AI key set (GEMINI_API_KEY or GROQ_API_KEY)" }, 500);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "bad JSON" }, 400); }
  const task = body?.task;
  if (task !== "command" && task !== "plan") return json({ error: "unknown task" }, 400);
  const input = body.input;
  const today = String(input?.today || new Date().toDateString()).slice(0, 40);
  const CUR_NAMES: Record<string, string> = { INR: "Indian rupees (₹)", USD: "US dollars ($)", EUR: "euros (€)", GBP: "British pounds (£)", CAD: "Canadian dollars", AUD: "Australian dollars", SGD: "Singapore dollars", AED: "UAE dirhams", JPY: "Japanese yen (¥)" };
  let system: string, user: string;
  if (task === "plan") {
    // input: { messages: [{ role: "user" | "assistant", text }], currency, today }
    const msgs = Array.isArray(input?.messages) ? input.messages.slice(-12) : [];
    const convo = msgs.map((m: any) => `${m?.role === "assistant" ? "HEIST" : "STUDENT"}: ${String(m?.text ?? "").slice(0, 2500)}`).join("\n\n").slice(-9000).trim();
    if (!convo) return json({ error: "empty message" }, 400);
    const cur = String(input?.currency || "INR").slice(0, 8);
    const rounds = msgs.filter((m: any) => m?.role === "assistant").length;
    system = PLAN_SYSTEM(today, CUR_NAMES[cur] || cur);
    user = `CONVERSATION:\n${convo}\n\nQUESTION ROUNDS SO FAR: ${rounds}${rounds >= 2 ? " (make the plan now)" : ""}`;
  } else {
    const text = String(typeof input === "string" ? input : input?.text ?? "").slice(0, 2000).trim();
    if (!text) return json({ error: "empty message" }, 400);
    const context = typeof input === "object" && input?.context ? JSON.stringify(input.context).slice(0, 6000) : "{}";
    const cur = typeof input === "object" && input?.context?.currency ? String(input.context.currency).slice(0, 8) : "INR";
    system = SYSTEM(today, CUR_NAMES[cur] || cur);
    user = `CONTEXT: ${context}\n\nMESSAGE: ${text}`;
  }

  const started = Date.now();
  const deadline = task === "plan" ? 26000 : DEADLINE_MS;
  const left = () => deadline - (Date.now() - started);
  const tried: Attempt[] = [];

  // Build the queue: Groq first when its key is set (fast, bigger free quota), then the chosen
  // Gemini model, then other Gemini Flash models on the key.
  const queue: { provider: "gemini" | "groq"; model: string }[] = [];
  if (qKey) {
    // Llama 3.3 70B is Enterprise-only on Groq now; GPT OSS is on every plan
    const first = Deno.env.get("GROQ_MODEL") || "openai/gpt-oss-120b";
    for (const m of [first, "openai/gpt-oss-20b"]) if (!queue.some((q) => q.model === m)) queue.push({ provider: "groq", model: m });
  }
  if (gKey) {
    const first = Deno.env.get("GEMINI_MODEL") || "gemini-3.8-flash";
    queue.push({ provider: "gemini", model: first });
    for (const m of (await listGeminiModels(gKey)).slice(0, 4)) if (m !== first) queue.push({ provider: "gemini", model: m });
  }
  // the last model that answered goes first; models resting after a 429 / timeout are skipped
  queue.sort((a, b) => Number(b.model === lastGood) - Number(a.model === lastGood));
  const live = queue.filter((q) => (skipUntil.get(q.model) || 0) < Date.now());
  if (live.length) queue.splice(0, queue.length, ...live);
  for (let i = 0; i < queue.length; i++) {
    const { provider, model } = queue[i];
    const ms = Math.min(task === "plan" ? (i === 0 ? 16000 : 9000) : (i === 0 ? 8000 : 5000), left());
    if (ms < 1500) break;
    try {
      const res = provider === "gemini"
        ? await askGemini(gKey!, model, system, user, ms)
        : await askGroq(qKey!, model, system, user, ms);
      if (!res.ok) {
        tried.push({ provider, model, status: res.status, detail: res.detail });
        rest(model, res.status, res.detail);
        // 404 / 400 = this model name doesn't work on this key; 429 / 503 / 5xx = busy or out of quota. Try the next one.
        continue;
      }
      let parsed: any;
      try { parsed = JSON.parse(res.out); } catch { parsed = task === "plan" ? null : { intent: "chat", reply: res.out.slice(0, 400) }; }
      if (task === "plan" && (!parsed || (parsed.stage !== "ask" && parsed.stage !== "plan"))) {
        tried.push({ provider, model, status: "bad plan JSON" });   // try the next model rather than show junk
        continue;
      }
      if (!parsed || typeof parsed !== "object") parsed = { intent: "chat", reply: String(res.out).slice(0, 400) };
      if (typeof parsed.reply === "string") parsed.reply = parsed.reply.replace(/\s*—\s*/g, ", ").slice(0, 1200);
      parsed.provider = `${provider}:${model}`;
      if (tried.length) parsed.skipped = tried.map((t) => `${t.model} ${t.status}`);
      lastGood = model;
      return json(parsed);
    } catch (e) {
      const status = (e as Error).name === "TimeoutError" || (e as Error).name === "AbortError" ? "timeout" : "fetch failed";
      tried.push({ provider, model, status });
      rest(model, status);
    }
  }
  const quota = tried.some((t) => t.status === 429);
  return json({ error: quota ? "quota" : "unavailable", tried }, 502);
});
