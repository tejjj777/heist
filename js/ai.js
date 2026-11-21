/* HEIST · AI helper.
   Classic script: shares one global scope with the other js/ files (see README-AGENTS.md). */
'use strict';

/** URL of the Supabase Edge Function that handles AI requests (Session 2 requirement). */
const AI_URL = 'https://qmcwczyqhymyoesfsrzh.supabase.co/functions/v1/ai';

/**
 * Calls the AI edge function for a specific task.
 * Falls back to a local rejection/fallback if the network fails or times out.
 * 
 * @param {string} task - e.g. "import", "command", "budget"
 * @param {string|object} input - Text or JSON payload for the task
 * @returns {Promise<any>} The AI response object or null on failure (handled by caller fallback)
 */
/** Why the last AI call failed: 'offline', 'blocked' (site not allowed), 'busy' (server or model trouble) or ''. */
let aiLastError = '';

async function aiCall(task, input, timeoutMs = 10000) {
  aiLastError = '';
  if (typeof navigator !== 'undefined' && navigator.onLine === false) { aiLastError = 'offline'; return null; }   // offline: go straight to the on-device fallback
  const started = Date.now();
  // one retry: a cold server or a dropped connection usually works the second time
  for (let attempt = 0; attempt < 2; attempt++) {
    const left = timeoutMs - (Date.now() - started);
    if (left < 1500) break;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), left);   // a slow network never leaves the user waiting long
    try {
      const res = await fetch(AI_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ task, input }),
        signal: controller.signal
      });
      clearTimeout(timeout);
      if (res.status === 429) {   // daily limit reached: say so instead of pretending the AI is down
        const d = await res.json().catch(() => null);
        return { intent: 'chat', reply: (d && d.reply) || 'You’ve asked a lot today. Try again in a bit.' };
      }
      if (res.status === 403) { aiLastError = 'blocked'; console.warn('AI: this site is not on the allowed list (ALLOWED_ORIGINS)'); return null; }
      if (!res.ok) { aiLastError = 'busy'; console.warn(`AI edge function failed with status ${res.status}`); continue; }
      return await res.json();
    } catch (err) {
      clearTimeout(timeout);
      aiLastError = navigator.onLine === false ? 'offline' : location.protocol === 'file:' ? 'blocked' : 'busy';
      console.warn(err.name === 'AbortError' ? `AI call timed out after ${Math.round((Date.now() - started) / 1000)} seconds.` : 'AI call failed: ' + err.message);
      if (err.name === 'AbortError') break;   // out of time: no second try
    }
  }
  return null;
}

/** URL of the Supabase Edge Function that reads payment screenshots with a vision model. */
const VISION_URL = 'https://qmcwczyqhymyoesfsrzh.supabase.co/functions/v1/vision';

/** Shrinks an image file to at most 1280px on its longest side and returns a JPEG data URL. */
async function visionImage(file) {
  const bmp = await createImageBitmap(file);
  const s = Math.min(1, 1280 / Math.max(bmp.width, bmp.height));
  const c = document.createElement('canvas');
  c.width = Math.round(bmp.width * s); c.height = Math.round(bmp.height * s);
  const x = c.getContext('2d');
  x.fillStyle = '#FFFFFF'; x.fillRect(0, 0, c.width, c.height);
  x.drawImage(bmp, 0, 0, c.width, c.height);
  return c.toDataURL('image/jpeg', 0.85);
}

/**
 * Reads a payment screenshot with the AI. Returns an array of { amount, type, merchant, date, note },
 * or null if the AI couldn't be reached (the caller then reads it on the device with OCR).
 * The free AI plan handles about 2 screenshots a minute, so a busy answer waits once and tries again.
 */
async function aiReadScreenshot(file, onWait) {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return null;
  let image;
  try { image = await visionImage(file); } catch (e) { return null; }
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetch(VISION_URL, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ image, today: todayISO() }),
        signal: AbortSignal.timeout(30000)
      });
      const d = await res.json().catch(() => null);
      if (res.ok && d && Array.isArray(d.txns)) return d.txns;
      const busy = d && (d.status === 429 || /rate limit/i.test(d.detail || ''));
      if (!busy || attempt) return null;
      const wait = Math.min(30, Math.ceil(Number(((d.detail || '').match(/try again in ([\d.]+)s/i) || [])[1]) || 20) + 1);
      if (onWait) onWait(wait);
      await new Promise(r => setTimeout(r, wait * 1000));
    } catch (e) { console.warn('Screenshot AI failed', e); return null; }
  }
  return null;
}
