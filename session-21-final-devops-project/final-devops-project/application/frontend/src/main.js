// Kirana ledger UI: talks to the backend through same-origin /api (nginx / Ingress route it).
const $ = (id) => document.getElementById(id);
const rupee = (n) => "₹" + Number(n).toLocaleString("en-IN");

async function api(path, options = {}) {
  const headers = { "Content-Type": "application/json", ...(options.headers || {}) };
  const key = $("apikey").value || localStorage.getItem("kirana-api-key") || "";
  if (key) headers["X-API-Key"] = key;
  const res = await fetch(path, { ...options, headers });
  if (!res.ok && res.status !== 204) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.detail ? JSON.stringify(body.detail) : res.statusText);
  }
  return res.status === 204 ? null : res.json();
}

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  Object.entries(attrs).forEach(([k, v]) => (k === "onclick" ? (node.onclick = v) : node.setAttribute(k, v)));
  children.forEach((c) => node.append(c));
  return node;
}

async function loadInfo() {
  const info = await api("/api/info");
  $("shop").textContent = info.shop;
  $("version").textContent = (/^\d/.test(info.version) ? "v" : "") + info.version.slice(0, 12);
  document.title = info.shop;
}

async function loadBalances() {
  const list = $("balances");
  list.replaceChildren();
  const rows = await api("/api/customers");
  if (!rows.length) list.append(el("li", { class: "empty" }, "Sab hisaab barabar — nobody owes anything."));
  rows.forEach((r) => {
    const copy = el("button", { class: "secondary", onclick: async () => {
      await navigator.clipboard.writeText(r.reminder).catch(() => {});
      copy.textContent = "Copied ✓";
    } }, "Copy WhatsApp reminder");
    list.append(el("li", {}, el("span", {}, r.customer), el("span", { class: "amt udhar" }, rupee(r.balance)), copy));
  });
}

async function loadEntries() {
  const list = $("entries");
  list.replaceChildren();
  const rows = await api("/api/entries");
  if (!rows.length) list.append(el("li", { class: "empty" }, "No entries yet."));
  rows.forEach((e) => {
    const edit = el("button", { class: "secondary", onclick: () => editEntry(e) }, "Edit");
    const del = el("button", { class: "danger", onclick: () => removeEntry(e.id) }, "Delete");
    list.append(el("li", {},
      el("span", {}, `${e.customer}`, el("br"), el("span", { class: "muted" }, `${e.type}${e.note ? " · " + e.note : ""}`)),
      el("span", { class: `amt ${e.type}` }, rupee(e.amount)), edit, del));
  });
}

async function refresh() {
  try {
    await Promise.all([loadInfo(), loadBalances(), loadEntries()]);
  } catch (err) {
    $("form-msg").textContent = "Cannot reach the API: " + err.message;
  }
}

async function editEntry(e) {
  const amount = prompt(`New amount for ${e.customer} (${e.type})`, e.amount);
  if (amount === null) return;
  try {
    await api(`/api/entries/${e.id}`, { method: "PUT",
      body: JSON.stringify({ customer: e.customer, amount: Number(amount), type: e.type, note: e.note }) });
    refresh();
  } catch (err) { $("form-msg").textContent = "Update failed: " + err.message; }
}

async function removeEntry(id) {
  if (!confirm("Delete this entry?")) return;
  try { await api(`/api/entries/${id}`, { method: "DELETE" }); refresh(); }
  catch (err) { $("form-msg").textContent = "Delete failed: " + err.message; }
}

$("entry-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const body = {
    customer: $("customer").value,
    amount: Number($("amount").value),
    type: document.querySelector('input[name="type"]:checked').value,
    note: $("note").value,
  };
  try {
    const saved = await api("/api/entries", { method: "POST", body: JSON.stringify(body) });
    if ($("apikey").value) localStorage.setItem("kirana-api-key", $("apikey").value);
    $("form-msg").textContent = `${saved.customer} ${rupee(saved.amount)} ${saved.type} — saved ✓`;
    $("entry-form").reset();
    refresh();
  } catch (err) {
    $("form-msg").textContent = "Not saved: " + err.message;
  }
});

refresh();
