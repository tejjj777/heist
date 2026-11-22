/* HEIST Travel Agent. Provider credentials remain in Supabase secrets. */
'use strict';
const HeistTravel = {
  busy: false, status: '', panel: 'Itinerary', query: '',
  list(v) { return Array.isArray(v) ? v.filter(x => x && typeof x === 'object') : []; },
  selected() { return (state.travelTrips || []).find(t => t.id === ui.travelId) || (state.travelTrips || [])[0]; },
  link(url, label) {
    try { const u = new URL(url); if (u.protocol !== 'https:' || u.username || u.password) return ''; }
    catch (_) { return ''; }
    return `<a class="btn btn-ghost" href="${esc(url)}" target="_blank" rel="noopener noreferrer">${esc(label)}</a>`;
  },
  money(t, n) { return state.settings.privacy ? '••••' : new Intl.NumberFormat('en-IN', {style:'currency',currency:CURRENCIES[t.currency] ? t.currency : 'INR'}).format(Number(n) || 0); },
  button(action, text, extra = '') { return `<button type="button" class="btn btn-ghost" data-travel="${action}" ${extra} ${this.busy ? 'disabled' : ''}>${esc(text)}</button>`; },
  card(html) { return `<article class="card"><div class="card-body">${html}</div></article>`; },
  create() {
    formModal({ title:'New travel plan', values:{startDate:todayISO(),days:3,travelers:2,budget:10000}, fields:[
      {name:'destination',label:'Destination',kind:'text',required:true},
      {name:'origin',label:'Starting city',kind:'text',required:true},
      {name:'startDate',label:'Departure date',kind:'date',required:true},
      {name:'days',label:'Days (1–14)',kind:'number',required:true,min:1,max:14},
      {name:'travelers',label:'Travelers (1–30)',kind:'number',required:true,min:1,max:30},
      {name:'budget',label:'Total group budget',kind:'money',required:true,positive:true},
      {name:'interests',label:'Interests, pace, accessibility and stay preferences',kind:'textarea',wide:true},
    ], onSave:v => {
      v.days=Number(v.days);v.travelers=Number(v.travelers);
      if(!Number.isInteger(v.days)||v.days<1||v.days>14||!Number.isInteger(v.travelers)||v.travelers<1||v.travelers>30){toast('Use 1–14 days and 1–30 travelers.');return false;}
      const trip={...v,id:uid(),currency:state.currency,pace:'balanced',status:'draft',expenses:[],people:Array.from({length:v.travelers},(_,i)=>`Traveler ${i+1}`)};
      state.travelTrips=state.travelTrips||[];state.travelTrips.push(trip);ui.travelId=trip.id;commit();
    }});
  },
  async request(stage,t) {
    const brief=Object.fromEntries(['destination','origin','startDate','days','travelers','budget','currency','interests','pace'].map(k=>[k,t[k]]));
    const token=await accessToken();
    const r=await fetch(SYNC_URL+'/functions/v1/travel',{method:'POST',signal:AbortSignal.timeout(65000),
      headers:{'Content-Type':'application/json',apikey:SYNC_KEY,Authorization:'Bearer '+token},
      body:JSON.stringify({stage,trip:brief,...(stage==='plan'?{research:t.research}:{})})});
    const data=await r.json();if(!r.ok)throw new Error(data.error||'Travel research is unavailable.');return data;
  },
  async generate() {
    const t=this.selected();if(!t||this.busy)return;
    if(!navigator.onLine){toast('Offline: saved trips and expenses work; live research needs internet.');return;}
    if(!Sync.acc||!Sync.acc.refresh){toast('Sign in from Account to research this trip.');return;}
    if(!window.confirm('Send destination, dates, group size, trip budget and preferences to the travel AI/search provider? Wallet balances, names and expense history are excluded. This builds a new itinerary; recorded expenses remain.'))return;
    this.busy=true;t.error='';
    try {
      if(!t.research){this.status='Searching current travel sources…';render();
        const research=await this.request('research',t);
        if(typeof research.summary!=='string'||this.list(research.sources).length<2)throw new Error('Research returned no attributable sources. Retry.');
        t.research=research;t.status='researched';save();
      }
      this.status='Building your day-by-day itinerary…';render();
      const result=await this.request('plan',t);
      if(!result.plan||this.list(result.plan.days).length!==t.days||!Array.isArray(result.plan.budget))throw new Error('Incomplete plan. Research is saved; retry.');
      t.plan=result.plan;t.status='ready';commit();
    }catch(e){t.error=e.name==='TimeoutError'?'Request timed out. Research is retained; retry.':e.message;save();}
    finally{this.busy=false;this.status='';render();}
  },
  expense() {
    const t=this.selected();if(!t)return;
    formModal({title:'Trip expense',values:{date:todayISO()},fields:[
      {name:'note',label:'What did you pay for?',kind:'text',required:true},
      {name:'amount',label:'Amount in '+t.currency,kind:'number',required:true,min:0.01},
      {name:'date',label:'Date',kind:'date',required:true},
      {name:'category',label:'Category',kind:'select',options:['Stay','Food','Transport','Activities','Other']},
      {name:'paidBy',label:'Paid by',kind:'select',options:t.people},
    ],onSave:v=>{if(!(v.amount>0))return false;t.expenses=t.expenses||[];t.expenses.push({...v,id:uid()});commit();}});
  },
  stop() {
    const t=this.selected();if(!t)return;
    formModal({title:'Add itinerary stop',fields:[
      {name:'day',label:'Day',kind:'select',options:Array.from({length:t.days},(_,i)=>[String(i+1),`Day ${i+1}`])},
      {name:'name',label:'Place or activity',kind:'text',required:true},
      {name:'time',label:'Time',kind:'text',required:true},
      {name:'notes',label:'Notes',kind:'textarea',wide:true},
      {name:'cost',label:'Estimated cost in '+t.currency,kind:'number',required:true,min:0},
    ],onSave:v=>{t.plan=t.plan||{days:Array.from({length:t.days},(_,i)=>({day:i+1,title:`Day ${i+1}`,stops:[]})),budget:[],hotels:[]};
      const d=t.plan.days[Number(v.day)-1];if(!d)return false;d.stops=HeistTravel.list(d.stops);d.stops.push(v);commit();}});
  },
  share() {
    const t=this.selected();if(!t)return;const copy=JSON.parse(JSON.stringify(t));delete copy.expenses;delete copy.error;
    const url=URL.createObjectURL(new Blob([JSON.stringify({format:'heist-trip',version:1,trip:copy},null,2)],{type:'application/json'}));
    const a=document.createElement('a');a.href=url;a.download='heist-trip-'+t.id+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  },
  content(t) {
    const p=t.plan||{}, money=n=>this.money(t,n), source=s=>this.link(s.sourceUrl,'Source');
    if(this.panel==='Itinerary')return this.list(p.days).map((d,i)=>this.card(`<h2>Day ${i+1}: ${esc(d.title||'')}</h2>`+this.list(d.stops).map(s=>
      `<div class="travel-stop"><h3>${esc(s.time||'')} ${esc(s.name||'')}</h3><p>${esc(s.notes||'')}</p><p>Estimate: ${money(s.cost)}</p>${this.link('https://www.google.com/maps/search/?api=1&query='+encodeURIComponent(s.name+', '+t.destination),'Google Maps')}${source(s)}</div>`).join(''))).join('')+this.button('stop','Add stop manually');
    if(this.panel==='Stays')return this.card(`<p>Check live prices, guest reviews, taxes, dates and cancellation rules with the provider. Saved costs are estimates, not availability.</p>
      ${this.link('https://www.booking.com/searchresults.html?ss='+encodeURIComponent(t.destination)+'&checkin='+encodeURIComponent(t.startDate)+'&group_adults='+t.travelers,'Booking.com')}
      ${this.link('https://www.tripadvisor.com/Search?q='+encodeURIComponent(t.destination+' hotels'),'Tripadvisor')}
      ${this.link('https://www.google.com/search?q='+encodeURIComponent('site:makemytrip.com/hotels/ '+t.destination+' '+t.startDate),'MakeMyTrip search')}
      <label for="travel-search">Filter saved stays by name, area or amenities</label><input id="travel-search" class="input" value="${esc(this.query)}">`)+
      this.list(p.hotels).filter(h=>`${h.name} ${h.area} ${h.amenities}`.toLowerCase().includes(this.query.toLowerCase())).sort((a,b)=>(a.nightlyEstimate||0)-(b.nightlyEstimate||0)).map(h=>this.card(`<h2>${esc(h.name||'')}</h2><p>${esc(h.area||'')} · nightly estimate ${money(h.nightlyEstimate)}</p><p>${esc(h.notes||'')}</p>${source(h)}`)).join('');
    if(this.panel==='Budget'){
      const expenses=this.list(t.expenses),spent=expenses.reduce((s,e)=>s+(Number(e.amount)||0),0);
      return this.card(`<h2>Trip budget</h2><p>Budget ${money(t.budget)} · spent ${money(spent)} · remaining ${money(t.budget-spent)}</p><p>Trip expenses stay separate from the main spending log.</p>${this.button('expense','Add trip expense')}`)+
        this.card('<h2>Estimated plan costs</h2>'+this.list(p.budget).map(b=>`<p>${esc(b.category)}: ${money(b.amount)}</p>`).join(''))+
        expenses.map(e=>this.card(`<strong>${esc(e.note)}: ${money(e.amount)}</strong><p>${esc(e.date)} · ${esc(e.category)} · paid by ${esc(e.paidBy)}</p>`)).join('');
    }
    if(this.panel==='Group'){
      const balances=Object.fromEntries(t.people.map(n=>[n,0]));
      for(const e of this.list(t.expenses)){
        if(!Object.hasOwn(balances,e.paidBy))continue;const minor=Math.round(Number(e.amount)*100);balances[e.paidBy]+=minor;
        t.people.forEach((n,i)=>balances[n]-=Math.floor(minor/t.people.length)+(i<minor%t.people.length?1:0));
      }
      return this.card('<h2>Equal group split</h2><p>Positive = should receive; negative = owes. No payments are made. Sharing exports a copy; live co-editing is not enabled.</p>'+Object.entries(balances).map(([n,b])=>`<p>${esc(n)}: ${money(b/100)}</p>`).join('')+this.button('share','Share itinerary copy'));
    }
    return this.card(`<h2>Research sources</h2><p>Updated: ${esc(t.research?.researchedAt||'Not researched')}</p><p>${esc(t.research?.summary||'Research online or add your own stops offline.')}</p>`+
      this.list(t.research?.sources).map(s=>this.link(s.url,s.title||s.url)).join('')+(Array.isArray(p.warnings)?p.warnings.map(w=>`<p>${esc(w)}</p>`).join(''):''));
  },
  bind() {
    const root=document.getElementById('view-travel');
    root.querySelectorAll('[data-travel]').forEach(b=>b.onclick=()=>{
      const action=b.dataset.travel;
      if(action==='panel'){this.panel=b.dataset.panel;render();}
      else if(['create','generate','expense','stop','share'].includes(action))this[action]();
    });
    const select=root.querySelector('#travel-selected');if(select)select.onchange=()=>{ui.travelId=select.value;render();};
    const search=root.querySelector('#travel-search');if(search)search.oninput=()=>{this.query=search.value;render();};
  }
};
function renderTravel() {
  const t=HeistTravel.selected(), trips=state.travelTrips||[];
  return {html:`<div class="heist-travel"><div class="view-head"><h1 id="h-travel">Travel Agent</h1><p>Your next escape, planned. Itinerary, stays, sources and trip spending in one place.</p>${HeistTravel.button('create','New trip')}</div>`+
    (trips.length?HeistTravel.card(`<label for="travel-selected">Saved trips</label><select id="travel-selected" class="select">${trips.map(x=>`<option value="${esc(x.id)}" ${t&&t.id===x.id?'selected':''}>${esc(x.destination)} · ${esc(x.startDate)}</option>`).join('')}</select>`):HeistTravel.card('<h2>Start your next adventure</h2><p>Create a trip with dates, travelers and a group budget. Research needs sign-in and internet. Saved trips and expenses work offline.</p>'))+
    (t?HeistTravel.card(`<h2>${esc(t.destination)} · ${t.days} days · ${t.travelers} travelers</h2><p>${esc(t.origin)} → ${esc(t.destination)} · ${esc(t.startDate)} · ${HeistTravel.money(t,t.budget)} group budget</p><p role="status">${esc(HeistTravel.status||t.error||'Saved locally. Live research and maps need internet.')}</p>${HeistTravel.button('generate',t.research?'Resume / rebuild plan':'Research & build trip')}${HeistTravel.button('share','Share itinerary')}`)+
      `<div class="travel-panels" aria-label="Travel sections">${['Itinerary','Stays','Budget','Group','Sources'].map(n=>HeistTravel.button('panel',n,`data-panel="${n}" aria-pressed="${HeistTravel.panel===n}"`)).join('')}</div>`+HeistTravel.content(t):'')+'</div>',charts:()=>HeistTravel.bind()};
}
