// Server-only key rotation. Never return provider keys or raw error payloads.
export class GroqPool {
  keys: string[];
  cooling = new Map<string, number>();
  private send: typeof fetch;
  private clock: () => number;
  constructor(keys: string[], send: typeof fetch = fetch, clock = Date.now) {
    this.send = send;
    this.clock = clock;
    this.keys = [...new Set(keys.map(k => k.trim()).filter(Boolean))];
  }
  async complete(payload: Record<string, unknown>, milliseconds = 45000) {
    const deadline = this.clock() + milliseconds;
    for (const key of this.keys) {
      if ((this.cooling.get(key) || 0) > this.clock()) continue;
      const left = deadline - this.clock();
      if (left < 1000) break;
      try {
        const r = await this.send('https://api.groq.com/openai/v1/chat/completions', {
          method: 'POST', signal: AbortSignal.timeout(Math.min(left, 22000)),
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
          body: JSON.stringify(payload),
        });
        if (r.ok) return await r.json();
        if (![401, 403, 408, 429].includes(r.status) && r.status < 500) {
          throw new Error('Provider rejected the request configuration.');
        }
        const seconds = Number(r.headers.get('retry-after'));
        this.cooling.set(key, this.clock() + (r.status === 401 || r.status === 403
          ? 3600000 : Math.min(3600000, Math.max(60000, Number.isFinite(seconds) ? seconds * 1000 : 60000))));
      } catch (e) {
        if ((e as Error).message === 'Provider rejected the request configuration.') throw e;
        this.cooling.set(key, this.clock() + 60000);
      }
    }
    throw new Error('Travel AI is temporarily unavailable. Your saved progress is safe; retry later.');
  }
}

export function objectFromText(text: string): Record<string, any> {
  // Search can prepend snippets or Markdown. Accept only a complete JSON object.
  for (let start = text.indexOf('{'); start >= 0; start = text.indexOf('{', start + 1)) {
    for (let end = text.lastIndexOf('}'); end > start; end = text.lastIndexOf('}', end - 1)) {
      try { return JSON.parse(text.slice(start, end + 1)); } catch { /* next candidate */ }
    }
  }
  throw new Error('The agent returned an incomplete result. Retry this step.');
}

export function safeSources(value: unknown): { title: string; url: string }[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  return value.filter(s => {
    try {
      const u = new URL(s.url);
      if (u.protocol !== 'https:' || u.username || u.password || !u.hostname.includes('.') || seen.has(u.href)) return false;
      seen.add(u.href); return true;
    } catch { return false; }
  }).slice(0, 15).map(s => ({title: String(s.title || s.url).slice(0, 180), url: String(s.url).slice(0, 2000)}));
}
