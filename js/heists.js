/* HEIST · Crew Heists: a shared goal your friends save toward together.
   A heist is a live group (js/groups.js) with two kinds of special rows in group_expenses, so no database change is needed:
     "HEIST_GOAL {json}"  the plan: name, target, deadline (paid by the creator and split to the creator, so it moves no balance)
     "HEIST_DEPOSIT"      money a member put in the vault (paid by them and split to them, so it moves no balance)
   These rows are left out of balances, the expense list and personal spending. Each member's own share also shows as a
   personal goal, so it counts in Goals & Savings.
   Classic script: shares one global scope with the other js/ files (see README-AGENTS.md). */
'use strict';

const HEIST_GOAL = 'HEIST_GOAL ', HEIST_DEPOSIT = 'HEIST_DEPOSIT';
function isHeistRow(ex) { return !!ex && typeof ex.description === 'string' && (ex.description.startsWith(HEIST_GOAL) || ex.description === HEIST_DEPOSIT); }

/** The heist inside a group, or null. Everything here is derived from the group's rows, so every member sees the same thing. */
function heistInfo(groupId) {
  const g = (state.groups || []).find(x => x.id === groupId);
  const data = (state.groupData || {})[groupId];
  if (!g || !data) return null;
  const rows = data.expenses || [];
  const goalRow = rows.filter(ex => typeof ex.description === 'string' && ex.description.startsWith(HEIST_GOAL)).slice(-1)[0];
  if (!goalRow) return null;
  let meta = {};
  try { meta = JSON.parse(goalRow.description.slice(HEIST_GOAL.length)) || {}; } catch (e) { meta = {}; }
  const target = Number(meta.target) || Number(goalRow.amount) || 0;
  const members = (data.members || []).map(m => ({ id: m.id, name: m.name, me: m.id === g.myMemberId, put: 0 }));
  rows.filter(ex => ex.description === HEIST_DEPOSIT).forEach(ex => {
    const m = members.find(x => x.id === ex.paid_by); if (m) m.put += Number(ex.amount) || 0;
  });
  const saved = members.reduce((t, m) => t + m.put, 0);
  const n = Math.max(1, members.length);
  const share = target / n;
  const deadline = F.parseDate(meta.deadline) ? meta.deadline : '';
  const today = todayDate();
  const start = F.parseDate(String(goalRow.created_at || '').slice(0, 10)) || today;
  const end = deadline ? F.parseDate(deadline) : null;
  const weeksLeft = end ? Math.max(1, Math.ceil(F.daysBetween(today, end) / 7)) : null;
  const span = end ? Math.max(1, F.daysBetween(start, end)) : null;
  const doneFrac = end ? Math.min(1, Math.max(0, F.daysBetween(start, today) / span)) : null;
  members.forEach(m => {
    m.left = Math.max(0, share - m.put);
    m.weekly = weeksLeft ? m.left / weeksLeft : null;
    m.expected = doneFrac === null ? null : share * doneFrac;
    m.behind = m.expected !== null && m.put + 0.5 < m.expected && m.left > 0;
  });
  members.sort((a, b) => b.put - a.put);
  return { groupId, name: String(meta.name || g.name).slice(0, 60), target, deadline, saved, share, members, weeksLeft, pct: target > 0 ? Math.min(100, saved / target * 100) : 0, me: members.find(m => m.me) };
}

/** Keep the member's personal goal for this heist in step: their fair share, and the right name. */
function heistSyncLocalGoal(groupId) {
  const h = heistInfo(groupId);
  if (!h) return;
  let goal = state.goals.find(x => x.heistGroupId === groupId);
  if (!goal) { goal = { id: uid(), name: h.name, target: 0, saved: 0, deadline: '', planMonthly: null, contributions: [], heistGroupId: groupId }; state.goals.push(goal); }
  goal.name = ('Heist: ' + h.name).slice(0, 60);
  goal.target = Math.round(h.share);
  if (h.deadline) goal.deadline = h.deadline;
  // deposits made on another device or before this goal existed still count
  const mine = h.me ? Math.round(h.me.put * 100) / 100 : 0;
  if (mine > goal.saved + 0.004) { const add = Math.round((mine - goal.saved) * 100) / 100; goal.saved += add; goal.contributions.push({ id: uid(), date: todayISO(), amount: add, note: 'Crew heist deposits' }); }
}

function heistInviteText(h, code) {
  return `Join my HEIST crew for "${h.name}". We need ${fmt(h.target)} together${h.deadline ? ` by ${fmtDate(F.parseDate(h.deadline))}` : ''}.\n` +
    `Open ${location.origin}${location.pathname.replace(/index\.html$/, '')}#split/groups, tap "Join with code" and enter ${code}.`;
}

/** Start a heist: makes a live group, stores the plan in it, and adds your share as a personal goal. */
function heistForm(preset = {}) {
  formModal({
    title: 'Start a crew heist', submitLabel: 'Start the heist',
    values: { name: preset.name || '', target: preset.target || '', deadline: preset.deadline || '', myName: (state.settings.myName || '') },
    fields: [
      { name: 'name', label: 'What are you saving for?', kind: 'text', required: true, placeholder: 'e.g. Goa trip in December', wide: true },
      { name: 'target', label: 'Crew’s total target', kind: 'money', required: true, positive: true, help: preset.target ? 'From your plan. If the plan was only your share, change this to the whole crew’s total.' : 'The total everyone saves together. It’s split equally between the crew.' },
      { name: 'deadline', label: 'Needed by', kind: 'date', help: 'Optional. Sets how much each person puts in each week.' },
      { name: 'myName', label: 'Your name in the crew', kind: 'text', required: true, placeholder: 'e.g. Tej' }
    ],
    onSave: async v => {
      if (!navigator.onLine) { toast('Crew heists need internet. Try again when you’re online.'); return false; }
      toast('Setting up your heist…', 2500);
      try {
        if (!(await GroupSync.ready())) throw new Error('offline');
        state.settings.myName = v.myName;
        const group = await GroupSync.createGroup(v.name, v.myName);
        const g = state.groups.find(x => x.id === group.id);
        const meta = { name: v.name, target: v.target, deadline: v.deadline || '' };
        GroupSync.addExpense(group.id, HEIST_GOAL + JSON.stringify(meta), v.target, { [g.myMemberId]: v.target });
        heistSyncLocalGoal(group.id);
        commit();
        setTimeout(() => heistView(group.id), 50);
      } catch (e) {
        console.warn('Heist setup failed', e);
        toast(groupErrorText(e), 4000);
      }
    }
  });
}

function heistDeposit(groupId) {
  const h = heistInfo(groupId), g = state.groups.find(x => x.id === groupId);
  if (!h || !g) return;
  const suggest = h.me && h.me.weekly ? Math.ceil(h.me.weekly) : '';
  formModal({
    title: `Add to the ${h.name} vault`, submitLabel: 'Add to the vault',
    values: { amount: suggest },
    fields: [{ name: 'amount', label: 'How much are you putting in?', kind: 'money', required: true, positive: true,
      help: h.me ? `Your share is ${fmt(h.share)}. You’ve put in ${fmt(h.me.put)}${h.me.weekly ? `, so about ${fmt(h.me.weekly)} a week keeps you on track` : ''}.` : '' }],
    onSave: v => {
      GroupSync.addExpense(groupId, HEIST_DEPOSIT, v.amount, { [g.myMemberId]: v.amount });
      heistSyncLocalGoal(groupId);
      commit(); playSound('coin'); toast(`${fmt(v.amount)} added to the ${h.name} vault`);
      setTimeout(() => heistView(groupId), 50);
    }
  });
}

function heistPanelHTML(groupId) {
  const h = heistInfo(groupId), g = state.groups.find(x => x.id === groupId);
  if (!h || !g) return '';
  const behind = h.members.filter(m => m.behind);
  return `<div class="heist-panel">
    <div class="heist-vault card featured">
      <p class="stat-label">The vault</p>
      <p class="heist-amt">${fmt(h.saved)} <span class="muted">of ${fmt(h.target)}</span></p>
      <span class="hc-bar heist-bar" role="meter" aria-label="Vault filled" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(h.pct)}"><span style="width:${h.pct}%"></span></span>
      <p class="small muted">${h.pct >= 100 ? 'Vault cracked. You did it.' : `${Math.round(h.pct)}% there${h.deadline ? ` · needed by ${fmtDate(F.parseDate(h.deadline))}${h.weeksLeft ? ` (${plural(h.weeksLeft, 'week')} left)` : ''}` : ''}`}</p>
    </div>
    ${behind.length && h.pct < 100 ? `<p class="heist-nudge" role="status">${heistBehindLine(behind)}</p>` : ''}
    <h3 style="margin-top:12px">The crew</h3>
    <ul class="plain-list heist-crew">${h.members.map(m => `<li class="heist-member ${m.behind ? 'is-behind' : ''}">
      <div><strong>${esc(m.name)}</strong>${m.me ? ' (you)' : ''}<br><span class="small muted">Put in ${fmt(m.put)} of ${fmt(h.share)}${m.weekly && m.left > 0 ? ` · ${fmt(m.weekly)}/week to finish` : m.left <= 0 ? ' · share done' : ''}</span></div>
      <span class="hc-bar heist-mini" aria-hidden="true"><span style="width:${h.share > 0 ? Math.min(100, m.put / h.share * 100) : 0}%"></span></span>
    </li>`).join('')}</ul>
    <div class="row heist-actions">
      <button type="button" class="btn btn-primary" data-action="heist-deposit" data-id="${groupId}">Add to the vault</button>
      <button type="button" class="btn" data-action="heist-invite" data-id="${groupId}">Invite your crew</button>
    </div>
    <p class="small muted">Join code <strong>${esc(g.joinCode)}</strong>. Everyone saves their own share; the vault fills live for the whole crew.</p>
  </div>`;
}

function heistBehindLine(list) {
  const names = list.map(m => m.me ? 'you' : esc(m.name));
  const who = names.length === 1 ? names[0] : names.slice(0, -1).join(', ') + ' and ' + names[names.length - 1];
  const solo = list.length === 1 && list[0].me;
  return (who.charAt(0).toUpperCase() + who.slice(1)) + (solo ? '’re' : list.length === 1 ? ' is' : ' are') + ' behind on this job.';
}

function heistView(groupId) {
  const h = heistInfo(groupId);
  if (!h) { toast('Loading the heist…'); GroupSync.ready().then(() => GroupSync.fetchGroupData(groupId)); return; }
  openModal({ title: '🎯 ' + h.name, hideSubmit: true, cancelLabel: 'Close', body: heistPanelHTML(groupId) +
    `<details class="collapsible" style="margin-top:12px"><summary>Shared costs in this group</summary><div class="details-body"><button type="button" class="btn btn-sm" data-action="group-view" data-id="${groupId}">Open the group</button></div></details>` });
}

const HEIST_ACTIONS = {
  'heist-new': () => heistForm(),
  'heist-view': el => heistView(el.dataset.id),
  'heist-deposit': el => heistDeposit(el.dataset.id),
  'heist-invite': el => {
    const h = heistInfo(el.dataset.id), g = state.groups.find(x => x.id === el.dataset.id);
    if (!h || !g) return;
    const text = heistInviteText(h, g.joinCode);
    if (navigator.share) navigator.share({ title: 'Join my HEIST crew', text }).catch(() => {});
    else copyText(text, 'Invite copied. Send it to your crew.');
  }
};

/** "Your crew heists" card for Goals and Split. */
function heistsCard() {
  const list = (state.groups || []).map(g => heistInfo(g.id)).filter(Boolean);
  return `<div class="card mb" id="heists-card"><div class="card-head"><div><h2>Crew heists</h2><p class="muted small">Save for a trip or a big plan together. Everyone puts in their share and watches the vault fill.</p></div>
    <div class="actions no-print"><button type="button" class="btn btn-sm btn-primary" data-action="heist-new">${ICON.plus}<span>New heist</span></button></div></div>
    ${list.length ? `<ul class="plain-list">${list.map(h => `<li class="heist-li"><button type="button" class="heist-open" data-action="heist-view" data-id="${h.groupId}">
        <span class="heist-li-top"><strong>🎯 ${esc(h.name)}</strong><span class="small">${fmt(h.saved)} of ${fmt(h.target)}</span></span>
        <span class="hc-bar" aria-hidden="true"><span style="width:${h.pct}%"></span></span>
        <span class="small muted">${plural(h.members.length, 'person', 'people')}${h.me ? ` · you’ve put in ${fmt(h.me.put)} of ${fmt(h.share)}` : ''}${h.members.some(m => m.behind) ? ' · someone’s behind' : ''}</span></button></li>`).join('')}</ul>`
      : '<p class="small muted">No heists yet. Plan a trip with Plan it, then turn it into a crew heist, or start one here.</p>'}
  </div>`;
}
