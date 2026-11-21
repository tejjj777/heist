/* HEIST · Constants, countries, small utilities, display formatting.
   Classic script: shares one global scope with the other js/ files (see README-AGENTS.md). */
'use strict';
const F = FinMath;
const STORAGE_KEY = 'yoko.student.v1';   // HEIST's own key. Never read or migrate main HEIST's 'paywise.v1'.
const APP_NAME = 'HEIST';
const SUPPORT_EMAIL = '';   // support address: shown in Settings → Help when set. Also add it to privacy.html and terms.html (search “support email”).
const GOATCOUNTER_CODE = '';   // visit counter (goatcounter.com, no cookies). Empty string turns it off.
/* The HEIST logo, embedded so it also works in exported images (a file:// image would block canvas export). */
const LOGO_URI = 'data:image/png;base64,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';
const LOGO_IMG = new Image();
LOGO_IMG.src = LOGO_URI;
const THEMES = {
  yoko: { label: 'HEIST', swatch: ['#0A0A0A', '#7ED957'], meta: '#0A0A0A', chart: ['#7ED957', '#B8F09E', '#E8E8E8', '#4E9E34', '#9A9A9A', '#2F6B22'] },
  blue: { label: 'Black & Blue', swatch: ['#0A0A0A', '#3B9EFF'], meta: '#0A0A0A', chart: ['#3B9EFF', '#9CCCFF', '#E8E8E8', '#1E6FCC', '#9A9A9A', '#0E4A8F'] },
  red: { label: 'Black & Red', swatch: ['#0A0A0A', '#FF4D4D'], meta: '#0A0A0A', chart: ['#FF4D4D', '#FFA3A3', '#E8E8E8', '#C92A2A', '#9A9A9A', '#7A1414'] }
};
const THEME_KEYS = Object.keys(THEMES);

/* ---------- Constants ---------- */
const FREQS = [
  ['weekly', 'Weekly'], ['biweekly', 'Every 2 weeks'], ['semimonthly', 'Twice a month'],
  ['monthly', 'Monthly'], ['yearly', 'Yearly']
];
const FREQ_LABEL = Object.fromEntries(FREQS);
const OCCASIONS = ['Birthday', 'Anniversary', 'Christmas', 'Diwali', 'Eid', 'Hanukkah', 'Lunar New Year', 'Valentine’s Day', 'Mother’s Day', 'Father’s Day', 'Wedding', 'Graduation', 'Raksha Bandhan', 'Custom'];
const GIFT_STATUS = ['Idea', 'Bought', 'Given'];
const CAT_TYPES = [['needs', 'Need'], ['wants', 'Want'], ['savings', 'Saving']];
const BUCKET_ROLES = ['bills', 'debt', 'goals', 'gifts', 'spending', 'custom'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const ROUTES = [
  { id: 'dashboard', label: 'Dashboard', short: 'Home', icon: 'dashboard' },
  { id: 'spend', label: 'Spend', short: 'Spend', icon: 'wallet2' },
  { id: 'budget', label: 'Budget', short: 'Budget', icon: 'budget' },
  { id: 'split', label: 'Split', short: 'Split', icon: 'debt', long: 'Split & Roommates' },
  { id: 'goals', label: 'Goals', short: 'Goals', icon: 'goal', long: 'Goals & Savings' },
  { id: 'debt', label: 'Debt', short: 'Debt', icon: 'debt', long: 'Debt & Loans' }
];

const svg = (p, size = 20) => `<svg class="icon" viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square" stroke-linejoin="miter" aria-hidden="true" focusable="false">${p}</svg>`;
const ICON = {
  mic: svg('<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>'),
  stop: svg('<rect x="6" y="6" width="12" height="12"/>'),
  camera: svg('<path d="M4 7h4l2-3h4l2 3h4v12H4z"/><circle cx="12" cy="13" r="3.5"/>'),
  receipt: svg('<path d="M6 3h12v18l-3-2-3 2-3-2-3 2zM9 8h6M9 12h6"/>'),
  dashboard: svg('<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>'),
  debt: svg('<rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M2.5 10h19M6.5 15h4"/>'),
  budget: svg('<path d="M21 12.5A9 9 0 1 1 11.5 3v9.5z"/><path d="M14.5 3.2A9 9 0 0 1 20.8 9.5h-6.3z"/>'),
  gift: svg('<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M12 8v13M5 12v9h14v-9"/><path d="M12 8H8.5a2.5 2.5 0 1 1 0-5C11 3 12 8 12 8zM12 8h3.5a2.5 2.5 0 1 0 0-5C13 3 12 8 12 8z"/>'),
  goal: svg('<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.2"/>'),
  settings: svg('<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>'),
  print: svg('<path d="M6 9V3h12v6"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="7" rx="1"/>', 18),
  plus: svg('<path d="M12 5v14M5 12h14"/>', 18),
  wallet: svg('<path d="M3 7h15a3 3 0 0 1 3 3v7a3 3 0 0 1-3 3H3z"/><path d="M3 7V5.5A2.5 2.5 0 0 1 5.5 3H16v4"/><circle cx="16.5" cy="13.5" r="1.2"/>', 18),
  edit: svg('<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>', 18),
  trash: svg('<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>', 18),
  download: svg('<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>', 16),
  warn: svg('<path d="M12 3l9.5 17h-19z"/><path d="M12 10v4M12 17.5v.01"/>', 18),
  close: svg('<path d="M6 6l12 12M18 6L6 18"/>', 20),
  moon: svg('<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>'),
  sun: svg('<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>'),
  search: svg('<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>'),
  palette: svg('<path d="M12 3a9 9 0 1 0 0 18c1.1 0 1.7-.9 1.4-1.9l-.3-.9c-.3-1 .4-2.2 1.6-2.2H17a4 4 0 0 0 4-4c0-5-4-9-9-9z"/><circle cx="7.5" cy="11" r="1.2"/><circle cx="10.5" cy="7" r="1.2"/><circle cx="15" cy="7.5" r="1.2"/>'),
  wallet2: svg('<path d="M3 7h15a3 3 0 0 1 3 3v7a3 3 0 0 1-3 3H3z"/><path d="M3 7V5.5A2.5 2.5 0 0 1 5.5 3H16v4"/><path d="M16 13.5h2"/>'),
  upload: svg('<path d="M12 16V4M7 9l5-5 5 5M5 20h14"/>', 18)
};
const BOSS_EMOJI = ['👾', '🐉', '🦖', '👹', '🐙', '🦂'];
const TRANSPORT_MODES = [
  ['fuel', '⛽', 'Fuel / charging'], ['cab', '🚕', 'Cab / ride'], ['auto', '🛺', 'Auto / tuk-tuk'], ['metro', '🚇', 'Metro / train'],
  ['bus', '🚌', 'Bus'], ['flight', '✈️', 'Flight'], ['parking', '🅿️', 'Parking / toll'], ['service', '🔧', 'Vehicle service'],
  ['insurance', '🛡️', 'Vehicle insurance'], ['other', '🚲', 'Other']
];
const TRANSPORT_KEYS = TRANSPORT_MODES.map(m => m[0]);
const TRANSPORT_WORDS = { fuel: 'fuel', petrol: 'fuel', diesel: 'fuel', cng: 'fuel', charging: 'fuel', cab: 'cab', uber: 'cab', ola: 'cab', rapido: 'cab', taxi: 'cab', lyft: 'cab',
  auto: 'auto', rickshaw: 'auto', metro: 'metro', train: 'metro', rail: 'metro', bus: 'bus', flight: 'flight', parking: 'parking', toll: 'parking', fastag: 'parking', repair: 'service', tyre: 'service', tire: 'service' };
const DOW_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const FULL_DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const FULL_MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/* ---------- Countries: currency, tax year, date order ---------- */
const CURRENCIES = {
  USD: { symbol: '$', locale: 'en-US' }, EUR: { symbol: '€', locale: 'en-IE' }, GBP: { symbol: '£', locale: 'en-GB' },
  INR: { symbol: '₹', locale: 'en-IN' }, CAD: { symbol: 'C$', locale: 'en-CA' }, AUD: { symbol: 'A$', locale: 'en-AU' },
  NZD: { symbol: 'NZ$', locale: 'en-NZ' }, SGD: { symbol: 'S$', locale: 'en-SG' }, AED: { symbol: 'AED', locale: 'en-AE' },
  SAR: { symbol: 'SAR', locale: 'en-US' }, JPY: { symbol: '¥', locale: 'en-US' }, CNY: { symbol: 'CN¥', locale: 'en-US' },
  KRW: { symbol: '₩', locale: 'en-US' }, HKD: { symbol: 'HK$', locale: 'en-HK' }, CHF: { symbol: 'CHF', locale: 'en-US' },
  SEK: { symbol: 'kr', locale: 'en-US' }, NOK: { symbol: 'kr', locale: 'en-US' }, DKK: { symbol: 'kr', locale: 'en-US' },
  PLN: { symbol: 'zł', locale: 'en-US' }, TRY: { symbol: '₺', locale: 'en-US' }, BRL: { symbol: 'R$', locale: 'en-US' },
  MXN: { symbol: 'MX$', locale: 'en-US' }, ZAR: { symbol: 'R', locale: 'en-ZA' }, NGN: { symbol: '₦', locale: 'en-NG' },
  KES: { symbol: 'KSh', locale: 'en-KE' }, PKR: { symbol: 'Rs', locale: 'en-PK' }, BDT: { symbol: '৳', locale: 'en-US' },
  LKR: { symbol: 'Rs', locale: 'en-US' }, EGP: { symbol: 'E£', locale: 'en-US' }, PHP: { symbol: '₱', locale: 'en-PH' },
  MYR: { symbol: 'RM', locale: 'en-MY' }, IDR: { symbol: 'Rp', locale: 'en-US' }, THB: { symbol: '฿', locale: 'en-US' },
  VND: { symbol: '₫', locale: 'en-US' }
};
const NO_DECIMALS = new Set(['JPY', 'KRW', 'VND', 'IDR']);
/* fy = month the tax year starts; dates = how people write 03/04 */
const COUNTRIES = {
  US: ['United States', 'USD', 1, 'mdy'], GB: ['United Kingdom', 'GBP', 4], IN: ['India', 'INR', 4], CA: ['Canada', 'CAD', 1],
  AU: ['Australia', 'AUD', 7], NZ: ['New Zealand', 'NZD', 4], IE: ['Ireland', 'EUR', 1], DE: ['Germany', 'EUR', 1], FR: ['France', 'EUR', 1],
  ES: ['Spain', 'EUR', 1], IT: ['Italy', 'EUR', 1], NL: ['Netherlands', 'EUR', 1], CH: ['Switzerland', 'CHF', 1], SE: ['Sweden', 'SEK', 1],
  NO: ['Norway', 'NOK', 1], DK: ['Denmark', 'DKK', 1], PL: ['Poland', 'PLN', 1], TR: ['Türkiye', 'TRY', 1], AE: ['United Arab Emirates', 'AED', 1],
  SA: ['Saudi Arabia', 'SAR', 1], SG: ['Singapore', 'SGD', 1], MY: ['Malaysia', 'MYR', 1], PH: ['Philippines', 'PHP', 1, 'mdy'], ID: ['Indonesia', 'IDR', 1],
  TH: ['Thailand', 'THB', 1], VN: ['Vietnam', 'VND', 1], JP: ['Japan', 'JPY', 1], KR: ['South Korea', 'KRW', 1], CN: ['China', 'CNY', 1],
  HK: ['Hong Kong', 'HKD', 4], PK: ['Pakistan', 'PKR', 7], BD: ['Bangladesh', 'BDT', 7], LK: ['Sri Lanka', 'LKR', 4], NG: ['Nigeria', 'NGN', 1],
  KE: ['Kenya', 'KES', 1], ZA: ['South Africa', 'ZAR', 3], EG: ['Egypt', 'EGP', 1], BR: ['Brazil', 'BRL', 1], MX: ['Mexico', 'MXN', 1],
  OTHER: ['Somewhere else', 'USD', 1]
};
const countryInfo = code => { const c = COUNTRIES[code] || COUNTRIES.OTHER; return { code: COUNTRIES[code] ? code : 'OTHER', name: c[0], currency: c[1], fy: c[2], dates: c[3] || 'dmy' }; };
const TZ_COUNTRY = {
  'Asia/Kolkata': 'IN', 'Asia/Calcutta': 'IN', 'Europe/London': 'GB', 'Europe/Dublin': 'IE', 'Europe/Berlin': 'DE', 'Europe/Paris': 'FR', 'Europe/Madrid': 'ES',
  'Europe/Rome': 'IT', 'Europe/Amsterdam': 'NL', 'Europe/Zurich': 'CH', 'Europe/Stockholm': 'SE', 'Europe/Oslo': 'NO', 'Europe/Copenhagen': 'DK', 'Europe/Warsaw': 'PL',
  'Europe/Istanbul': 'TR', 'Asia/Dubai': 'AE', 'Asia/Riyadh': 'SA', 'Asia/Singapore': 'SG', 'Asia/Kuala_Lumpur': 'MY', 'Asia/Manila': 'PH', 'Asia/Jakarta': 'ID',
  'Asia/Bangkok': 'TH', 'Asia/Ho_Chi_Minh': 'VN', 'Asia/Saigon': 'VN', 'Asia/Tokyo': 'JP', 'Asia/Seoul': 'KR', 'Asia/Shanghai': 'CN', 'Asia/Hong_Kong': 'HK',
  'Asia/Karachi': 'PK', 'Asia/Dhaka': 'BD', 'Asia/Colombo': 'LK', 'Africa/Lagos': 'NG', 'Africa/Nairobi': 'KE', 'Africa/Johannesburg': 'ZA', 'Africa/Cairo': 'EG',
  'America/Sao_Paulo': 'BR', 'America/Mexico_City': 'MX', 'Pacific/Auckland': 'NZ', 'Pacific/Honolulu': 'US'
};
/** Best guess at the user's country: time zone first (where they are), then browser language. */
function detectCountry() {
  let tz = '';
  try { tz = Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch (e) { /* ignore */ }
  if (TZ_COUNTRY[tz]) return TZ_COUNTRY[tz];
  if (/^Australia\//.test(tz)) return 'AU';
  if (/^America\/(Toronto|Vancouver|Edmonton|Winnipeg|Halifax|St_Johns|Regina|Montreal)$/.test(tz)) return 'CA';
  if (/^America\/(New_York|Chicago|Denver|Los_Angeles|Phoenix|Anchorage|Detroit|Boise|Indiana\/.+|Kentucky\/.+)$/.test(tz)) return 'US';
  const langs = [].concat(navigator.languages || [], navigator.language || []);
  for (const l of langs) { const m = /[-_]([A-Za-z]{2})$/.exec(l); if (m && COUNTRIES[m[1].toUpperCase()]) return m[1].toUpperCase(); }
  return 'OTHER';
}
/** Existing data from before countries existed: guess the country from the currency. */
function countryFromCurrency(cur) {
  if (cur === 'USD') return 'US';
  if (cur === 'EUR') { const c = detectCountry(); return countryInfo(c).currency === 'EUR' ? c : 'IE'; }
  const hit = Object.keys(COUNTRIES).find(k => COUNTRIES[k][1] === cur);
  return hit || detectCountry();
}
/** Rough "same lifestyle" factor from rupees, used only to size sample data and defaults. */
const SAMPLE_SCALE = { INR: 1, USD: 0.05, EUR: 0.045, GBP: 0.04, CAD: 0.065, AUD: 0.07, NZD: 0.07, SGD: 0.065, AED: 0.15, SAR: 0.15, JPY: 6, CNY: 0.25,
  KRW: 50, HKD: 0.35, CHF: 0.05, SEK: 0.45, NOK: 0.45, DKK: 0.3, PLN: 0.12, TRY: 1.2, BRL: 0.1, MXN: 0.3, ZAR: 0.25, NGN: 5, KES: 1.2, PKR: 1.5,
  BDT: 0.8, LKR: 1.5, EGP: 0.5, PHP: 0.6, MYR: 0.1, IDR: 150, THB: 0.5, VND: 350 };
const scaleFor = cur => SAMPLE_SCALE[cur] || 0.05;
/** Two significant figures: 4,250 → 4,300; 32.45 → 32. */
function niceAmount(v) {
  if (!(v > 0)) return 0;
  const p = Math.pow(10, Math.max(0, Math.floor(Math.log10(v)) - 1));
  return Math.round(v / p) * p;
}
const ROUND_TO = [1, 5, 10, 50, 100, 500, 1000];
const roundUpFor = cur => (cur === 'INR' ? 100 : ROUND_TO.reduce((best, v) => (Math.abs(Math.log(v / (20 * scaleFor(cur)))) < Math.abs(Math.log(best / (20 * scaleFor(cur)))) ? v : best), 1));
/** Common personal tax dates for a few countries. Everyone should double-check them each year. */
function taxDeadlinePresets(country) {
  const P = {
    IN: [['Advance tax, 1st instalment (15%)', 6, 15], ['Advance tax, 2nd instalment (45%)', 9, 15], ['Advance tax, 3rd instalment (75%)', 12, 15], ['Advance tax, last instalment (100%)', 3, 15], ['Income tax return filing', 7, 31]],
    US: [['Tax Day: file your return and pay', 4, 15], ['Estimated tax: 2nd payment', 6, 15], ['Estimated tax: 3rd payment', 9, 15], ['Estimated tax: 4th payment', 1, 15]],
    GB: [['Self Assessment: file online and pay', 1, 31], ['Second payment on account', 7, 31], ['Register for Self Assessment (if you’re new)', 10, 5]],
    CA: [['File your tax return and pay', 4, 30], ['Self-employed filing deadline', 6, 15], ['Tax instalment', 3, 15], ['Tax instalment', 6, 15], ['Tax instalment', 9, 15], ['Tax instalment', 12, 15]],
    AU: [['Tax return due (if you lodge it yourself)', 10, 31]]
  }[country];
  if (!P) return null;
  const y = todayDate().getFullYear();
  return P.map(([title, m, d]) => ({ id: uid(), title, date: F.toISO(new Date(y, m - 1, d)), repeat: true }));
}
const TAX_TYPES = ['Withheld from pay', 'Advance / estimated tax', 'Tax return payment', 'Payroll tax (NI, Social Security, PT…)', 'Sales tax / VAT / GST', 'Property tax', 'Other'];
const LEGACY_TAX = { 'TDS (salary)': 'Withheld from pay', 'Advance tax': 'Advance / estimated tax', 'Self-assessment tax': 'Tax return payment', 'GST': 'Sales tax / VAT / GST', 'Professional tax': 'Payroll tax (NI, Social Security, PT…)' };
const PAYROLL_TAX = TAX_TYPES[3];

/* ---------- Small utilities ---------- */
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const sum = (arr, fn) => arr.reduce((s, x) => s + (fn ? fn(x) : x), 0);
const nn = v => { const n = Number(v); return Number.isFinite(n) && n >= 0 ? n : 0; };
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const r2 = v => Number.isFinite(v) ? Math.round(v * 100) / 100 : '';
const todayDate = () => F.startOfDay(new Date());
const todayISO = () => F.toISO(todayDate());
/** Number for an input's value attribute (rounded for display only). */
const numStr = v => (v === null || v === undefined || !Number.isFinite(v)) ? '' : String(Math.round(v * 100) / 100);

/** Parse user text like "1,25,000" or "12.5". null = empty, NaN = not a number. */
const COMMA_DECIMAL = new Set(['DE', 'FR', 'ES', 'IT', 'NL', 'SE', 'DK', 'NO', 'PL', 'BR', 'TR', 'ID', 'VN', 'ZA']);
/** Read a typed amount. Takes "1,00,000", "₹500", "500/-", "12,50" and "1.000,50" (comma decimals). */
function parseNum(raw) {
  let s = String(raw ?? '').trim();
  if (s === '') return null;
  const CUR = /^(rs\.?|inr|usd|eur|gbp|aud|cad|nzd|sgd|aed|sar|chf|sek|nok|dkk|pln|brl|zar|jpy|cny)\s*/i;
  s = s.replace(CUR, '').replace(/\s*(rs\.?|inr|usd|eur|gbp|aud|cad|nzd|sgd|aed|sar|chf|sek|nok|dkk|pln|brl|zar|jpy|cny)$/i, '').replace(/\/-$/, '');
  s = s.replace(/[\p{Sc}\s_'’]/gu, '').replace(/^[−–]/, '-');
  const neg = s[0] === '-'; if (neg) s = s.slice(1);
  if (!/^[\d.,]+$/.test(s) || !/\d/.test(s) || /[.,]{2}/.test(s)) return NaN;
  const lc = s.lastIndexOf(','), ld = s.lastIndexOf('.');
  const commaDec = typeof state !== 'undefined' && state && state.settings && COMMA_DECIMAL.has(state.settings.country);
  let dec = null;
  if (lc >= 0 && ld >= 0) dec = lc > ld ? ',' : '.';
  else if (lc >= 0) dec = s.split(',').length === 2 && (lc === 0 || commaDec || s.length - lc - 1 !== 3) ? ',' : null;
  else if (ld >= 0) dec = s.split('.').length === 2 && (ld === 0 || !commaDec || s.length - ld - 1 !== 3) ? '.' : null;
  let int = s, frac = '';
  if (dec) { const i = s.lastIndexOf(dec); int = s.slice(0, i); frac = s.slice(i + 1); }
  if (/[.,]/.test(frac)) return NaN;
  const out = Number((int.replace(/[.,]/g, '') || '0') + (frac ? '.' + frac : ''));
  return neg ? -out : out;
}

/* ---------- Formatting (display only) ---------- */
const fmtCache = {};
function getFmt(digits, compact) {
  const code = state.currency;
  const key = code + digits + (compact ? 'c' : '');
  if (!fmtCache[key]) {
    const opts = { style: 'currency', currency: code, minimumFractionDigits: 0, maximumFractionDigits: digits };
    if (compact) opts.notation = 'compact'; else opts.minimumFractionDigits = digits;
    fmtCache[key] = new Intl.NumberFormat(CURRENCIES[code].locale, opts);
  }
  return fmtCache[key];
}
/** Whole units by default; paise/cents only for small non-round amounts. */
function fmt(v) {
  if (!Number.isFinite(v)) return '-';
  if (Math.abs(v) < 0.005) v = 0;
  const small = Math.abs(v) < 100 && Math.abs(v - Math.round(v)) > 0.004;
  return getFmt(NO_DECIMALS.has(state.currency) || !small ? 0 : 2).format(v);
}
function fmtExact(v) {
  if (!Number.isFinite(v)) return '-';
  if (Math.abs(v) < 0.005) v = 0;
  return getFmt(NO_DECIMALS.has(state.currency) ? 0 : 2).format(v);
}
function fmtCompact(v) {
  if (!Number.isFinite(v)) return '-';
  const s = getFmt(1, true).format(v);
  return CURRENCIES[state.currency].locale === 'en-IN' ? s.replace(/(\d)\s?T$/, '$1K') : s;   // en-IN writes thousands as “T”, which reads as trillions
}
function fmtPct(p) {
  if (!Number.isFinite(p)) return '-';
  const a = Math.abs(p);
  return (a > 0 && a < 10 ? p.toFixed(1).replace(/\.0$/, '') : String(Math.round(p))) + '%';
}
/** Interest rates keep their decimals (10.5%, not 11%). */
function fmtRate(p) { return Number.isFinite(p) ? `${Math.round(p * 100) / 100}%` : '-'; }
const fmtDate = d => d ? `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}` : '-';
const fmtMonthYear = d => d ? `${MONTHS[d.getMonth()]} ${d.getFullYear()}` : '-';
const fmtMonthShort = d => `${MONTHS[d.getMonth()]} '${String(d.getFullYear()).slice(2)}`;
function monthsLabel(n) {
  if (!Number.isFinite(n)) return '-';
  if (n <= 0) return 'now';
  const y = Math.floor(n / 12), m = n % 12;
  if (y === 0) return `${m} month${m === 1 ? '' : 's'}`;
  return `${y} yr${y === 1 ? '' : 's'}${m ? ` ${m} mo` : ''}`;
}
function daysLabel(days) {
  if (days === 0) return 'Today';
  if (days === 1) return 'Tomorrow';
  if (days < 0) return `${-days} days ago`;
  return `in ${days} days`;
}

