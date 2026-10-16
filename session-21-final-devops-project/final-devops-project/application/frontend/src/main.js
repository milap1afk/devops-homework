// Kirana Ledger UI: talks to the backend through same-origin /api (nginx in Compose, the Ingress in Kubernetes).

const $ = (id) => document.getElementById(id);
const rupee = (n) => "₹" + Number(n).toLocaleString("en-IN", { maximumFractionDigits: 2 });
const TYPE_LABEL = { udhar: "उधार Udhar", payment: "वापस Payment", sale: "बिक्री Sale" };
const VIEWS = { dashboard: "Dashboard", ledger: "Ledger", customers: "Customers", settings: "Settings" };
const KEY_STORE = "kirana-api-key";

const state = { type: "", q: "", editing: null, info: null };

// ------------------------------------------------------------------ helpers
function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else if (v !== false && v != null) node.setAttribute(k, v === true ? "" : v);
  }
  node.append(...children.filter((c) => c != null));
  return node;
}

function storedKey() {
  try { return localStorage.getItem(KEY_STORE) || ""; } catch { return ""; }
}

async function api(path, options = {}) {
  const headers = { "Content-Type": "application/json", ...(options.headers || {}) };
  const key = storedKey();
  if (key) headers["X-API-Key"] = key;
  const res = await fetch(path, { ...options, headers });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    const err = new Error(res.status === 401 ? "API key missing or wrong — set it in Settings"
      : Array.isArray(body.detail) ? body.detail.map((d) => d.msg).join(", ") : body.detail || res.statusText);
    err.status = res.status;
    throw err;
  }
  return res.status === 204 ? null : res.json();
}

function toast(message, kind = "ok") {
  const t = el("div", { class: `toast ${kind}` }, message);
  $("toasts").append(t);
  setTimeout(() => t.classList.add("out"), 2600);
  setTimeout(() => t.remove(), 3000);
}

function initials(name) {
  return name.split(/\s+/).map((p) => p[0]).join("").slice(0, 2).toUpperCase();
}

function avatar(name) {
  let h = 0;
  for (const c of name) h = (h * 31 + c.charCodeAt(0)) % 360;
  return el("span", { class: "avatar", style: `--h:${h}` }, initials(name));
}

function when(iso) {
  const d = new Date(iso);
  const mins = Math.round((Date.now() - d) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} min ago`;
  if (mins < 24 * 60 && d.getDate() === new Date().getDate()) return `${Math.round(mins / 60)} h ago`;
  return d.toLocaleString("en-IN", { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });
}

const badge = (type) => el("span", { class: `badge ${type}` }, TYPE_LABEL[type]);
const signed = (e) => (e.type === "payment" ? "− " : e.type === "udhar" ? "+ " : "") + rupee(e.amount);

function whatsappLink(text) {
  return "https://wa.me/?text=" + encodeURIComponent(text);
}

function empty(message) {
  return el("li", { class: "empty" }, message);
}

// ------------------------------------------------------------------ dashboard
function renderChart(days) {
  const W = 640, H = 240, pad = { l: 44, r: 8, t: 12, b: 28 };
  const max = Math.max(100, ...days.flatMap((d) => [d.udhar, d.payment, d.sale]));
  const step = Math.pow(10, Math.floor(Math.log10(max)));
  const top = Math.ceil(max / step) * step;
  const y = (v) => pad.t + (H - pad.t - pad.b) * (1 - v / top);
  const groupW = (W - pad.l - pad.r) / days.length;
  const barW = Math.min(18, groupW / 4);
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", `0 0 ${W} ${H}`);
  const add = (tag, attrs, text) => {
    const n = document.createElementNS(ns, tag);
    Object.entries(attrs).forEach(([k, v]) => n.setAttribute(k, v));
    if (text != null) n.textContent = text;
    svg.append(n);
    return n;
  };
  for (let i = 0; i <= 4; i++) {
    const v = (top / 4) * i;
    add("line", { x1: pad.l, x2: W - pad.r, y1: y(v), y2: y(v), class: "grid" });
    add("text", { x: pad.l - 6, y: y(v) + 4, class: "axis", "text-anchor": "end" },
      v >= 1000 ? `${v / 1000}k` : v);
  }
  days.forEach((d, i) => {
    const x0 = pad.l + groupW * i + (groupW - barW * 3 - 4) / 2;
    ["udhar", "payment", "sale"].forEach((k, j) => {
      const h = Math.max(d[k] ? 2 : 0, y(0) - y(d[k]));
      const r = add("rect", { x: x0 + j * (barW + 2), y: y(0) - h, width: barW, height: h, rx: 3, class: `bar ${k}` });
      const t = document.createElementNS(ns, "title");
      t.textContent = `${d.date} · ${k}: ${rupee(d[k])}`;
      r.append(t);
    });
    const label = new Date(d.date + "T00:00:00").toLocaleDateString("en-IN", { weekday: "short", day: "numeric" });
    add("text", { x: pad.l + groupW * i + groupW / 2, y: H - 8, class: "axis", "text-anchor": "middle" },
      i === days.length - 1 ? "Today" : label);
  });
  $("chart").replaceChildren(svg);
}

async function loadDashboard() {
  const [s, dues, recent] = await Promise.all([api("/api/stats"), api("/api/customers"), api("/api/entries?limit=8")]);
  $("k-outstanding").textContent = rupee(s.outstanding);
  $("k-dues").textContent = `${s.customers_with_dues} of ${s.customers_total} customers owe`;
  $("k-udhar").textContent = rupee(s.today.udhar);
  $("k-count").textContent = `${s.today.count} entries today`;
  $("k-payment").textContent = rupee(s.today.payment);
  $("k-rate").textContent = `${s.collection_rate}% of all credit collected`;
  $("k-sale").textContent = rupee(s.today.sale);
  $("k-customers").textContent = `${s.entries_total} entries in the ledger`;
  renderChart(s.days);

  const top = $("top-dues");
  const biggest = dues[0]?.balance || 1;
  top.replaceChildren(...(dues.length ? dues.slice(0, 5).map((c) => el("li", { class: "due" },
    avatar(c.customer),
    el("div", { class: "grow" },
      el("div", { class: "due-line" }, el("strong", {}, c.customer), el("span", { class: "amt udhar" }, rupee(c.balance))),
      el("div", { class: "bar-track" }, el("div", { class: "bar-fill", style: `width:${(c.balance / biggest) * 100}%` }))),
    el("a", { class: "icon-btn wa", href: whatsappLink(c.reminder), target: "_blank", rel: "noopener",
      title: `Send reminder: ${c.reminder}` }, "💬"),
  )) : [empty("Sab hisaab barabar — nobody owes anything.")]));

  $("activity").replaceChildren(...(recent.length ? recent.map(feedItem) : [empty("No entries yet. Add the first one!")]));
}

function feedItem(e) {
  return el("li", {},
    el("span", { class: `pip ${e.type}` }),
    el("div", { class: "grow" },
      el("div", {}, el("strong", {}, e.customer), " ", badge(e.type)),
      el("small", { class: "muted" }, when(e.created_at) + (e.note ? ` · ${e.note}` : ""))),
    el("span", { class: `amt ${e.type}` }, signed(e)));
}

// ------------------------------------------------------------------ ledger
async function loadLedger() {
  const params = new URLSearchParams({ limit: "500" });
  if (state.type) params.set("type", state.type);
  if (state.q) params.set("q", state.q);
  const rows = await api(`/api/entries?${params}`);
  $("ledger-count").textContent = `${rows.length} ${rows.length === 1 ? "entry" : "entries"}`;
  $("ledger-rows").replaceChildren(...(rows.length ? rows.map((e) => el("tr", {},
    el("td", { class: "muted nowrap" }, when(e.created_at)),
    el("td", {}, el("span", { class: "who" }, avatar(e.customer), e.customer)),
    el("td", {}, badge(e.type)),
    el("td", { class: "muted hide-sm" }, e.note || "—"),
    el("td", { class: `num amt ${e.type}` }, rupee(e.amount)),
    el("td", { class: "actions" },
      el("button", { class: "icon-btn", title: "Edit", onclick: () => openEntry(e) }, "✎"),
      el("button", { class: "icon-btn danger", title: "Delete", onclick: () => removeEntry(e) }, "🗑")),
  )) : [el("tr", {}, el("td", { colspan: 6, class: "empty" }, "No entries match."))]));
}

// ------------------------------------------------------------------ customers
async function loadCustomers() {
  let rows = await api("/api/customers");
  if (state.q) rows = rows.filter((c) => c.customer.toLowerCase().includes(state.q.toLowerCase()));
  const biggest = rows[0]?.balance || 1;
  $("cust-grid").replaceChildren(...(rows.length ? rows.map((c) => el("article", { class: "card cust" },
    el("div", { class: "cust-head" }, avatar(c.customer),
      el("div", {}, el("strong", {}, c.customer), el("small", { class: "muted" }, "बाकी"))),
    el("div", { class: "cust-amt udhar" }, rupee(c.balance)),
    el("div", { class: "bar-track" }, el("div", { class: "bar-fill", style: `width:${(c.balance / biggest) * 100}%` })),
    el("p", { class: "reminder" }, `“${c.reminder}”`),
    el("div", { class: "row" },
      el("a", { class: "btn wa", href: whatsappLink(c.reminder), target: "_blank", rel: "noopener" }, "💬 WhatsApp"),
      el("button", { class: "btn ghost", onclick: async () => {
        await navigator.clipboard?.writeText(c.reminder).catch(() => {});
        toast("Reminder copied");
      } }, "Copy"),
      el("button", { class: "btn ghost", onclick: () => openHistory(c.customer) }, "History")),
  )) : [el("p", { class: "empty card" }, state.q ? "No customer matches." : "Sab hisaab barabar — nobody owes anything.")]));
}

async function openHistory(name) {
  const rows = (await api(`/api/entries?customer=${encodeURIComponent(name)}&limit=1000`)).reverse();
  let running = 0;
  const items = rows.map((e) => {
    running += e.type === "udhar" ? e.amount : e.type === "payment" ? -e.amount : 0;
    const li = feedItem(e);
    li.append(el("small", { class: "running muted" }, `bal ${rupee(running)}`));
    return li;
  }).reverse();
  $("history-title").textContent = name;
  $("history-summary").replaceChildren(
    el("div", {}, el("small", { class: "muted" }, "Balance"), el("strong", { class: "udhar" }, rupee(running))),
    el("div", {}, el("small", { class: "muted" }, "Entries"), el("strong", {}, String(rows.length))),
    el("button", { class: "btn primary", onclick: () => { $("history-dialog").close(); openEntry(null, name); } }, "＋ Entry"));
  $("history-rows").replaceChildren(...(items.length ? items : [empty("No entries.")]));
  $("history-dialog").showModal();
}

// ------------------------------------------------------------------ settings
function loadSettings() {
  $("apikey").value = storedKey();
  const i = state.info || {};
  const facts = [["Shop", i.shop], ["Version", i.version], ["API", "same origin /api (Ingress → FastAPI)"],
    ["Browser time", new Date().toLocaleString("en-IN")]];
  $("facts").replaceChildren(...facts.flatMap(([k, v]) => [el("dt", {}, k), el("dd", {}, v ?? "—")]));
}

// ------------------------------------------------------------------ entry dialog
const QUICK = [50, 100, 200, 500, 1000, 2000];

function currentType() {
  return document.querySelector('input[name="type"]:checked').value;
}

function updateConfirm() {
  const name = $("customer").value.trim();
  const amount = Number($("amount").value);
  $("confirm-line").textContent = name && amount > 0
    ? `${name} ${rupee(amount)} ${currentType()} — sahi hai?` : "";
}

async function openEntry(entry = null, presetName = "") {
  state.editing = entry;
  $("entry-form").reset();
  $("dialog-title").textContent = entry ? `Edit entry #${entry.id}` : "New entry";
  $("save").textContent = entry ? "Save changes" : "Save entry";
  if (entry) {
    $("customer").value = entry.customer;
    $("amount").value = entry.amount;
    $("note").value = entry.note;
    document.querySelector(`input[name="type"][value="${entry.type}"]`).checked = true;
  } else if (presetName) {
    $("customer").value = presetName;
  }
  updateConfirm();
  api("/api/entries?limit=1000").then((rows) => {
    const names = [...new Set(rows.map((r) => r.customer))].sort();
    $("customer-list").replaceChildren(...names.map((n) => el("option", { value: n })));
  }).catch(() => {});
  $("entry-dialog").showModal();
  (presetName ? $("amount") : $("customer")).focus();
}

async function saveEntry(ev) {
  ev.preventDefault();
  const body = { customer: $("customer").value, amount: Number($("amount").value), type: currentType(), note: $("note").value };
  const btn = $("save");
  btn.disabled = true;
  try {
    const saved = state.editing
      ? await api(`/api/entries/${state.editing.id}`, { method: "PUT", body: JSON.stringify(body) })
      : await api("/api/entries", { method: "POST", body: JSON.stringify(body) });
    $("entry-dialog").close();
    toast(`${saved.customer} ${rupee(saved.amount)} ${saved.type} — saved ✓`);
    refresh();
  } catch (err) {
    toast(err.message, "err");
    if (err.status === 401) { $("entry-dialog").close(); location.hash = "#settings"; }
  } finally {
    btn.disabled = false;
  }
}

async function removeEntry(e) {
  if (!confirm(`Delete ${e.customer} ${rupee(e.amount)} ${e.type}?`)) return;
  try {
    await api(`/api/entries/${e.id}`, { method: "DELETE" });
    toast("Entry deleted");
    refresh();
  } catch (err) {
    toast(err.message, "err");
    if (err.status === 401) location.hash = "#settings";
  }
}

// ------------------------------------------------------------------ routing + boot
function currentView() {
  const v = location.hash.slice(1);
  return VIEWS[v] ? v : "dashboard";
}

async function refresh() {
  const view = currentView();
  try {
    const info = await api("/api/info");
    state.info = info;
    $("shop").textContent = info.shop;
    document.title = `${info.shop} · Kirana Ledger`;
    $("status").className = "status ok";
    $("status-text").textContent = `API online · ${/^[0-9a-f]{40}$/.test(info.version) ? info.version.slice(0, 7) : info.version}`;
    $("banner").hidden = true;
    if (view === "dashboard") await loadDashboard();
    if (view === "ledger") await loadLedger();
    if (view === "customers") await loadCustomers();
    if (view === "settings") loadSettings();
  } catch (err) {
    $("status").className = "status down";
    $("status-text").textContent = "API unreachable";
    $("banner").hidden = false;
    $("banner").textContent = `Cannot reach the API (${err.message}). Retrying…`;
    setTimeout(refresh, 5000);
  }
}

function route() {
  const view = currentView();
  for (const v of Object.keys(VIEWS)) $(`view-${v}`).hidden = v !== view;
  document.querySelectorAll(".nav a").forEach((a) => a.classList.toggle("active", a.dataset.view === view));
  $("title").textContent = VIEWS[view];
  $("search").hidden = !["ledger", "customers"].includes(view);
  refresh();
}

function boot() {
  $("today").textContent = new Date().toLocaleDateString("en-IN", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
  $("quick-amounts").replaceChildren(...QUICK.map((n) => el("button", { type: "button", class: "chip", onclick: () => {
    $("amount").value = n;
    updateConfirm();
  } }, rupee(n))));

  $("new-entry").addEventListener("click", () => openEntry());
  $("fab").addEventListener("click", () => openEntry());
  $("close-dialog").addEventListener("click", () => $("entry-dialog").close());
  $("close-history").addEventListener("click", () => $("history-dialog").close());
  $("entry-form").addEventListener("submit", saveEntry);
  $("entry-form").addEventListener("input", updateConfirm);

  $("type-filter").addEventListener("click", (ev) => {
    const chip = ev.target.closest(".chip");
    if (!chip) return;
    state.type = chip.dataset.type;
    document.querySelectorAll("#type-filter .chip").forEach((c) => c.classList.toggle("active", c === chip));
    loadLedger().catch((err) => toast(err.message, "err"));
  });

  let timer;
  $("search").addEventListener("input", (ev) => {
    clearTimeout(timer);
    timer = setTimeout(() => { state.q = ev.target.value.trim(); refresh(); }, 250);
  });

  $("key-form").addEventListener("submit", (ev) => {
    ev.preventDefault();
    try { localStorage.setItem(KEY_STORE, $("apikey").value.trim()); } catch { /* private mode */ }
    toast("API key saved in this browser");
  });
  $("clear-key").addEventListener("click", () => {
    try { localStorage.removeItem(KEY_STORE); } catch { /* private mode */ }
    $("apikey").value = "";
    toast("API key removed");
  });

  window.addEventListener("hashchange", route);
  setInterval(() => { if (currentView() === "dashboard" && !document.hidden) refresh(); }, 30000);
  route();
}

boot();
