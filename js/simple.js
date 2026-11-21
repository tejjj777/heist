/* HEIST · Simple view: three calm screens for parents and grandparents.
   Classic script: shares one global scope with the other js/ files (see README-AGENTS.md).
   When state.settings.simple is on, render() uses these instead of the full pages, and only
   Home, Spending and Savings show. Everything else stays one tap away by turning Simple view off. */
'use strict';
const SIMPLE_ROUTES = ['dashboard', 'spend', 'goals'];
const SIMPLE_VIEWS = { dashboard: simpleHome, spend: simpleSpend, goals: simpleSavings };
const SIMPLE_LABELS = { dashboard: 'Home', spend: 'Spending', goals: 'Savings' };

function svCatName(id) { const c = state.budget.categories.find(k => k.id === id); return c ? c.name : 'Other'; }
function svDay(iso) {
  const t = todayISO();
  if (iso === t) return 'Today';
  if (iso === F.toISO(F.addDays(todayDate(), -1))) return 'Yesterday';
  const d = F.parseDate(iso);
  return d ? `${d.getDate()} ${FULL_MONTHS[d.getMonth()]}` : iso;
}
function svRow(x) {
  const name = (x.note || '').replace(/^🔁\s*/, '').trim() || svCatName(x.categoryId);
  return `<li class="sv-row"><button type="button" class="sv-row-btn" data-action="edit-expense" data-id="${x.id}" aria-label="Change ${esc(name)}, ${esc(fmt(x.amount))}">
      <span class="sv-row-main"><span class="sv-row-name">${esc(name)}</span><span class="sv-row-sub">${esc(svDay(x.date))}</span></span>
      <span class="sv-row-amt">${esc(fmt(x.amount))}</span></button></li>`;
}
const svHead = (title, sub) => `<header class="sv-head"><h1 id="h-${currentRoute()}" tabindex="-1">${esc(title)}</h1>${sub ? `<p class="sv-sub">${esc(sub)}</p>` : ''}</header>`;

function simpleHome() {
  const t = todayDate();
  let hero;
  if (!(monthlyIncome() > 0)) {
    hero = `<section class="sv-hero"><p class="sv-k">Let’s start</p>
      <p class="sv-text">Tell HEIST how much money you get each month. It then shows how much you can spend each day.</p>
      <button type="button" class="btn btn-primary sv-big-btn" data-action="open-paycheck">Add monthly money</button></section>`;
  } else {
    const s = studentSafeToSpend(), al = allowanceLeft(), end = F.parseDate(al.end);
    const over = s.overToday > 0;
    hero = `<section class="sv-hero${over ? ' is-over' : ''}">
      <p class="sv-k">${over ? 'Over today’s limit by' : 'You can spend today'}</p>
      <p class="sv-amount">${esc(fmt(over ? s.overToday : s.leftToday))}</p>
      <p class="sv-text">${esc(fmt(Math.max(0, s.balanceNow)))} left${end ? ` until ${end.getDate()} ${FULL_MONTHS[end.getMonth()]}` : ''}</p>
    </section>`;
  }
  const recent = state.budget.expenses.slice().sort((a, b) => (b.date + (b.id || '')).localeCompare(a.date + (a.id || ''))).slice(0, 5);
  const soon = (state.recurring || []).filter(r => r.active).map(r => ({ r, d: recurringNext(r) }))
    .filter(x => x.d && (x.d - t) / 864e5 <= 14).sort((a, b) => a.d - b.d).slice(0, 3);
  return { html: `<div class="sv">
    ${svHead(hxGreeting())}
    ${hero}
    <button type="button" class="btn btn-primary sv-big-btn" data-action="add-expense">${ICON.plus} Add a spend</button>
    ${soon.length ? `<section class="sv-card"><h2>Bills coming up</h2><ul class="sv-list">${soon.map(x => `<li class="sv-row"><span class="sv-row-main"><span class="sv-row-name">${esc(x.r.name)}</span><span class="sv-row-sub">${esc(dayLabelFuture(x.d, t))}</span></span><span class="sv-row-amt">${esc(fmt(x.r.amount))}</span></li>`).join('')}</ul></section>` : ''}
    <section class="sv-card"><h2>Recent spends</h2>
      ${recent.length ? `<ul class="sv-list">${recent.map(svRow).join('')}</ul><a class="sv-more" href="#spend">See all spends</a>` : '<p class="sv-text">Nothing yet. Tap “Add a spend” when you buy something.</p>'}
    </section>
  </div>` };
}

function simpleSpend() {
  const t = todayDate(), monthStart = F.toISO(new Date(t.getFullYear(), t.getMonth(), 1));
  const all = state.budget.expenses.slice().sort((a, b) => (b.date + (b.id || '')).localeCompare(a.date + (a.id || '')));
  const month = all.filter(x => x.date >= monthStart);
  const shown = (ui.svMore ? all : month.length ? month : all.slice(0, 20)).slice(0, ui.svMore ? 300 : 100);
  return { html: `<div class="sv">
    ${svHead('Spending', `${FULL_MONTHS[t.getMonth()]}: ${fmt(sum(month, x => x.amount))} spent`)}
    <button type="button" class="btn btn-primary sv-big-btn" data-action="add-expense">${ICON.plus} Add a spend</button>
    <section class="sv-card">
      ${shown.length ? `<ul class="sv-list">${shown.map(svRow).join('')}</ul><p class="sv-hint">Tap a spend to change or delete it.</p>` : '<p class="sv-text">No spends yet.</p>'}
      ${!ui.svMore && all.length > shown.length ? '<button type="button" class="btn sv-wide" data-action="sv-show-older">Show older spends</button>' : ''}
    </section>
  </div>` };
}

function simpleSavings() {
  const goals = state.goals || [];
  return { html: `<div class="sv">
    ${svHead('Savings', goals.length ? `${fmt(sum(goals, g => g.saved))} saved` : '')}
    ${goals.length ? goals.map(g => {
      const pct = g.target > 0 ? Math.min(100, Math.round(g.saved / g.target * 100)) : 0;
      return `<section class="sv-card sv-goal">
        <div class="sv-goal-top"><h2>${esc(g.name)}</h2><span class="sv-row-amt">${pct}%</span></div>
        <div class="sv-bar" role="img" aria-label="${pct}% saved"><i style="width:${pct}%"></i></div>
        <p class="sv-text">${esc(fmt(g.saved))} of ${esc(fmt(g.target))}</p>
        <button type="button" class="btn sv-wide" data-action="add-money" data-id="${g.id}">Add money</button>
      </section>`;
    }).join('') : '<section class="sv-card"><p class="sv-text">Saving for something? Add it here and watch it grow.</p></section>'}
    <button type="button" class="btn btn-primary sv-big-btn" data-action="add-goal">${ICON.plus} New saving goal</button>
  </div>` };
}
