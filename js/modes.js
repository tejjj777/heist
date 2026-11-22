/* HEIST · Student and Working modes.
   The mode decides what the app looks like (semester plan vs payday, roommates vs flatmates, campus vs household
   categories). Income sources are separate and stack: a student can also have a job, salary or freelance work.
   Classic script: shares one global scope with the other js/ files (see README-AGENTS.md). */
'use strict';

const LIFE_MODES = [['student', 'Student'], ['working', 'Working']];
const INCOME_TYPES = [['allowance', 'Pocket money'], ['parttime', 'Part-time job'], ['salary', 'Salary'], ['freelance', 'Freelance or gig'], ['business', 'Business']];

function isWorking() { return state.settings.lifeMode === 'working'; }
function hasIncome(t) { return (state.settings.incomeTypes || []).includes(t); }
/** XP, Slime, quests and money weather: on for students by default, off for working people (a switch in Settings). */
function funOn() { return state.settings.funLayer !== false; }
/** Simple view: the same app with a clean, flat look and bigger text, for parents and grandparents. */
function isSimple() { return !!(typeof state !== 'undefined' && state && state.settings && state.settings.simple); }
function toggleSimple() {
  state.settings.simple = !state.settings.simple;
  save(); applyLifeMode(); render();
  toast(state.settings.simple ? 'Simple view on. Turn it off in Settings.' : 'Simple view off', 4000);
}

/* ---------- Tabs and labels that change with the mode ---------- */
const BASE_TABS = JSON.parse(JSON.stringify(TABS));
let tabsFor = null;   // which mode the tab lists were last built for
function lifeModeStale() { return tabsFor !== (isWorking() ? 'w' : 's') + (isSimple() ? '1' : '0'); }
const BASE_SPLIT_LONG = (ROUTES.find(r => r.id === 'split') || {}).long;
function applyLifeMode() {
  const w = isWorking(), simple = isSimple();
  tabsFor = (w ? 'w' : 's') + (simple ? '1' : '0');
  for (const r of Object.keys(BASE_TABS)) TABS[r] = BASE_TABS[r].slice();
  TABS.dashboard = BASE_TABS.dashboard.filter(([k]) => !(w && k === 'semester'));
  TABS.budget = BASE_TABS.budget.map(([k, l]) => [k, w && k === 'yearly' ? 'Yearly bills' : l]);
  TABS.split = BASE_TABS.split.map(([k, l]) => [k, w && k === 'ious' ? 'IOUs & Flatmates' : l]);
  const sp = ROUTES.find(r => r.id === 'split');
  if (sp) sp.long = w ? 'Split & Shared costs' : BASE_SPLIT_LONG;
  document.documentElement.classList.toggle('simple', simple);
  document.body.classList.toggle('mode-working', w);
  document.body.classList.toggle('mode-student', !w);
  workWordsObserve(w);
}

/* ---------- Working mode: say "pay" and "payday" instead of "allowance" everywhere ---------- */
const WORK_WORDS = [
  [/Pocket money \/ Allowance/g, 'Salary / Pay'], [/allowance or pocket money/gi, 'take-home pay'],
  [/Allowance in\b/g, 'Payday in'], [/allowance in\b/g, 'payday in'],
  [/next allowance/g, 'next payday'], [/Next allowance/g, 'Next payday'],
  [/Monthly allowance/g, 'Monthly pay'], [/monthly allowance/g, 'monthly pay'],
  [/pocket money/g, 'pay'], [/Pocket money/g, 'Pay'], [/allowances\b/g, 'paydays'],
  [/allowance/g, 'pay'], [/Allowance/g, 'Pay'],
  [/Split & Roommates/g, 'Split & Shared costs'], [/IOUs & Roommates/g, 'IOUs & Flatmates'],
  [/roommates/g, 'flatmates'], [/Roommates/g, 'Flatmates'], [/roommate/g, 'flatmate'], [/Roommate/g, 'Flatmate'],
  [/Yearly \/ Semester fees/g, 'Yearly bills'], [/student budget/g, 'budget'], [/hostel and college life/g, 'everyday life']
];
const WORK_SKIP = new Set(['SCRIPT', 'STYLE', 'TEXTAREA', 'INPUT', 'CODE', 'PRE']);
function workWords(s) { let o = s; for (const [re, to] of WORK_WORDS) o = o.replace(re, to); return o; }
function workWordsIn(root) {
  if (!root || !isWorking()) return;
  if (root.nodeType === 3) { const v = workWords(root.nodeValue); if (v !== root.nodeValue) root.nodeValue = v; return; }
  if (root.nodeType !== 1 || WORK_SKIP.has(root.nodeName) || root.closest && root.closest('[data-raw]')) return;
  for (const a of ['placeholder', 'aria-label', 'title']) if (root.hasAttribute && root.hasAttribute(a)) { const v = workWords(root.getAttribute(a)); if (v !== root.getAttribute(a)) root.setAttribute(a, v); }
  for (const c of Array.from(root.childNodes)) workWordsIn(c);
}
let workObserver = null;
function workWordsObserve(on) {
  if (typeof MutationObserver !== 'function') return;
  if (on && !workObserver) {
    workObserver = new MutationObserver(list => { for (const m of list) m.addedNodes.forEach(workWordsIn); });
    workObserver.observe(document.body, { childList: true, subtree: true });
    workWordsIn(document.body);
  } else if (!on && workObserver) { workObserver.disconnect(); workObserver = null; }
}

/* ---------- Starter budget for working people ---------- */
function workingStarterPlan(living = 'flatmates') {
  const inc = computedMonthlyIncome(), r = roundUpFor(state.currency), round = v => Math.max(0, Math.round(v / r) * r);
  const rent = living === 'family' ? 0 : living === 'own' ? 0.15 : living === 'alone' ? 0.3 : 0.22;
  const cats = [
    living === 'own' ? ['Home loan & upkeep', 'needs', rent] : rent ? ['Rent', 'needs', rent] : ['Home & family share', 'needs', 0.1],
    ['Groceries', 'needs', 0.12], ['Bills & internet', 'needs', 0.05], ['Travel & fuel', 'needs', 0.07],
    ['Insurance & health', 'needs', 0.04], ['Eating out', 'wants', 0.06], ['Shopping', 'wants', 0.05],
    ['Fun & subscriptions', 'wants', 0.04], ['Emergency fund', 'savings', 0.1], ['Investments & goals', 'savings', 0.1]
  ];
  const used = cats.reduce((t, c) => t + c[2], 0);
  cats.push(['Other', 'wants', Math.max(0, 1 - used)]);
  state.budget.categories = cats.filter(c => c[2] > 0).map(([name, type, p]) => ({ id: uid(), name, type, planned: round(inc * p), actual: 0 }));
}

/* ---------- Emergency fund suggestion (both modes) ---------- */
function emergencyFundInfo() {
  const needs = state.budget.categories.filter(c => c.type === 'needs').reduce((t, c) => t + (Number(c.planned) || 0), 0);
  const monthly = needs > 0 ? needs : computedMonthlyIncome() * 0.6;
  const months = isWorking() ? 3 : 1;
  const goal = state.goals.find(g => /emergency/i.test(g.name));
  return { monthly, months, target: monthly * months, goal, saved: goal ? Number(goal.saved) || 0 : 0 };
}
function emergencyFundCard() {
  const ef = emergencyFundInfo();
  if (!(ef.target > 0)) return '';
  const pct = Math.min(100, ef.saved / ef.target * 100);
  return `<div class="card mb ef-card" id="ef-card">
    <div class="card-head"><div><h2>Emergency fund</h2><p class="muted small">${isWorking()
      ? `Aim for ${ef.months} months of your needs: rent, food, bills and travel. 6 months is even safer.`
      : 'Aim for one month of your needs, for a surprise bill, a broken phone or a trip home.'}</p></div></div>
    <div class="ef-row"><div><p class="stat-label">Suggested</p><p class="stat-value">${fmt(ef.target)}</p><p class="small muted">${ef.months} × ${fmt(ef.monthly)} a month of needs</p></div>
      <div><p class="stat-label">Saved so far</p><p class="stat-value">${fmt(ef.saved)}</p><p class="small muted">${ef.goal ? `in “${esc(ef.goal.name)}”` : 'No emergency fund goal yet'}</p></div></div>
    <span class="hc-bar" role="meter" aria-label="Emergency fund saved" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(pct)}"><span style="width:${pct}%"></span></span>
    <div class="row" style="margin-top:12px">${ef.goal
      ? (ef.goal.target < ef.target - 1 ? `<button type="button" class="btn btn-sm" data-action="ef-goal">Raise the goal to ${fmt(ef.target)}</button>` : `<span class="small muted">${pct >= 100 ? 'You’re covered. Nice.' : `${fmt(ef.target - ef.saved)} to go.`}</span>`)
      : `<button type="button" class="btn btn-sm btn-primary" data-action="ef-goal">Start an emergency fund</button>`}</div>
  </div>`;
}
function emergencyFundGoal() {
  const ef = emergencyFundInfo();
  if (ef.goal) { ef.goal.target = Math.round(ef.target); toast(`Emergency fund goal set to ${fmt(ef.target)}`); }
  else { state.goals.push({ id: uid(), name: 'Emergency fund', target: Math.round(ef.target), saved: 0, deadline: '', planMonthly: null, contributions: [] }); toast(`Emergency fund goal added: ${fmt(ef.target)}`); }
  commit();
}

/* ---------- Settings: who the app is for ---------- */
function modeSettingsHTML() {
  const s = state.settings;
  return `<div class="settings-group"><h3>About you</h3><div class="form-grid two">
    <div class="field"><span class="field-label">I’m a</span>${segRadio({ name: 'set-lifemode', label: 'Student or working', value: s.lifeMode, attrs: 'data-setting="lifeMode" data-kind="select"', options: LIFE_MODES })}
      <p class="help">Students see the semester plan and allowance. Working shows payday and household costs.</p></div>
    <div class="field span-2 simple-field"><span class="field-label">Simple view</span><label class="check"><input type="checkbox" id="set-simple" data-setting="simple" data-kind="bool" ${isSimple() ? 'checked' : ''}> Clean, plain look with bigger text</label>
      <p class="help">Good for parents and grandparents. Every feature stays, just calmer: no bold shadows or animations.</p></div>
    <div class="field"><span class="field-label">Games and Slime</span><label class="check"><input type="checkbox" id="set-fun" data-setting="funLayer" data-kind="bool" ${funOn() ? 'checked' : ''}> Show XP, Slime and quests</label></div>
    <fieldset class="field span-2"><legend class="field-label">Where your money comes from</legend><div class="chip-row">${INCOME_TYPES.map(([k, l]) =>
      `<label class="pl-choice"><input type="checkbox" data-income-type="${k}" ${hasIncome(k) ? 'checked' : ''}><span>${l}</span></label>`).join('')}</div>
      <p class="help">Tick all that apply. Freelance or business income can vary month to month.</p></fieldset>
  </div></div>`;
}
function bindModeSettings(form) {
  form.querySelectorAll('[data-income-type]').forEach(cb => cb.addEventListener('change', () => {
    state.settings.incomeTypes = INCOME_TYPES.map(([k]) => k).filter(k => form.querySelector(`[data-income-type="${k}"]`).checked);
    save(); scheduleRender(300);
  }));
}
