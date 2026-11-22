// HEIST · "vision" Edge Function: reads a payment screenshot (UPI app, bank SMS, receipt) with a vision model.
// The app sends { image: "data:image/jpeg;base64,..." , today: "YYYY-MM-DD" }.
// Answers { txns: [{ amount, type, merchant, date, note }], provider }.
// Secrets: OPENROUTER_API_KEY (uses OpenRouter's free router, which picks a free model that can read images),
//   OPENROUTER_MODEL (optional, default openrouter/free). Only if OPENROUTER_API_KEY is missing: GROQ_API_KEY with
//   VISION_MODEL (default qwen/qwen3.8-27b). ALLOWED_ORIGINS (shared with "ai"), VISION_PER_DAY (optional, default 60 per IP).
const ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") || "https://tejjj777.github.io")
  .split(",").map((o) => o.trim()).filter(Boolean);
const okOrigin = (o: string | null) => !!o && ORIGINS.some((a) => o === a || (a.endsWith("localhost") && o.startsWith(a)));
const OR_KEY = Deno.env.get("OPENROUTER_API_KEY");
const OR_MODEL = Deno.env.get("OPENROUTER_MODEL") || "openrouter/free";
const GROQ_MODEL = Deno.env.get("VISION_MODEL") || "qwen/qwen3.8-27b";
const PER_DAY = Number(Deno.env.get("VISION_PER_DAY") || 60);
const hits = new Map<string, number[]>();
function overLimit(ip: string) {
  const now = Date.now(), list = (hits.get(ip) || []).filter((t) => now - t < 86400000);
  if (list.length >= PER_DAY) { hits.set(ip, list); return true; }
  list.push(now); hits.set(ip, list);
  if (hits.size > 5000) hits.clear();
  return false;
}

const PROMPT = (today: string) => `You read screenshots of payments for a student budgeting app in India.
Today is ${today}. The image may be a UPI app screen (GPay, PhonePe, Paytm, BHIM), a bank SMS, a list of transactions, or a receipt.
Find every completed money transaction you can see. Ignore failed or pending payments, ads, offers and balances.
Reply with ONLY this JSON, no other text:
{"txns":[{"amount":number,"type":"debit"|"credit","merchant":string,"date":"YYYY-MM-DD","note":string}]}
Rules:
- amount: the rupee amount as a plain number (1,250.00 -> 1250). Never guess a number you cannot read.
- type: "debit" if money left the user (Paid to, Sent, Debited). "credit" if money came in (Received from, Credited).
- merchant: the person or business name exactly as shown, without "Paid to"/"Received from". Not the UPI ID unless no name is shown.
- date: from the screen. If only a day and month are shown, use the year from today. If no date is shown, use ${today}.
- note: a short label if the screen shows one (like "WiFi Split"), else "".
- If no transaction is visible, reply {"txns":[]}.`;

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  const CORS = {
    "Access-Control-Allow-Origin": okOrigin(origin) ? origin! : ORIGINS[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
  const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (!okOrigin(origin)) return json({ error: "not allowed from this site" }, 403);
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || "unknown";
  if (overLimit(ip)) return json({ error: "daily limit", reply: "You’ve scanned a lot today. Try again tomorrow." }, 429);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }
  const image = String(body?.image || "");
  if (!/^data:image\/(png|jpe?g|webp);base64,/.test(image)) return json({ error: "send image as a data URL" }, 400);
  if (image.length > 4_000_000) return json({ error: "image too big, shrink it first" }, 413);
  const today = /^\d{4}-\d{2}-\d{2}$/.test(body?.today) ? body.today : new Date().toISOString().slice(0, 10);

  const groqKey = Deno.env.get("GROQ_API_KEY");
  if (!OR_KEY && !groqKey) return json({ error: "no AI key set" }, 500);
  const useOR = !!OR_KEY;
  const model = useOR ? OR_MODEL : GROQ_MODEL;
  const url = useOR ? "https://openrouter.ai/api/v1/chat/completions" : "https://api.groq.com/openai/v1/chat/completions";
  const headers: Record<string, string> = { "Authorization": `Bearer ${useOR ? OR_KEY : groqKey}`, "Content-Type": "application/json" };
  if (useOR) { headers["HTTP-Referer"] = "https://tejjj777.github.io/heist/"; headers["X-Title"] = "HEIST"; }
  try {
    const r = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify({
        model,
        temperature: 0,
        max_tokens: 1200,
        // free models don't all support JSON mode, so the prompt asks for JSON and the reply is parsed below
        ...(useOR ? {} : { response_format: { type: "json_object" } }),
        messages: [{ role: "user", content: [
          { type: "text", text: PROMPT(today) },
          { type: "image_url", image_url: { url: image } },
        ] }],
      }),
      signal: AbortSignal.timeout(28000),
    });
    const raw = await r.text();
    if (!r.ok) return json({ error: "model error", status: r.status, detail: raw.slice(0, 300) }, 502);
    const reply = JSON.parse(raw);
    const content = String(reply?.choices?.[0]?.message?.content || "").replace(/<think>[\s\S]*?<\/think>/g, "");
    const used = reply?.model || model;
    const m = content.match(/\{[\s\S]*\}/);
    // a free model that didn't answer in JSON: let the app read it on the device instead
    if (!m) return json({ error: "model gave no JSON", provider: used }, 502);
    const parsed = JSON.parse(m[0]);
    const txns = (Array.isArray(parsed.txns) ? parsed.txns : [])
      .map((t: any) => ({
        amount: Math.round(Number(String(t.amount).replace(/[^\d.]/g, "")) * 100) / 100,
        type: t.type === "credit" ? "credit" : "debit",
        merchant: String(t.merchant || "").trim().slice(0, 60) || "UPI Payment",
        date: /^\d{4}-\d{2}-\d{2}$/.test(t.date) ? t.date : today,
        note: String(t.note || "").trim().slice(0, 60),
      }))
      .filter((t: any) => t.amount > 0 && t.amount < 10_000_000);
    return json({ txns, provider: (useOR ? "openrouter:" : "groq:") + used });
  } catch (e) {
    return json({ error: "vision failed", detail: String(e).slice(0, 200) }, 502);
  }
});
