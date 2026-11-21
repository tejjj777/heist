/* HEIST · Dashboard page (Home).
   Classic script: shares one global scope with the other js/ files (see README-AGENTS.md). */
'use strict';
/* =========================================================
   VIEW: DASHBOARD (HOME)
   ========================================================= */

/** Safe-to-spend hero: the biggest element on Home. */
function safeToSpendHero(week, maxDay) {
  const inc = monthlyIncome();
  if (!(inc > 0)) {   // no allowance yet: nothing is "overspent", there's just nothing to divide
    return `<div class="card safe-hero" id="safe-hero">
      <p class="stat-label">Safe to spend today</p>
      <p class="safe-hero-reason">Add your allowance and HEIST works out how much you can spend each day.</p>
      <div class="safe-hero-actions no-print"><button type="button" class="btn btn-primary btn-sm" data-action="open-paycheck"><span>Set allowance</span></button></div>
    </div>`;
  }
  const sts = studentSafeToSpend();
  const al = allowanceLeft();
  const next = nextPayInfo() ? { days: al.daysLeft } : null;
  const t = todayDate();
  const statusLabel = sts.status === 'green' ? 'On track' : sts.status === 'amber' ? 'Tight pace' : 'Overspent';

  return `<div class="card safe-hero safe-${sts.status}${week ? ' in-bento' : ''}" id="safe-hero">
    <svg class="hero-beam no-print" aria-hidden="true" focusable="false"><rect pathLength="100"></rect></svg>
    <div class="safe-hero-header">
      <p class="safe-hero-label">Safe to spend today</p>
      <span class="small muted">${next ? `Next allowance ${daysLabel(next.days).toLowerCase()}` : (state.income.irregular ? 'Irregular allowance' : `${F.daysLeftInMonth(t)} days left this month`)}</span>
    </div>
    <div class="safe-hero-body">
      <h1 class="safe-hero-amount">${fmtExact(sts.leftToday)}</h1>
      <p class="safe-hero-reason"><span class="safe-status is-${sts.status}">${sts.status === 'green' && sts.overToday <= 0 && sts.available > 0 ? statusLabel : statusLabel + '.'}</span> ${sts.overToday > 0 ? `You went ${fmtExact(sts.overToday)} over today’s limit. Tomorrow’s limit adjusts.` : sts.available <= 0 ? 'Nothing left after bills. Showing 0.' : esc(sts.reason.replace(/^On track /, ''))}</p>
      <div class="safe-hero-formula small muted">
        <span>Daily limit: <strong>${fmtExact(sts.dailyLimit)}</strong></span>
        <span>·</span>
        <span>Spent today: ${fmtExact(sts.spentToday)}</span>
      </div>
      <div class="safe-hero-formula small muted">
        <span>This week: <strong>${fmtExact(sts.weekLeft)}</strong> left · spent ${fmtExact(sts.spentWeek)}</span>
      </div>
      <div class="safe-hero-formula small muted">
        <span>${sts.fromBank ? 'In your bank / UPI' : 'Left this period'}: ${fmtExact(sts.balanceNow)}</span>
        ${sts.upcomingBills > 0 ? `<span>− Bills ${fmtExact(sts.upcomingBills)}</span>` : ''}
        ${sts.debtDue > 0 ? `<span>− Debt ${fmtExact(sts.debtDue)}</span>` : ''}
        <span>· ${plural(sts.daysLeft, 'day')} left</span>
      </div>
    </div>
    ${week ? `<div class="hero-week" aria-label="Spending each day this week">${week.map(d => `<span class="hw-col"><i class="${d.today ? 'today' : ''}" style="height:${Math.max(4, Math.round(d.amt / maxDay * 100))}%"></i><b>${d.label}</b></span>`).join('')}</div>` : ''}
    ${(() => { const due = billsDueSoon(); return due.length ? `<div class="safe-due">${due.slice(0, 3).map(b => `<span>${b.date === todayISO() ? 'Due today' : 'Due tomorrow'}: <strong>${esc(b.name)}</strong> ${fmtExact(b.amount)}</span>`).join('')}</div>` : ''; })()}
    <div class="safe-hero-actions no-print">
      <button type="button" class="btn btn-primary btn-sm" data-action="add-expense">${ICON.plus}<span>Log expense</span></button>
      <button type="button" class="btn btn-sm" data-action="set-bank">${state.settings.bank ? `Bank: ${fmtExact(bankBalanceNow())}` : 'Add bank balance'}</button>
      <button type="button" class="btn btn-sm" data-action="open-paycheck"><span>Edit allowance</span></button>
      ${sts.status === 'red' ? `<button type="button" class="btn btn-sm btn-warn" data-action="ask-topup"><span>Ask for a top-up</span></button>` : ''}
    </div>
  </div>`;
}

/** Home bento: the money tiles from the Bento × Zine design, built from real data. */
function homeBento() {
  if (!(monthlyIncome() > 0)) return safeToSpendHero();
  const t = todayDate();
  const al = allowanceLeft(), b = budgetTotals(), sk = streakInfo();
  const daysPay = nextPayInfo() ? al.daysLeft : F.daysLeftInMonth(t);
  const week = [];
  for (let i = 6; i >= 0; i--) {
    const d = F.addDays(t, -i), iso = F.toISO(d);
    week.push({ label: i === 0 ? 'Today' : DOW_SHORT[d.getDay()], amt: sum(state.budget.expenses.filter(x => x.date === iso), x => x.amount), today: i === 0, noWants: !sk.spend.has(iso) });
  }
  const maxDay = Math.max(1, ...week.map(d => d.amt));
  const cats = state.budget.categories.filter(c => c.planned > 0 && c.type !== 'savings');
  const hot = cats.map(c => ({ c, r: c.actual / c.planned })).sort((x, y) => y.r - x.r)[0];
  const usedPct = b.planned > 0 ? Math.round(b.actual / b.planned * 100) : 0;
  const ringLen = 2 * Math.PI * 48, ringOn = Math.min(1, usedPct / 100) * ringLen;
  const where = state.budget.categories.filter(c => c.actual > 0).sort((x, y) => y.actual - x.actual).slice(0, 5);
  const goals = state.goals.slice().sort((x, y) => goalInfo(y).pct - goalInfo(x).pct).slice(0, 3);
  const dayLeft = hot ? Math.max(0, hot.c.planned - hot.c.actual) / Math.max(1, daysPay) : 0;
  const month = FULL_MONTHS[t.getMonth()];
  return `<div class="bento">
    ${safeToSpendHero(week, maxDay)}
    <button type="button" class="card bento-tile tile-green" data-action="open-paycheck" aria-label="${daysPay} days to your next allowance. Edit allowance">
      <span class="tile-label">${nextPayInfo() ? 'Next allowance in' : 'Days left this month'}</span>
      <span class="tile-big"><span class="big-num">${daysPay}</span> <span class="tile-unit">${daysPay === 1 ? 'day' : 'days'}</span></span>
    </button>
    ${hot ? `<a class="card bento-tile" href="#budget/plan" data-vt="cat-${hot.c.id}" data-cat-id="${hot.c.id}">
      <span class="tile-row"><span class="muted">${esc(hot.c.name)}</span><span class="tile-flag">${hot.r >= 1 ? 'Over limit' : hot.r >= 0.75 ? 'Close to limit' : 'On track'}</span></span>
      <span class="big-num tile-accent">${Math.round(hot.r * 100)}%</span>
      <span class="muted small">${hot.r >= 1 ? `${fmt(hot.c.actual - hot.c.planned)} over its limit` : `${fmt(dayLeft)} a day keeps you on track`}</span>
    </a>` : ''}
    <div class="card bento-tile tile-ring">
      <svg width="104" height="104" viewBox="0 0 120 120" role="img" aria-label="${usedPct}% of the ${month} budget used"><circle cx="60" cy="60" r="48" class="ring-bg"></circle><circle cx="60" cy="60" r="48" class="ring-on" style="stroke-dasharray:${ringOn.toFixed(1)} 999"></circle></svg>
      <span><span class="big-num">${usedPct}%</span><span class="muted small">of ${month} used<br>${fmt(b.actual)} of ${fmt(b.planned)}</span></span>
    </div>
    <div class="card bento-tile tile-streak">
      <span class="muted">No-spend streak</span>
      <span class="tile-big"><span class="big-num">${sk.current}</span> <span class="tile-unit muted">${sk.current === 1 ? 'day' : 'days'}</span></span>
      <span class="streak-dots" aria-label="Last 7 days, filled means no spending on wants">${week.map(d => `<i class="${d.noWants ? 'on' : ''}"></i>`).join('')}</span>
    </div>
    ${where.length ? `<div class="card bento-wide">
      <div class="tile-head"><h2>Where it went</h2><a href="#spend/categories">All categories</a></div>
      ${where.map(c => { const pct = c.planned > 0 ? Math.min(100, c.actual / c.planned * 100) : 100; return `<a class="bw-row" href="#budget/plan" data-vt="cat-${c.id}" data-cat-id="${c.id}"><span>${esc(c.name)}</span><span class="bw-bar"><i class="${c.planned > 0 && c.actual / c.planned >= 0.75 ? 'warn' : ''}" style="width:${pct}%"></i></span><span class="bw-amt">${fmt(c.actual)}</span></a>`; }).join('')}
    </div>` : ''}
    ${goals.length ? `<div class="card bento-wide">
      <div class="tile-head"><h2>Saving for</h2><a href="#goals/goals">All goals</a></div>
      ${goals.map((g, i) => { const gi = goalInfo(g), pct = Math.min(100, Math.round(gi.pct)); return `<a class="hang-tag${i === 0 ? ' is-lead' : ''}" href="#goals/goals" data-vt="goal-${g.id}"><span class="hang-hole" aria-hidden="true"></span><span class="hang-body"><span class="hang-top"><strong>${esc(g.name)}</strong><span class="hang-pct">${pct}%</span></span><span class="hang-bar"><i style="width:${pct}%"></i></span><span class="small">${fmt(g.saved)} of ${fmt(g.target)}</span></span></a>`; }).join('')}
    </div>` : ''}
  </div>`;
}

/* =========================================================
   HEIST TODAY: clean take, getaway clock, suspects, targets
   ========================================================= */
function hxGreeting() {
  const h = new Date().getHours();
  return h < 5 ? 'Late night' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
}
/** Money split into whole part and cents, so the cents can sit small. */
function hxMoney(v) {
  const s = fmtExact(v), m = s.match(/^(.*?)([.,]\d{2})(\D*)$/);
  return m && !NO_DECIMALS.has(state.currency) ? `${esc(m[1])}<span class="hx-cents">${esc(m[2])}</span>${esc(m[3])}` : esc(s);
}
function hxMonthlySub(s) { const a = +s.amount || 0; return s.cycle === 'yearly' ? a / 12 : s.cycle === 'weekly' ? a * 52 / 12 : a; }

/** Hero: what you can safely spend today, and how far the money has to stretch. */
function hxHero() {
  const inc = monthlyIncome();
  if (!(inc > 0)) {
    return `<article class="hx-hero hx-rise" style="--i:0" id="safe-hero">
      <div class="hx-aura" aria-hidden="true"><i></i><i></i><i></i></div>
      <div class="hx-eyebrow"><span class="hx-chip">Clean take</span></div>
      <div class="hx-amount-wrap"><p class="hx-label">Let’s set you up</p>
      <p class="hx-reason">Add your allowance and HEIST works out how much you can safely spend each day, after bills.</p></div>
      <div class="hx-actions"><button type="button" class="btn btn-primary" data-action="open-paycheck"><span>Set allowance</span></button>${hasAnyData() ? '' : '<button type="button" class="btn" data-action="load-sample"><span>Try sample data</span></button>'}</div>
    </article>`;
  }
  const sts = studentSafeToSpend(), al = allowanceLeft(), t = todayDate(), today = F.toISO(t);
  const tone = sts.status === 'red' ? 'is-red' : sts.status === 'amber' ? 'is-amber' : 'is-green';
  const statusLabel = sts.status === 'green' ? 'On track' : sts.status === 'amber' ? 'Tight pace' : 'Overspent';
  const next = nextPayInfo();
  const reason = sts.overToday > 0 ? `You went ${fmtExact(sts.overToday)} over today’s limit. Tomorrow’s limit adjusts.`
    : sts.available <= 0 ? 'Nothing left after bills, so this shows 0.'
    : (sts.reason || '').replace(/^On track /, 'You’re on track ');
  // getaway clock: how far through this money period we are, with upcoming bills as ticks
  const start = F.parseDate(al.start) || t, end = F.parseDate(al.end) || F.addDays(t, al.daysLeft);
  const total = Math.max(1, F.daysBetween(start, end)), gone = Math.min(total, Math.max(0, F.daysBetween(start, t)));
  const pct = Math.round(gone / total * 100);
  const ticks = [];
  (state.recurring || []).filter(r => r.active).forEach(r => {
    F.recurringDue(r, today, F.toISO(end)).forEach(d => {
      const dd = typeof d === 'string' ? F.parseDate(d) : d;
      const at = Math.min(100, Math.max(0, F.daysBetween(start, dd) / total * 100));
      ticks.push(`<i class="hx-tick" style="left:${at.toFixed(1)}%" data-tip="${esc(r.name)} ${esc(fmt(r.amount))}"></i>`);
    });
  });
  const days = al.daysLeft;
  return `<article class="hx-hero ${tone} hx-rise" style="--i:0" id="safe-hero">
    <div class="hx-aura" aria-hidden="true"><i></i><i></i><i></i></div>
    <div class="hx-eyebrow">
      <span class="hx-chip"><i class="hx-dot" aria-hidden="true"></i>${statusLabel}</span>
      <span class="hx-quiet">${next ? `Allowance ${daysLabel(next.days).toLowerCase()}` : `${plural(days, 'day')} left`}</span>
    </div>
    <div class="hx-amount-wrap">
      <p class="hx-label">Clean take today</p>
      <h2 class="hx-amount" data-hx-count="${Math.max(0, sts.leftToday)}">${hxMoney(sts.leftToday)}</h2>
      <p class="hx-reason">${esc(reason)}</p>
    </div>
    <div class="hx-clock" aria-label="Getaway clock: ${plural(days, 'day')} until your money resets">
      <div class="hx-clock-top"><span>Getaway clock</span><strong>${plural(days, 'day')} to go</strong></div>
      <div class="hx-track"><b style="--w:${pct}%"></b>${ticks.slice(0, 12).join('')}</div>
      <div class="hx-clock-legend"><span>${esc(fmtDate(start).replace(/ \d{4}$/, ''))}</span><span>${esc(fmtDate(end).replace(/ \d{4}$/, ''))}</span></div>
    </div>
    <div class="hx-facts">
      <div class="hx-fact"><span>Daily limit</span><strong>${esc(fmt(sts.dailyLimit))}</strong></div>
      <div class="hx-fact"><span>Spent today</span><strong>${esc(fmt(sts.spentToday))}</strong></div>
      <div class="hx-fact"><span>${sts.fromBank ? 'In your bank' : 'Left this period'}</span><strong>${esc(fmt(sts.balanceNow))}</strong></div>
    </div>
    <div class="hx-actions no-print">
      <button type="button" class="btn btn-primary" data-action="add-expense">${ICON.plus}<span>Log a spend</span></button>
      <button type="button" class="btn" data-action="scan-receipt">${ICON.camera}<span>Scan receipt</span></button>
      ${sts.status === 'red' ? `<button type="button" class="btn" data-action="ask-topup"><span>Ask for a top-up</span></button>` : `<button type="button" class="btn" data-action="set-bank"><span>${state.settings.bank ? 'Update bank' : 'Add bank balance'}</span></button>`}
    </div>
  </article>`;
}

function heistToday() {
  const t = todayDate(), b = budgetTotals(), sk = streakInfo();
  const week = [];
  for (let i = 6; i >= 0; i--) {
    const d = F.addDays(t, -i), iso = F.toISO(d);
    week.push({ amt: sum(state.budget.expenses.filter(x => x.date === iso), x => x.amount), today: i === 0, noWants: !sk.spend.has(iso), label: i === 0 ? 'Today' : DOW_SHORT[d.getDay()] });
  }
  const weekSum = sum(week, d => d.amt), maxDay = Math.max(1, ...week.map(d => d.amt));
  const usedPct = b.planned > 0 ? Math.round(b.actual / b.planned * 100) : 0;
  const ringLen = 2 * Math.PI * 26;
  const month = FULL_MONTHS[t.getMonth()];
  const inc = monthlyIncome();

  // Suspects: categories close to or past their limit, then the priciest subscriptions
  const cats = state.budget.categories.filter(c => c.planned > 0 && c.type !== 'savings')
    .map(c => ({ c, r: c.actual / c.planned })).filter(x => x.r >= 0.6).sort((x, y) => y.r - x.r).slice(0, 3);
  const subs = (state.subscriptions || []).slice().sort((x, y) => hxMonthlySub(y) - hxMonthlySub(x)).slice(0, Math.max(0, 4 - cats.length));
  const suspects = cats.map(({ c, r }) => {
    const cls = r > 1 ? 'bad' : r >= 0.85 ? 'warn' : '';
    const flag = r > 1 ? 'Over' : r >= 1 ? 'At limit' : r >= 0.85 ? 'Close' : 'Watch';
    return `<a class="hx-row" href="#budget/plan" data-cat-id="${c.id}">
      <span class="hx-av ${cls}" aria-hidden="true">${esc((c.name || '?').trim().charAt(0).toUpperCase())}</span>
      <span class="hx-row-main"><strong>${esc(c.name)}</strong><span>${esc(fmt(c.actual))} of ${esc(fmt(c.planned))}</span><span class="hx-bar"><i class="${cls}" style="--w:${Math.min(100, Math.round(r * 100))}%"></i></span></span>
      <span class="hx-row-end"><span class="hx-flag ${cls}">${flag}</span><span>${Math.round(r * 100)}%</span></span>
    </a>`;
  }).concat(subs.map(s => `<a class="hx-row" href="#spend/recurring">
      <span class="hx-av" aria-hidden="true">${esc((s.name || '?').trim().charAt(0).toUpperCase())}</span>
      <span class="hx-row-main"><strong>${esc(s.name)}</strong><span>Subscription${s.cycle && s.cycle !== 'monthly' ? `, ${esc(s.cycle)}` : ''}</span></span>
      <span class="hx-row-end"><strong>${esc(fmt(hxMonthlySub(s)))}</strong><span>a month</span></span>
    </a>`));

  const goals = state.goals.slice().sort((x, y) => goalInfo(y).pct - goalInfo(x).pct).slice(0, 4);
  const targets = goals.map(g => {
    const gi = goalInfo(g), pct = Math.min(100, Math.round(gi.pct));
    return `<a class="hx-row" href="#goals/goals" data-vt="goal-${g.id}">
      <span class="hx-av" aria-hidden="true">${pct >= 100 ? '✓' : esc((g.name || '?').trim().charAt(0).toUpperCase())}</span>
      <span class="hx-row-main"><strong>${esc(g.name)}</strong><span>${esc(fmt(g.saved))} of ${esc(fmt(g.target))}</span><span class="hx-bar"><i style="--w:${pct}%"></i></span></span>
      <span class="hx-row-end"><strong>${pct}%</strong></span>
    </a>`;
  });

  return `<div class="hx-today">
    ${hxHero()}
    <div class="hx-tiles">
      <a class="hx-tile is-ink hx-rise" style="--i:1" href="#spend/log">
        <span class="hx-tile-k">Spent this week</span>
        <span class="hx-tile-v">${esc(fmt(weekSum))}</span>
        <span class="hx-week" aria-label="Spending on each of the last 7 days">${week.map((d, i) => `<i class="${d.today ? 'on' : ''}" style="--h:${Math.max(6, Math.round(d.amt / maxDay * 100))}%;--d:${i}" title="${esc(d.label)}: ${esc(fmt(d.amt))}"></i>`).join('')}</span>
      </a>
      <a class="hx-tile hx-rise" style="--i:2" href="#budget/plan">
        <span class="hx-tile-k">${esc(month)} budget</span>
        <span class="hx-tile-row"><span class="hx-tile-v">${usedPct}%</span>
        <svg class="hx-ring" viewBox="0 0 64 64" aria-hidden="true"><circle class="bg" cx="32" cy="32" r="26"></circle><circle class="on" cx="32" cy="32" r="26" style="--len:${(Math.min(1, usedPct / 100) * ringLen).toFixed(1)}"></circle></svg></span>
        <span class="hx-tile-s">Used: ${esc(fmt(b.actual))} of ${esc(fmt(b.planned))}</span>
      </a>
      <div class="hx-tile is-lav hx-rise" style="--i:3">
        <span class="hx-tile-k">No-spend streak</span>
        <span class="hx-tile-v">${sk.current}<small>${sk.current === 1 ? 'day' : 'days'}</small></span>
        <span class="hx-streak" aria-label="Last 7 days, filled means no spending on wants">${week.map(d => `<i class="${d.noWants ? 'on' : ''}"></i>`).join('')}</span>
      </div>
      <button type="button" class="hx-tile hx-rise" style="--i:4" data-action="open-paycheck">
        <span class="hx-tile-k">Monthly allowance</span>
        <span class="hx-tile-v">${esc(fmt(inc))}</span>
        <span class="hx-tile-s">${state.income.irregular ? 'Irregular' : 'Tap to edit'}</span>
      </button>
    </div>
  </div>
  <div class="hx-pair">
    <section class="hx-panel hx-rise" style="--i:5" aria-labelledby="hx-suspects">
      <div class="hx-panel-head"><h2 id="hx-suspects">The <em>suspects</em></h2><a href="#spend/categories">See all</a></div>
      ${suspects.length ? `<div class="hx-rows">${suspects.join('')}</div>` : `<p class="hx-empty">No leaks right now. Every category is under 60% of its limit.</p>`}
    </section>
    <section class="hx-panel hx-rise" style="--i:6" aria-labelledby="hx-targets">
      <div class="hx-panel-head"><h2 id="hx-targets">Your <em>targets</em></h2><a href="#goals/goals">See all</a></div>
      ${targets.length ? `<div class="hx-rows">${targets.join('')}</div>` : `<p class="hx-empty">No targets yet. <button type="button" class="linklike" data-action="add-goal">Add one</button></p>`}
    </section>
  </div>`;
}

/** Count the hero amount up from zero (cents stay put until it lands). */
function hxCountUp() {
  const el = document.querySelector('.hx-amount[data-hx-count]');
  if (!el || !motionOK() || el.dataset.hxDone) return;
  el.dataset.hxDone = '1';
  const target = parseFloat(el.dataset.hxCount), html = el.innerHTML;
  if (!(target >= 10)) return;
  const cents = el.querySelector('.hx-cents'), centsHTML = cents ? cents.outerHTML : '';
  const sym = fmt(0).replace(/[\d.,\s]/g, '');
  const locale = (CURRENCIES[state.currency] || {}).locale || 'en-IN';
  const nf = new Intl.NumberFormat(locale, { maximumFractionDigits: 0 });
  const pre = fmt(0).trim().startsWith(sym);
  const dur = 1100, t0 = performance.now() + 150;
  const step = now => {
    if (!el.isConnected) return;
    const k = Math.max(0, Math.min(1, (now - t0) / dur)), e = 1 - Math.pow(1 - k, 4);
    if (k >= 1) { el.innerHTML = html; return; }
    const n = nf.format(Math.floor(target * e));
    el.innerHTML = (pre ? esc(sym) + n : n + ' ' + esc(sym)) + centsHTML;
    requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

/** Forecast card with interactive sliders for flexible spending. */
function runOutForecastCard(chartId = 'dash-forecast-chart') {
  const fc = studentRunOutForecast();
  const days = allowanceLeft().daysLeft;

  return `<div class="card mb" id="forecast-card">
    <div class="card-head">
      <div>
        <h2>Run-out forecast</h2>
        <p class="muted small">Your money until the next allowance: wants at your current pace, plus bills not paid yet.</p>
      </div>
      <div id="forecast-status-badge" class="badge ${fc.willMakeIt ? 'badge-success' : 'badge-danger'}">
        ${fc.willMakeIt ? `You’ll make it with ${fmt(fc.endBalance)} left` : `Runs out ${fc.runOutDay ? fmtDate(F.parseDate(fc.runOutDay)) : 'soon'} (${Math.max(1, days - (fc.runOutDayIndex || 0))} days before allowance)`}
      </div>
    </div>
    <div class="chart-box" style="height:210px;position:relative"><canvas id="${chartId}"></canvas></div>
    <div class="slider-panel no-print">
      <div class="slider-panel-head"><p class="slider-panel-title"><strong>Your spending habits</strong> <span class="small muted">(drag to see what changes)</span></p>
        <button type="button" class="btn btn-sm" data-action="edit-habits">${ICON.edit}<span>Edit habits</span></button></div>
      ${habitsList().length ? `<div class="slider-grid">${habitsList().map(h => {
        const max = Math.max(5, Math.ceil(h.now * 3), h.now + 3);
        return `<div class="slider-item">
          <div class="slider-header"><label for="slider-${h.id}">${esc(h.name)}</label><span class="slider-val" id="val-slider-${h.id}">${h.now} ${h.per === 'day' ? 'a day' : 'a week'}</span></div>
          <input type="range" class="range-slider" id="slider-${h.id}" min="0" max="${max}" step="1" value="${h.now}" data-hid="${h.id}" data-base="${h.now}" data-cost="${h.cost}" data-per="${h.per}">
          <p class="small muted slider-cost">${fmt(h.cost)} each</p>
        </div>`;
      }).join('')}</div>` : '<p class="small muted">Add the things you spend on often, like takeout, cafes or cabs, and see how changing them moves your forecast.</p>'}
    </div>
  </div>`;
}

/** Semester overview card with heavy months and progress. */
function semesterCard() {
  const sem = studentSemesterPlan();
  const sData = (state.student && state.student.semester) || {};
  const t = todayDate();
  const startStr = sData.start ? fmtMonthYear(F.parseDate(sData.start)) : fmtMonthYear(t);
  const endStr = sData.end ? fmtMonthYear(F.parseDate(sData.end)) : fmtMonthYear(F.addMonths(t, 4));
  const heavy = sData.heavyMonths || [];

  return `<div class="card mb" id="semester-card">
    <div class="card-head">
      <div>
        <h2>Semester plan</h2>
        <p class="muted small">${startStr} – ${endStr} (${plural(sem.months, 'month')})</p>
      </div>
      <div class="actions no-print">
        <span class="badge ${sem.onTrack ? 'badge-success' : 'badge-warn'}">${sem.onTrack ? 'On track' : `Behind by ${fmt(sem.diff)}`}</span>
        <button type="button" class="btn btn-sm" data-action="open-semester-modal">${ICON.edit}<span>Edit semester</span></button>
      </div>
    </div>
    <div class="stats-grid three" style="margin-bottom:12px">
      ${stat('Semester income', fmt(sem.totalIncome), `${fmt(monthlyIncome())} / month`)}
      ${stat('Base expenses', fmt(sem.baseExpenses), `${fmt(sem.baseExpenses / sem.months)} / month`)}
      ${stat('Heavy month expenses', fmt(sem.heavyTotal), `${heavy.length} planned spikes`, sem.heavyTotal > 0 ? 'tone-warn' : '')}
    </div>
    ${sem.onTrack ? `<div class="alert alert-info" style="margin-bottom:12px">Your expected income and savings comfortably cover your regular expenses and heavy semester months with a <strong>${fmt(sem.surplus)} surplus</strong>.</div>`
      : `<div class="alert alert-warn" style="margin-bottom:12px">You need to set aside approximately <strong>${fmt(sem.monthlyBufferNeeded)} a month</strong> to cover upcoming fees, exams and trips without running dry.</div>`}
    ${heavy.length ? `<div class="table-wrap"><table><thead><tr><th scope="col">Month</th><th scope="col">Event / Fee</th><th class="num" scope="col">Amount</th></tr></thead>
      <tbody>${heavy.map(h => `<tr><td><strong>${monthLabelISO(h.month)}</strong></td><td>${esc(h.name)}</td><td class="num font-bold">${fmt(h.amount)}</td></tr>`).join('')}</tbody></table></div>`
      : '<p class="muted small">No heavy months marked yet. Tap "Edit semester" to plan semester fees, exam costs or trips.</p>'}
  </div>`;
}

function bindForecastSliders(chartId = 'dash-forecast-chart') {
  const container = document.getElementById('forecast-card');
  if (!container) return;
  const sliders = container.querySelectorAll('.range-slider');
  if (!sliders.length) return;

  const onSlide = () => {
    const adj = {};
    sliders.forEach(s => {
      const val = Number(s.value), base = Number(s.dataset.base || 0), cost = Number(s.dataset.cost || 0), daily = s.dataset.per === 'day';
      const label = container.querySelector('#val-' + s.id);
      if (label) label.textContent = `${val} ${daily ? 'a day' : 'a week'}`;
      adj['habit:' + s.dataset.hid] = (val - base) * cost * (daily ? 1 : 1 / 7);
    });
    const newFc = studentRunOutForecast(adj);
    updateRunOutChartLive(chartId, newFc);

    const badge = container.querySelector('#forecast-status-badge');
    if (badge) {
      badge.className = `badge ${newFc.willMakeIt ? 'badge-success' : 'badge-danger'}`;
      badge.textContent = newFc.willMakeIt ? `You’ll make it with ${fmt(newFc.endBalance)} left` : `Runs out ${newFc.runOutDay ? fmtDate(F.parseDate(newFc.runOutDay)) : 'soon'}`;
    }
  };

  sliders.forEach(s => s.addEventListener('input', onSlide));
}

/* ---------- Savings: how much the student is saving ---------- */
function savingsByMonth(ym) {
  const savCats = new Set(state.budget.categories.filter(c => c.type === 'savings').map(c => c.id));
  const goalIn = sum(state.goals.flatMap(g => g.contributions.filter(c => c.date.slice(0, 7) === ym)), c => c.amount);
  const catIn = sum(state.budget.expenses.filter(x => x.date.slice(0, 7) === ym && savCats.has(x.categoryId)), x => x.amount);
  return goalIn + catIn;
}
function savingsInfo() {
  const t = todayDate(), months = [];
  for (let i = 5; i >= 0; i--) { const d = new Date(t.getFullYear(), t.getMonth() - i, 1); months.push({ ym: F.toISO(d).slice(0, 7), label: SHORT_MONTHS_SAFE(d.getMonth()) }); }
  months.forEach(m => { m.amount = savingsByMonth(m.ym); });
  const thisM = months[5].amount, lastM = months[4].amount, inc = monthlyIncome();
  return { months, thisM, lastM, change: thisM - lastM, rate: inc > 0 ? thisM / inc * 100 : null,
    total: sum(state.goals, g => g.saved), goals: state.goals.filter(g => g.target > 0) };
}
function SHORT_MONTHS_SAFE(i) { return ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][i]; }
function savingsCard(chartId = 'dash-savings-chart') {
  const s = savingsInfo();
  const ch = s.change, chTxt = s.lastM === 0 && s.thisM === 0 ? 'Nothing saved yet' : `${ch >= 0 ? '▲' : '▼'} ${fmtExact(Math.abs(ch))} vs last month`;
  const goals = s.goals.slice(0, 4).map(g => { const p = Math.min(100, g.saved / g.target * 100); return `<div class="sv-goal"><div class="sv-goal-top"><span>${esc(g.name)}</span><span class="small muted">${fmtExact(g.saved)} of ${fmtExact(g.target)}</span></div><div class="progress" role="progressbar" aria-valuenow="${Math.round(p)}" aria-valuemin="0" aria-valuemax="100" aria-label="${esc(g.name)}"><span style="width:${p}%"></span></div></div>`; }).join('');
  return `<div class="card mb savings-card" id="savings-card">
    <div class="card-head"><div><h2>Your savings</h2><p class="muted small">Goal deposits plus money put in savings categories.</p></div>
      <div class="actions no-print"><button type="button" class="btn btn-sm" data-action="add-goal">${ICON.plus}<span>Goal</span></button></div></div>
    <div class="exact-grid">
      <div><p class="stat-label">Total saved</p><p class="exact-val">${fmtExact(s.total)}</p></div>
      <div><p class="stat-label">This month</p><p class="exact-val">${fmtExact(s.thisM)}</p><p class="small ${ch >= 0 ? 'sv-up' : 'tone-danger-text'}">${chTxt}</p></div>
      <div><p class="stat-label">Savings rate</p><p class="exact-val">${s.rate === null ? '-' : fmtPct(s.rate)}</p><p class="small muted">of this month’s income</p></div>
    </div>
    <div class="sv-chart"><canvas id="${chartId}" aria-label="Savings in the last 6 months" role="img"></canvas></div>
    ${goals ? `<div class="sv-goals">${goals}</div>` : '<p class="small muted">Add a goal to see your progress here.</p>'}
  </div>`;
}
function drawSavingsChart(id) {
  const el = document.getElementById(id); if (!el) return;
  const s = savingsInfo();
  makeChart(id, { type: 'bar', data: { labels: s.months.map(m => m.label), datasets: [{ label: 'Saved', data: s.months.map(m => Math.round(m.amount * 100) / 100), backgroundColor: getComputedStyle(document.documentElement).getPropertyValue('--primary').trim() || '#7ED957', borderRadius: 6 }] },
    options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false }, tooltip: { callbacks: { label: c => fmtExact(c.parsed.y) } } }, scales: { y: { beginAtZero: true, ticks: { callback: v => fmtCompactSafe(v) } } } } });
}
function fmtCompactSafe(v) { try { return fmt(v); } catch (e) { return String(v); } }

function renderDashboard() {
  const t = todayDate();
  const inc = monthlyIncome();
  const al = allowanceLeft();
  const next = nextPayInfo() ? { days: al.daysLeft } : null;
  const b = budgetTotals(), rw = runwayInfo(), sk = streakInfo();
  const saved = sum(state.goals, g => g.saved), target = sum(state.goals, g => g.target);
  const sp = spendingSource();

  let html = viewHeader('dashboard', `${hxGreeting()}<em>.</em>`, `${['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][t.getDay()]}, ${t.getDate()} ${FULL_MONTHS[t.getMonth()]}`,
    '', [mi('What’s new', 'whats-new'), mi('Full tutorial', 'tour-all'), mi('Money Wrapped', 'open-wrapped')]);

  // a brand-new user is greeted by the hero itself (it has Set allowance and Try sample data)

  const overview = heistToday() + sampleBanner() + backupBanner() + (typeof budgetNudgeBanner === 'function' ? budgetNudgeBanner() : '') + commandBarHTML() + subCheckCard() +
    `<div class="stats-grid home-stats">
      ${stat('Monthly allowance', fmt(inc), `${state.income.irregular ? `${irregularLine()} · <button type="button" class="linklike" data-action="log-income">Log income</button>` : `${next ? `Next allowance ${daysLabel(next.days).toLowerCase()} · ` : ''}<button type="button" class="linklike" data-action="open-paycheck">Edit</button>`}`, 'featured')}
      ${al.byPayday
        ? stat('Left until payday', fmt(al.balance), inc > 0 ? `${fmtPct(al.spent / inc * 100)} of this allowance spent` : 'Track spending', al.balance < 0 ? 'tone-danger' : '')
        : stat('Left this month', fmt(b.remaining), inc > 0 ? `${fmtPct(b.actual / inc * 100)} of allowance spent` : 'Track spending', b.remaining < 0 ? 'tone-danger' : '')}
    </div>` +
    savingsCard('dash-savings-chart') +
    runOutForecastCard('dash-forecast-chart') +
    semesterCard() +
    `<div class="grid-2">${petCard()}${questsCard()}</div>`;

  const forecastTab = runOutForecastCard('tab-forecast-chart') + `<div class="grid-2">${weatherCard()}${questsCard()}</div>`;
  const semesterTab = semesterCard() + `<div class="grid-2">${chartCard('Savings goal progress', '% of each target saved', 'dash-goals-tab', state.goals.length > 0, 'Add a savings goal to track progress.')}</div>`;

  const chartsTab = `<div class="grid-2">
    ${chartCard('Spending by category', sp.useActual ? 'Actual spending this month' : (sp.list.length ? 'Planned' : ''), 'dash-spend', sp.list.length > 0, 'Log expenses to see where your money goes.', '', true)}
    ${chartCard('Savings goal progress', '% of each target saved', 'dash-goals', state.goals.length > 0, 'Add a savings goal to track progress.')}
  </div>`;

  html += tabbed('dashboard', {
    overview,
    forecast: forecastTab,
    semester: semesterTab,
    calendar: calendarCard(),
    charts: chartsTab
  });

  return {
    html,
    charts() {
      const tab = currentTab('dashboard');
      if (tab === 'overview') {
        const fc = studentRunOutForecast();
        runOutLineChart('dash-forecast-chart', fc);
        bindForecastSliders('dash-forecast-chart');
        bindCommandBar();
        drawSavingsChart('dash-savings-chart');
        hxCountUp();
      } else if (tab === 'forecast') {
        const fc = studentRunOutForecast();
        runOutLineChart('tab-forecast-chart', fc);
        bindForecastSliders('tab-forecast-chart');
      } else if (tab === 'semester') {
        if (state.goals.length) goalsBarChart('dash-goals-tab');
      } else if (tab === 'charts') {
        if (sp.list.length) spendChart('dash-spend');
        if (state.goals.length) goalsBarChart('dash-goals');
      }
    }
  };
}

/** Semester edit modal */
function openSemesterModal() {
  const sem = (state.student && state.student.semester) || {};
  const t = todayDate();
  const startVal = sem.start || todayISO().slice(0, 7) + '-01';
  const endVal = sem.end || F.toISO(F.addMonths(t, 4));
  const heavy = sem.heavyMonths || [];

  formModal({
    title: 'Semester plan',
    submitLabel: 'Save semester plan',
    values: {
      start: startVal,
      end: endVal,
      fee1Name: heavy[0] ? heavy[0].name : 'Semester exam & lab fees',
      fee1Month: heavy[0] ? heavy[0].month : F.toISO(F.addMonths(t, 1)).slice(0, 7),
      fee1Amount: heavy[0] ? heavy[0].amount : 0,
      fee2Name: heavy[1] ? heavy[1].name : 'Festivals / College trip',
      fee2Month: heavy[1] ? heavy[1].month : F.toISO(F.addMonths(t, 2)).slice(0, 7),
      fee2Amount: heavy[1] ? heavy[1].amount : 0
    },
    fields: [
      { name: 'start', label: 'Semester start date', kind: 'date', required: true },
      { name: 'end', label: 'Semester end date', kind: 'date', required: true },
      { name: 'fee1Name', label: 'Heavy month 1 (name)', kind: 'text', placeholder: 'e.g. Exam fees, Hostel deposit', max: 60 },
      { name: 'fee1Month', label: 'Heavy month 1 (month)', kind: 'select', options: Array.from({ length: 6 }, (_, i) => { const d = F.addMonths(t, i); const k = F.toISO(d).slice(0, 7); return [k, monthLabelISO(k)]; }) },
      { name: 'fee1Amount', label: 'Heavy month 1 (amount)', kind: 'money', positive: true },
      { name: 'fee2Name', label: 'Heavy month 2 (name)', kind: 'text', placeholder: 'e.g. Festival trip, Moving', max: 60 },
      { name: 'fee2Month', label: 'Heavy month 2 (month)', kind: 'select', options: Array.from({ length: 6 }, (_, i) => { const d = F.addMonths(t, i); const k = F.toISO(d).slice(0, 7); return [k, monthLabelISO(k)]; }) },
      { name: 'fee2Amount', label: 'Heavy month 2 (amount)', kind: 'money', positive: true }
    ],
    onSave: v => {
      const heavyMonths = [];
      if (v.fee1Amount > 0 && v.fee1Name) {
        heavyMonths.push({ id: uid(), name: v.fee1Name.trim(), month: v.fee1Month, amount: v.fee1Amount });
      }
      if (v.fee2Amount > 0 && v.fee2Name) {
        heavyMonths.push({ id: uid(), name: v.fee2Name.trim(), month: v.fee2Month, amount: v.fee2Amount });
      }
      state.student = state.student || {};
      state.student.semester = {
        start: v.start,
        end: v.end,
        heavyMonths
      };
      commit();
      toast('Semester plan saved');
    }
  });
}

