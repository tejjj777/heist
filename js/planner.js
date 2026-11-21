/* HEIST · Planner: "I want to go to Goa" → the AI asks every question that changes the plan,
   then returns a costed plan. The app does the math (F.planTotals) and can save the total as a goal.
   Plans are built from what the student wants to do, not from their balance: no money data is sent.
   Classic script: shares one global scope with the other js/ files (see README-AGENTS.md). */
'use strict';

const PLAN_EXAMPLES = ['A 3 day Goa trip with 3 friends', 'Movie night this Saturday', 'My birthday party', 'A weekend trek near Hyderabad'];
let planner = null;   // { messages, step: 'start'|'ask'|'plan'|'busy'|'error', title, questions, answers, plan, error }

/** Looks like "I want to plan / go on / go to …" rather than a spend or a question about past spending. */
function isPlanRequest(text) {
  const t = String(text || '').toLowerCase();
  if (/\b(spent|paid|bought|log|add)\b/.test(t) || /^\s*\d/.test(t)) return false;
  if (/\bhow much did i\b/.test(t)) return false;
  return /\b(plan|planning|trip|travel|vacation|holiday|tour|trek|movie|cinema|party|birthday|date night|concert|fest|festival|outing|wedding|picnic|road ?trip|getaway|going (to|on|for)|want to go|wanna go)\b/.test(t);
}

function openPlanner(firstText) {
  planner = { messages: [], step: 'start', title: '', questions: [], answers: {}, plan: null, error: '' };
  openModal({ title: 'Plan it', body: '<div id="planner-body"></div>', hideSubmit: true, cancelLabel: 'Close', wide: true, onMount: form => {
    form.addEventListener('submit', e => { e.preventDefault(); e.stopImmediatePropagation(); }, true);   // the planner has its own buttons
    renderPlanner();
    if (firstText && firstText.trim()) planStart(firstText.trim());
  } });
}

async function planAsk() {
  planner.step = 'busy'; renderPlanner();
  const res = typeof aiCall === 'function'
    ? await aiCall('plan', { messages: planner.messages, currency: state.currency || 'INR', today: new Date().toDateString() }, 30000)
    : null;
  if (!document.getElementById('planner-body')) return;   // closed while waiting
  if (res && res.stage === 'ask' && Array.isArray(res.questions) && res.questions.length) {
    planner.title = String(res.title || planner.title || 'Your plan').slice(0, 80);
    planner.questions = res.questions.slice(0, 16).map((q, i) => ({
      id: String(q.id || 'q' + i).replace(/[^\w-]/g, '') || 'q' + i,
      q: String(q.q || '').slice(0, 200),
      type: ['text', 'number', 'choice', 'date'].includes(q.type) ? q.type : 'text',
      options: Array.isArray(q.options) ? q.options.slice(0, 6).map(o => String(o).slice(0, 60)) : [],
      placeholder: String(q.placeholder || '').slice(0, 60)
    })).filter(q => q.q);
    planner.reply = String(res.reply || '').slice(0, 400);
    planner.messages.push({ role: 'assistant', text: (planner.reply ? planner.reply + '\n' : '') + 'Questions:\n' + planner.questions.map(q => '- ' + q.q).join('\n') });
    planner.step = 'ask';
  } else if (res && res.stage === 'plan' && Array.isArray(res.items)) {
    const items = res.items.slice(0, 40).map(x => ({
      name: String(x.name || 'Item').slice(0, 80), group: String(x.group || 'Other').slice(0, 20),
      qty: Number(x.qty) > 0 ? Number(x.qty) : 1, unit: Number(x.unit) >= 0 ? Number(x.unit) : 0, note: String(x.note || '').slice(0, 120)
    })).filter(x => x.unit > 0);
    if (!items.length) { planner.step = 'error'; planner.error = 'The AI sent a plan with no costs. Try again.'; renderPlanner(); return; }
    planner.title = String(res.title || planner.title || 'Your plan').slice(0, 80);
    planner.plan = {
      items, bufferPct: Math.min(25, Math.max(0, Number(res.bufferPct) || 10)),
      reply: String(res.reply || '').slice(0, 500),
      assumptions: (Array.isArray(res.assumptions) ? res.assumptions : []).slice(0, 8).map(s => String(s).slice(0, 200)),
      tips: (Array.isArray(res.tips) ? res.tips : []).slice(0, 5).map(s => String(s).slice(0, 200))
    };
    planner.step = 'plan';
  } else {
    planner.step = 'error';
    const why = typeof aiLastError === 'string' ? aiLastError : '';
    planner.error = why === 'offline' ? 'You’re offline. The planner needs the internet.'
      : why === 'blocked' ? 'The planner only works when HEIST is opened from its website link, not from a file.'
      : (res && res.intent === 'chat' && res.reply) ? res.reply
      : 'The AI isn’t answering right now. Try again in a minute.';
  }
  renderPlanner();
}

function planStart(text) {
  planner.messages = [{ role: 'user', text }];
  planner.answers = {};
  planAsk();
}

function planSendAnswers(form) {
  const lines = planner.questions.map(q => {
    const el = form.querySelector(`[name="pq-${q.id}"]:checked`) || form.querySelector(`[name="pq-${q.id}"]:not([type=radio])`);
    let v = el ? String(el.value).trim() : '';
    if (q.type === 'choice') { const other = form.querySelector(`[name="pq-${q.id}-other"]`); if (other && other.value.trim()) v = other.value.trim(); }
    planner.answers[q.id] = v;
    return `- ${q.q} ${v || 'not sure'}`;
  });
  planner.messages.push({ role: 'user', text: 'My answers:\n' + lines.join('\n') });
  planAsk();
}

function planText() {
  const p = planner.plan, t = F.planTotals(p.items, p.bufferPct);
  const rows = p.items.map(x => `- ${x.name}${x.qty !== 1 ? ` (${x.qty} × ${fmtExact(x.unit)})` : ''}: ${fmtExact(x.qty * x.unit)}`);
  return `${planner.title}\n${rows.join('\n')}\n- Buffer (${p.bufferPct}%): ${fmtExact(t.buffer)}\nTotal needed: ${fmtExact(t.total)}` +
    (p.assumptions.length ? `\n\nAssumptions:\n${p.assumptions.map(a => '- ' + a).join('\n')}` : '') +
    (p.tips.length ? `\n\nWays to spend less:\n${p.tips.map(a => '- ' + a).join('\n')}` : '') + '\n\nMade with HEIST. Prices are estimates.';
}

function renderPlanner() {
  const box = document.getElementById('planner-body');
  if (!box || !planner) return;
  const P = planner;
  if (P.step === 'start' || P.step === 'error') {
    box.innerHTML = `
      <p class="muted">Tell me what you’re planning. I’ll ask everything that changes the cost, then make your plan and the budget you need.</p>
      ${P.step === 'error' ? `<p class="pl-error" role="alert">${esc(P.error)}</p>` : ''}
      <div class="field"><label for="pl-what" class="field-label">What are you planning?</label>
        <textarea id="pl-what" class="input" rows="3" maxlength="600" placeholder="A 3 day Goa trip with 3 friends in December">${esc((P.messages[0] && P.messages[0].text) || '')}</textarea></div>
      <div class="chip-row pl-examples">${PLAN_EXAMPLES.map(x => `<button type="button" class="chip" data-pl-example="${esc(x)}">${esc(x)}</button>`).join('')}</div>
      <div class="pl-actions"><button type="button" class="btn btn-primary" id="pl-go">${P.step === 'error' ? 'Try again' : 'Start planning'}</button></div>`;
    box.querySelectorAll('[data-pl-example]').forEach(b => b.addEventListener('click', () => { box.querySelector('#pl-what').value = b.dataset.plExample; }));
    box.querySelector('#pl-go').addEventListener('click', () => {
      const v = box.querySelector('#pl-what').value.trim();
      if (!v) { box.querySelector('#pl-what').focus(); return; }
      if (P.step === 'error' && P.messages.length > 1 && v === P.messages[0].text) planAsk(); else planStart(v);
    });
    return;
  }
  if (P.step === 'busy') {
    box.innerHTML = `<div class="pl-busy" role="status"><span class="status-dot"></span> ${P.messages.length > 1 ? 'Making your plan and budget…' : 'Working out what to ask you…'}</div>`;
    return;
  }
  if (P.step === 'ask') {
    box.innerHTML = `
      <h3 class="pl-title">${esc(P.title)}</h3>
      ${P.reply ? `<p class="muted">${esc(P.reply)}</p>` : ''}
      <p class="small muted">Answer what you can. Leave anything blank and I’ll pick something sensible.</p>
      <ol class="pl-questions">${P.questions.map(q => {
        const name = 'pq-' + q.id, prev = P.answers[q.id] || '';
        let input;
        if (q.type === 'choice' && q.options.length) {
          input = `<div class="pl-choices">${q.options.map((o, k) => `<label class="pl-choice"><input type="radio" name="${name}" value="${esc(o)}" ${prev === o ? 'checked' : ''}><span>${esc(o)}</span></label>`).join('')}</div>
            <input class="input input-sm pl-other" name="${name}-other" placeholder="Or type your own" value="${q.options.includes(prev) ? '' : esc(prev)}">`;
        } else {
          const type = q.type === 'number' ? 'text" inputmode="decimal' : q.type === 'date' ? 'date' : 'text';
          input = `<input class="input" type="${type}" name="${name}" placeholder="${esc(q.placeholder)}" value="${esc(prev)}">`;
        }
        return `<li class="pl-q"><label class="pl-q-label">${esc(q.q)}</label>${input}</li>`;
      }).join('')}</ol>
      <div class="pl-actions"><button type="button" class="btn" id="pl-restart">Start over</button><button type="button" class="btn btn-primary" id="pl-make">Make my plan</button></div>`;
    box.querySelector('#pl-make').addEventListener('click', () => planSendAnswers(box));
    box.querySelector('#pl-restart').addEventListener('click', () => { planner.step = 'start'; planner.messages = []; renderPlanner(); });
    return;
  }
  // the plan
  const p = P.plan, t = F.planTotals(p.items, p.bufferPct);
  const groups = [];
  p.items.forEach(x => { let g = groups.find(k => k.name === x.group); if (!g) groups.push(g = { name: x.group, items: [] }); g.items.push(x); });
  box.innerHTML = `
    <div class="pl-hero card featured">
      <p class="stat-label">${esc(P.title)}</p>
      <p class="pl-total">${fmtExact(t.total)}</p>
      <p class="small muted">is what you need, including a ${p.bufferPct}% buffer. Prices are estimates.</p>
    </div>
    ${p.reply ? `<p>${esc(p.reply)}</p>` : ''}
    <div class="table-wrap"><table class="pl-table"><thead><tr><th scope="col">Item</th><th class="num" scope="col">Qty</th><th class="num" scope="col">Each</th><th class="num" scope="col">Cost</th></tr></thead>
      <tbody>${groups.map(g => `<tr class="pl-group"><th scope="rowgroup" colspan="3">${esc(g.name)}</th><td class="num">${fmtExact(F.planTotals(g.items, 0).subtotal)}</td></tr>` +
        g.items.map(x => `<tr><td>${esc(x.name)}${x.note ? `<span class="small muted pl-note">${esc(x.note)}</span>` : ''}</td><td class="num">${x.qty}</td><td class="num">${fmtExact(x.unit)}</td><td class="num">${fmtExact(x.qty * x.unit)}</td></tr>`).join('')).join('')}
        <tr><td colspan="3">Buffer (${p.bufferPct}%)</td><td class="num">${fmtExact(t.buffer)}</td></tr>
        <tr class="pl-sum"><td colspan="3"><strong>Total you need</strong></td><td class="num"><strong>${fmtExact(t.total)}</strong></td></tr></tbody></table></div>
    ${p.assumptions.length ? `<h4 class="pl-h">What I assumed</h4><ul class="pl-list">${p.assumptions.map(a => `<li>${esc(a)}</li>`).join('')}</ul>` : ''}
    ${p.tips.length ? `<h4 class="pl-h">Ways to spend less</h4><ul class="pl-list">${p.tips.map(a => `<li>${esc(a)}</li>`).join('')}</ul>` : ''}
    <div class="pl-actions">
      <button type="button" class="btn" id="pl-edit">Change answers</button>
      <button type="button" class="btn" id="pl-copy">Copy plan</button>
      <button type="button" class="btn" id="pl-goal">Save as a goal</button>
      <button type="button" class="btn btn-primary" id="pl-heist">Make it a crew heist</button>
    </div>`;
  box.querySelector('#pl-copy').addEventListener('click', () => copyText(planText(), 'Plan copied'));
  box.querySelector('#pl-edit').addEventListener('click', () => {
    // go back to the last questions; drop the answers and the plan from the conversation
    while (planner.messages.length && planner.messages[planner.messages.length - 1].role === 'user' && planner.messages.length > 1) planner.messages.pop();
    planner.step = planner.questions.length ? 'ask' : 'start'; renderPlanner();
  });
  box.querySelector('#pl-heist').addEventListener('click', () => { closeModal(true); heistForm({ name: P.title, target: Math.round(t.total) }); });
  box.querySelector('#pl-goal').addEventListener('click', () => {
    state.goals.push({ id: uid(), name: P.title.slice(0, 60), target: Math.round(t.total), saved: 0, deadline: '', planMonthly: null, contributions: [] });
    closeModal(); commit(); toast(`Goal added: ${P.title} · ${fmt(t.total)}`); location.hash = '#goals/goals';
  });
}
