/**
 * Staff panel and subscriber codes.
 * The DeltaSIB API password never enters D1 or the phone.
 * D1 stores code hashes, phone-session hashes, and — only until the first
 * redeem of a one-time code — the Winbox password sealed with AES-GCM.
 * Permanent codes never store a router password.
 */

import { lookupSubscriber } from "./sib-subscriber.js";

const CODE_TTL_MS = 24 * 60 * 60 * 1000;
const PERMANENT_EXPIRES_AT = Date.UTC(2099, 0, 1);
const SESSION_IDLE_MS = 365 * 24 * 60 * 60 * 1000;
const SESSION_TOUCH_MS = 24 * 60 * 60 * 1000;
const STAFF_TTL_MS = 12 * 60 * 60 * 1000;
const STAFF_COOKIE = "jb_staff";

export async function handleAdmin(request, env) {
  const url = new URL(request.url);
  if (!env.SIB_DB) return text("دیتابیس هنوز وصل نشده است.", 503);
  if (!env.SIB_ADMIN_PASSWORD) return text("رمز پنل روی ورکر تنظیم نشده است.", 503);

  if (url.pathname === "/jahanbit/admin/login" && request.method === "POST") {
    return staffLogin(request, env);
  }
  if (url.pathname === "/jahanbit/admin/logout") {
    return new Response(null, {
      status: 302,
      headers: {
        location: "/jahanbit/admin",
        "set-cookie": clearCookie(),
      },
    });
  }

  const staff = await readStaff(request, env);
  if (!staff) return html(loginPage(url.searchParams.get("e") === "1", env), 200);

  if (url.pathname === "/jahanbit/admin/api/codes" && request.method === "GET") {
    return listCodes(env, url);
  }
  if (url.pathname === "/jahanbit/admin/codes" && request.method === "POST") {
    return createCode(request, env);
  }
  if (request.method !== "GET" && request.method !== "HEAD") {
    return text("این درخواست مجاز نیست.", 405);
  }
  return html(panelShell(env), 200);
}

export async function handleRedeem(request, env) {
  if (request.method !== "POST") return json({ error: "POST required" }, 405);
  if (!env.SIB_DB) return json({ error: "database missing" }, 503);
  let body = {};
  try {
    body = await request.json();
  } catch (_) {
    body = {};
  }
  if (await tooManyAttempts(env, request)) {
    return json({ error: "چند لحظه بعد دوباره تلاش کنید." }, 429);
  }
  const username = String(body.username || "").trim();
  const secret = normalizeAccessCode(body.password || body.code);
  if (!secret || !isName(username)) {
    await noteAttempt(env, request);
    return json({ error: "نام کاربری یا رمز نادرست است." }, 400);
  }
  const now = Date.now();
  const hash = await sha256Hex(secret);
  const row = await env.SIB_DB.prepare(
    "SELECT username, expires_at, used_at, reusable, router_secret FROM access_codes WHERE code_hash = ?",
  )
    .bind(hash)
    .first();
  const reusable = row && Number(row.reusable) === 1;
  const usernameMatches =
    row && String(row.username).toLowerCase() === username.toLowerCase();
  if (!row || !usernameMatches || (!reusable && row.used_at) || Number(row.expires_at) < now) {
    await noteAttempt(env, request);
    return json({ error: "نام کاربری یا رمز نادرست است." }, 401);
  }
  let routerPassword = "";
  if (!reusable && row.router_secret) {
    try {
      routerPassword = await openSeal(env, row.router_secret);
    } catch (_) {
      return json({ error: "رمز روتر خوانده نشد. رمز ورود تازه بسازید." }, 502);
    }
  }
  if (!reusable) {
    const spent = await env.SIB_DB.prepare(
      "UPDATE access_codes SET used_at = ?, router_secret = NULL WHERE code_hash = ? AND used_at IS NULL",
    )
      .bind(now, hash)
      .run();
    if (!spent.meta || spent.meta.changes !== 1) {
      return json({ error: "نام کاربری یا رمز نادرست است." }, 401);
    }
  }
  const session = randomHex(32);
  await env.SIB_DB.prepare(
    "INSERT INTO phone_sessions (token_hash, username, created_at, expires_at, last_seen_at, code_hash) VALUES (?, ?, ?, ?, ?, ?)",
  )
    .bind(await sha256Hex(session), row.username, now, PERMANENT_EXPIRES_AT, now, hash)
    .run();
  const payload = { username: row.username, session };
  if (routerPassword) payload.routerPassword = routerPassword;
  return json(payload);
}

export async function usernameForSession(env, session) {
  const token = String(session || "").trim();
  if (!env.SIB_DB || token.length < 32) return "";
  const hash = await sha256Hex(token);
  const row = await env.SIB_DB.prepare(
    "SELECT username, created_at, last_seen_at FROM phone_sessions WHERE token_hash = ?",
  )
    .bind(hash)
    .first();
  if (!row) return "";
  const now = Date.now();
  const seen = Number(row.last_seen_at || row.created_at || 0);
  if (!seen || now - seen > SESSION_IDLE_MS) {
    await env.SIB_DB.prepare("DELETE FROM phone_sessions WHERE token_hash = ?")
      .bind(hash)
      .run();
    return "";
  }
  if (now - seen > SESSION_TOUCH_MS) {
    await env.SIB_DB.prepare(
      "UPDATE phone_sessions SET last_seen_at = ? WHERE token_hash = ?",
    )
      .bind(now, hash)
      .run();
  }
  return String(row.username || "");
}

export async function handleLogout(request, env) {
  if (request.method !== "POST") return json({ error: "POST required" }, 405);
  if (!env.SIB_DB) return json({ ok: true });
  let body = {};
  try {
    body = await request.json();
  } catch (_) {
    body = {};
  }
  const token = String(body.session || "").trim();
  if (token.length < 32) return json({ ok: true });
  await env.SIB_DB.prepare("DELETE FROM phone_sessions WHERE token_hash = ?")
    .bind(await sha256Hex(token))
    .run();
  return json({ ok: true });
}

export async function handleDeleteAccount(request, env) {
  if (request.method !== "POST") return json({ error: "POST required" }, 405);
  if (!env.SIB_DB) return json({ ok: true });
  let body = {};
  try {
    body = await request.json();
  } catch (_) {
    body = {};
  }
  const token = String(body.session || "").trim();
  if (token.length < 32) return json({ ok: true });
  const hash = await sha256Hex(token);
  const row = await env.SIB_DB.prepare(
    "SELECT username FROM phone_sessions WHERE token_hash = ?",
  )
    .bind(hash)
    .first();
  const username = String(row?.username || "").trim();
  if (!username) {
    await env.SIB_DB.prepare("DELETE FROM phone_sessions WHERE token_hash = ?")
      .bind(hash)
      .run();
    return json({ ok: true });
  }
  await env.SIB_DB.batch([
    env.SIB_DB.prepare(
      "DELETE FROM phone_sessions WHERE LOWER(username) = LOWER(?)",
    ).bind(username),
    env.SIB_DB.prepare(
      "DELETE FROM access_codes WHERE LOWER(username) = LOWER(?)",
    ).bind(username),
  ]);
  return json({ ok: true });
}

async function staffLogin(request, env) {
  const form = await request.formData();
  const password = String(form.get("password") || "");
  const ok = await safeEqual(password, String(env.SIB_ADMIN_PASSWORD));
  if (!ok) {
    return new Response(null, {
      status: 302,
      headers: { location: "/jahanbit/admin?e=1" },
    });
  }
  const cookie = await signStaff(env, Date.now() + STAFF_TTL_MS);
  return new Response(null, {
    status: 302,
    headers: {
      location: "/jahanbit/admin",
      "set-cookie": `${STAFF_COOKIE}=${cookie}; HttpOnly; Secure; SameSite=Lax; Path=/jahanbit/admin; Max-Age=${STAFF_TTL_MS / 1000}`,
    },
  });
}

async function createCode(request, env) {
  const staff = await readStaff(request, env);
  if (!staff) return fail(request, "وارد پنل نشده‌اید.", 401);
  const form = await request.formData();
  const username = String(form.get("username") || "").trim();
  if (!isName(username)) return fail(request, "نام کاربری معتبر نیست.", 400);
  const reusable = form.get("reusable") === "1";
  const routerPassword = String(form.get("router_password") || "");
  if (!reusable && !routerPassword.trim()) {
    return fail(request, "برای کد یک‌بارمصرف، رمز Winbox همان مشترک لازم است.", 400);
  }
  if (routerPassword.length > 128) return fail(request, "رمز Winbox خیلی بلند است.", 400);
  const found = await lookupSubscriber(env, username);
  if (found.status === "not-found") return fail(request, "subscriber not found", 404);
  if (found.status !== "ok") {
    return fail(request, "DeltaSIB unreachable", found.status === "unconfigured" ? 503 : 502);
  }
  const code = randomAccessCode(10);
  const now = Date.now();
  const expiresAt = reusable ? PERMANENT_EXPIRES_AT : now + CODE_TTL_MS;
  const [secret, codeSealed, codeHash] = await Promise.all([
    reusable || !routerPassword ? Promise.resolve(null) : seal(env, routerPassword),
    seal(env, code),
    sha256Hex(code),
  ]);
  await env.SIB_DB.prepare(
    "INSERT INTO access_codes (code_hash, username, created_at, expires_at, used_at, reusable, router_secret, code_sealed) VALUES (?, ?, ?, ?, NULL, ?, ?, ?)",
  )
    .bind(
      codeHash,
      username,
      now,
      expiresAt,
      reusable ? 1 : 0,
      secret,
      codeSealed,
    )
    .run();
  const payload = {
    code,
    username,
    reusable,
    createdAt: now,
    expiresAt,
    router: secret ? "waiting" : "none",
  };
  if ((request.headers.get("accept") || "").includes("application/json")) {
    return json(payload);
  }
  return html(panelShell(env), 200);
}

const PAGE_SIZE = 12;

async function listCodes(env, url) {
  const page = Math.max(1, Number(url.searchParams.get("page")) || 1);
  const query = String(url.searchParams.get("q") || "").trim().slice(0, 64);
  const where = query ? " WHERE username LIKE ?" : "";
  const like = query ? `${query.replace(/[%_]/g, "")}%` : "";
  const countStmt = env.SIB_DB.prepare(`SELECT COUNT(*) AS n FROM access_codes${where}`);
  const rowsStmt = env.SIB_DB.prepare(
    `SELECT username, created_at, expires_at, used_at, reusable, code_sealed, CASE WHEN router_secret IS NULL OR router_secret = '' THEN 0 ELSE 1 END AS has_router FROM access_codes${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`,
  );
  const boundCount = query ? countStmt.bind(like) : countStmt;
  const boundRows = query
    ? rowsStmt.bind(like, PAGE_SIZE, (page - 1) * PAGE_SIZE)
    : rowsStmt.bind(PAGE_SIZE, (page - 1) * PAGE_SIZE);
  const [countResult, rowResult] = await env.SIB_DB.batch([boundCount, boundRows]);
  const total = Number(countResult.results?.[0]?.n || 0);
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const rows = await Promise.all(
    (rowResult.results || []).map(async (row) => {
      let code = "";
      if (row.code_sealed) {
        try {
          code = await openSeal(env, row.code_sealed);
        } catch (_) {
          code = "";
        }
      }
      const permanent = Number(row.reusable) === 1;
      const state = permanent
        ? "permanent"
        : row.used_at
          ? "used"
          : Number(row.expires_at) < Date.now()
            ? "expired"
            : "ready";
      return {
        username: row.username,
        code,
        createdAt: row.created_at,
        expiresAt: row.expires_at,
        usedAt: row.used_at,
        reusable: permanent,
        state,
        router: Number(row.has_router) === 1 ? "waiting" : "none",
      };
    }),
  );
  return json({ page, pages, total, rows });
}

function panelShell(env) {
  return layout(provinceTitle(env, "رمز ورود"), `
    <header>
      <div>
        <h1>${provinceTitle(env, "نام کاربری و رمز ورود")}</h1>
        <p class="hint" id="summary">در حال خواندن فهرست…</p>
      </div>
      <form method="post" action="/jahanbit/admin/logout"><button class="ghost" type="submit">خروج</button></form>
    </header>
    <form id="make" class="make">
      <label>نام کاربری<input name="username" required maxlength="64" autocomplete="off" dir="ltr" placeholder="jb.user"></label>
      <label>رمز Winbox<input name="router_password" type="password" maxlength="128" autocomplete="new-password" dir="ltr" placeholder="فقط برای رمز یک‌بارمصرف"></label>
      <label class="tick"><input type="checkbox" name="reusable" value="1"><span>همیشگی</span></label>
      <button id="makeBtn" type="submit">ساخت رمز ورود</button>
    </form>
    <p class="hint">نام کاربری و رمز ساخته‌شده را با هم به مشترک بدهید. رمز یک‌بارمصرف بعد از اولین ورود پاک می‌شود و رمز روتر را هم برمی‌دارد. رمز همیشگی رمز روتر نگه نمی‌دارد.</p>
    <section id="fresh" class="result" hidden>
      <p class="who" id="freshUser"></p>
      <div class="codeLine">
        <input id="freshCode" class="codeField big" readonly dir="ltr" spellcheck="false" autocomplete="off">
        <button type="button" id="freshCopy" class="ghost">کپی</button>
      </div>
    </section>
    <p id="formError" class="err" hidden></p>
    <div class="tools">
      <input id="find" dir="ltr" placeholder="جستجوی نام کاربری" autocomplete="off">
    </div>
    <div class="tableWrap">
      <table>
        <thead><tr><th>رمز ورود</th><th>نام کاربری</th><th>زمان</th><th>وضعیت</th><th></th></tr></thead>
        <tbody id="rows"></tbody>
      </table>
    </div>
    <div class="pager">
      <button class="ghost" id="prev" type="button">قبلی</button>
      <span id="pageLabel"></span>
      <button class="ghost" id="next" type="button">بعدی</button>
    </div>
    <script>${panelScript()}</script>
  `);
}

function panelScript() {
  return `
const state = { page: 1, q: "" };
const rowsEl = document.getElementById("rows");
const summary = document.getElementById("summary");
const pageLabel = document.getElementById("pageLabel");
const fresh = document.getElementById("fresh");
const freshUser = document.getElementById("freshUser");
const freshCode = document.getElementById("freshCode");
const formError = document.getElementById("formError");
const labels = { permanent: "همیشگی", used: "مصرف شد", expired: "منقضی", ready: "آماده" };
function text(value) { return document.createTextNode(value == null ? "" : String(value)); }
async function copyText(value, hint) {
  const code = String(value || "").replace(/\\s+/g, "");
  if (!code) return;
  try {
    await navigator.clipboard.writeText(code);
  } catch (_) {
    const area = document.createElement("textarea");
    area.value = code;
    area.setAttribute("readonly", "");
    document.body.appendChild(area);
    area.select();
    document.execCommand("copy");
    area.remove();
  }
  if (!hint) return;
  const previous = hint.textContent;
  hint.textContent = "کپی شد";
  setTimeout(() => { hint.textContent = previous; }, 1100);
}
function codeButton(value) {
  const line = document.createElement("div");
  line.className = "codeLine";
  const field = document.createElement("input");
  field.readOnly = true;
  field.className = "codeField";
  field.dir = "ltr";
  field.spellcheck = false;
  field.value = value || "";
  const hint = document.createElement("button");
  hint.type = "button";
  hint.className = "ghost";
  hint.textContent = value ? "کپی" : "—";
  hint.disabled = !value;
  if (value) hint.addEventListener("click", () => copyText(value, hint));
  line.appendChild(field);
  line.appendChild(hint);
  return line;
}
function cell(value) { const td = document.createElement("td"); td.appendChild(text(value)); return td; }
function when(ms) {
  if (!ms) return "—";
  const date = new Date(Number(ms));
  const two = (n) => String(n).padStart(2, "0");
  return date.getFullYear() + "-" + two(date.getMonth()+1) + "-" + two(date.getDate()) + " " + two(date.getHours()) + ":" + two(date.getMinutes());
}
async function load() {
  const url = "/jahanbit/admin/api/codes?page=" + state.page + "&q=" + encodeURIComponent(state.q);
  const response = await fetch(url, { headers: { accept: "application/json" } });
  const data = await response.json();
  state.page = data.page || 1;
  summary.textContent = (data.total || 0) + " کد";
  pageLabel.textContent = state.page + " / " + (data.pages || 1);
  document.getElementById("prev").disabled = state.page <= 1;
  document.getElementById("next").disabled = state.page >= (data.pages || 1);
  rowsEl.replaceChildren();
  if (!data.rows || !data.rows.length) {
    const tr = document.createElement("tr");
    const td = cell("کدی نیست");
    td.colSpan = 5;
    tr.appendChild(td);
    rowsEl.appendChild(tr);
    return;
  }
  for (const row of data.rows) {
    const tr = document.createElement("tr");
    const codeCell = document.createElement("td");
    codeCell.appendChild(codeButton(row.code));
    tr.appendChild(codeCell);
    tr.appendChild(cell(row.username));
    tr.appendChild(cell(when(row.createdAt)));
    const status = labels[row.state] || row.state;
    const router = row.router === "waiting" ? " · رمز منتظر ورود" : "";
    tr.appendChild(cell(status + router));
    const action = document.createElement("td");
    const button = document.createElement("button");
    button.type = "button";
    button.className = "ghost";
    button.appendChild(text("مشترک"));
    button.addEventListener("click", () => showSubscriber(tr, row.username, button));
    action.appendChild(button);
    tr.appendChild(action);
    rowsEl.appendChild(tr);
  }
}
async function showSubscriber(tr, username, button) {
  const next = tr.nextElementSibling;
  if (next && next.classList.contains("detail")) { next.remove(); return; }
  button.disabled = true;
  const detail = document.createElement("tr");
  detail.className = "detail";
  const td = document.createElement("td");
  td.colSpan = 5;
  td.appendChild(text("در حال خواندن…"));
  detail.appendChild(td);
  tr.after(detail);
  try {
    const response = await fetch("/jahanbit/admin/api/subscriber?username=" + encodeURIComponent(username), { headers: { accept: "application/json" } });
    const data = await response.json();
    td.replaceChildren();
    if (!response.ok) { td.appendChild(text(data.error || "خوانده نشد")); return; }
    const title = document.createElement("strong");
    title.appendChild(text(data.name || data.username));
    td.appendChild(title);
    const list = document.createElement("dl");
    const profile = data.profile || {};
    for (const key of Object.keys(profile)) {
      const dt = document.createElement("dt");
      dt.appendChild(text(key));
      const dd = document.createElement("dd");
      dd.appendChild(text(profile[key]));
      list.appendChild(dt);
      list.appendChild(dd);
    }
    td.appendChild(list);
  } catch (_) {
    td.replaceChildren(text("اتصال به دلتاسیب برقرار نشد"));
  } finally {
    button.disabled = false;
  }
}
document.getElementById("make").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  formError.hidden = true;
  const button = document.getElementById("makeBtn");
  button.disabled = true;
  try {
    const response = await fetch("/jahanbit/admin/codes", {
      method: "POST",
      headers: { accept: "application/json" },
      body: new FormData(form),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok || !data.code) throw new Error(data.error || "ساخته نشد");
    freshUser.textContent = data.username || "";
    freshCode.value = data.code;
    fresh.hidden = false;
    const freshCopy = document.getElementById("freshCopy");
    freshCopy.textContent = "کپی";
    freshCopy.onclick = () => copyText(data.code, freshCopy);
    form.reset();
    state.page = 1;
    await load();
  } catch (error) {
    formError.hidden = false;
    formError.textContent = error.message || "ساخته نشد";
  } finally {
    button.disabled = false;
  }
});
document.getElementById("prev").addEventListener("click", () => { state.page -= 1; load(); });
document.getElementById("next").addEventListener("click", () => { state.page += 1; load(); });
let findTimer = 0;
document.getElementById("find").addEventListener("input", (event) => {
  clearTimeout(findTimer);
  findTimer = setTimeout(() => { state.q = event.target.value.trim(); state.page = 1; load(); }, 180);
});
load();
`;
}

function provinceTitle(env, base) {
  const province = String(env?.PROVINCE_FA || "").trim();
  return province ? `${base} — ${province}` : base;
}

function loginPage(failed, env) {
  return layout(provinceTitle(env, "ورود پنل"), `
    <h1>${provinceTitle(env, "پنل کد جهان‌بیت")}</h1>
    ${failed ? "<p class='err'>رمز نادرست است.</p>" : ""}
    <form method="post" action="/jahanbit/admin/login">
      <label>رمز پنل</label>
      <input name="password" type="password" required autocomplete="current-password">
      <button type="submit">ورود</button>
    </form>
  `);
}

function layout(title, body) {
  return `<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<style>
body{margin:0;background:#f7f6f3;color:#1c1917;font:15px/1.5 Tahoma,sans-serif}
main{max-width:920px;margin:0 auto;padding:1.25rem}
header{display:flex;justify-content:space-between;align-items:center;gap:1rem}
h1{font-size:1.25rem;margin:0}
label{display:flex;flex-direction:column;gap:.3rem;font-size:.85rem}
input,button{font:inherit}
input{border:1px solid #e7e5e4;background:#fff;border-radius:10px;padding:.65rem .75rem}
button{border:0;border-radius:10px;padding:.7rem 1rem;background:#0f766e;color:#fff;cursor:pointer}
button.ghost{background:#fff;color:#1c1917;border:1px solid #e7e5e4}
button:disabled{opacity:.5}
.make{display:grid;grid-template-columns:1.2fr 1.2fr auto auto;gap:.6rem;align-items:end;margin-top:1rem}
.tick{flex-direction:row;align-items:center;padding-bottom:.7rem}
.hint{color:#78716c;font-size:.85rem}
.err{color:#be123c}
.result{margin:1rem 0;padding:1rem 1.1rem;background:#fff;border:1px solid #e7e5e4;border-radius:16px}
.who{margin:0 0 .45rem;color:#78716c}
.codeLine{display:flex;gap:.5rem;align-items:center}
.codeField{flex:1;min-width:8rem;border:1px solid #e7e5e4;background:#fff;border-radius:10px;padding:.55rem .7rem;letter-spacing:.08em;font-weight:700;font-family:ui-monospace,Consolas,monospace}
.codeField.big{font-size:1.35rem;padding:.8rem .9rem}
.tools{margin:.6rem 0}
.tools input{width:min(100%,16rem)}
.tableWrap{overflow:auto;background:#fff;border-radius:12px}
table{width:100%;border-collapse:collapse}
th,td{padding:.55rem .7rem;border-bottom:1px solid #f5f5f4;text-align:right;vertical-align:top}
.pager{display:flex;gap:.6rem;justify-content:center;align-items:center;margin:1rem 0}
dl{display:grid;grid-template-columns:max-content 1fr;gap:.25rem .8rem;margin:.4rem 0 0}
dt{color:#78716c}
@media(max-width:760px){.make{grid-template-columns:1fr}}
</style></head><body><main>${body}</main></body></html>`;
}

function fail(request, message, status) {
  if ((request.headers.get("accept") || "").includes("application/json")) {
    return json({ error: message }, status);
  }
  return text(message, status);
}

export function isStaff(request, env) {
  return readStaff(request, env);
}

async function readStaff(request, env) {
  const raw = cookieValue(request, STAFF_COOKIE);
  if (!raw || !raw.includes(".")) return false;
  const [payload, sig] = raw.split(".");
  const expected = await hmac(String(env.SIB_ADMIN_PASSWORD), payload);
  if (!(await safeEqual(sig, expected))) return false;
  let data;
  try {
    data = JSON.parse(atob(payload));
  } catch (_) {
    return false;
  }
  return data && Number(data.exp) > Date.now();
}

async function signStaff(env, exp) {
  const payload = btoa(JSON.stringify({ exp, role: "staff" }));
  const sig = await hmac(String(env.SIB_ADMIN_PASSWORD), payload);
  return `${payload}.${sig}`;
}

function cookieValue(request, name) {
  const header = request.headers.get("cookie") || "";
  for (const part of header.split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return rest.join("=");
  }
  return "";
}

function clearCookie() {
  return `${STAFF_COOKIE}=; HttpOnly; Secure; SameSite=Lax; Path=/jahanbit/admin; Max-Age=0`;
}

async function tooManyAttempts(env, request) {
  const ip = request.headers.get("cf-connecting-ip") || "0";
  const since = Date.now() - 10 * 60 * 1000;
  const row = await env.SIB_DB.prepare(
    "SELECT COUNT(*) AS n FROM redeem_attempts WHERE ip = ? AND at > ?",
  )
    .bind(ip, since)
    .first();
  return Number(row?.n || 0) >= 30;
}

async function noteAttempt(env, request) {
  const ip = request.headers.get("cf-connecting-ip") || "0";
  const now = Date.now();
  await env.SIB_DB.prepare("INSERT INTO redeem_attempts (ip, at) VALUES (?, ?)").bind(ip, now).run();
  await env.SIB_DB.prepare("DELETE FROM redeem_attempts WHERE at < ?").bind(now - 60 * 60 * 1000).run();
}

async function seal(env, plain) {
  const key = await aesKey(env);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(plain)),
  );
  const packed = new Uint8Array(iv.length + cipher.length);
  packed.set(iv, 0);
  packed.set(cipher, iv.length);
  return bytesToB64(packed);
}

async function openSeal(env, packed) {
  const raw = b64ToBytes(String(packed || ""));
  if (raw.length <= 12) return "";
  const key = await aesKey(env);
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: raw.slice(0, 12) },
    key,
    raw.slice(12),
  );
  return new TextDecoder().decode(plain);
}

async function aesKey(env) {
  const material = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`jahanbit-router-v1:${env.SIB_ADMIN_PASSWORD}`),
  );
  return crypto.subtle.importKey("raw", material, "AES-GCM", false, ["encrypt", "decrypt"]);
}

function bytesToB64(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function b64ToBytes(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function isName(value) {
  return /^[\p{L}\p{N}._@-]{1,64}$/u.test(value);
}

const ACCESS_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function normalizeAccessCode(value) {
  const code = String(value || "").replace(/\s+/g, "").toUpperCase();
  return /^[A-Z0-9]{10}$/.test(code) ? code : "";
}

function randomAccessCode(length) {
  const letters = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const bytes = new Uint8Array(length + 2);
  crypto.getRandomValues(bytes);
  const chars = [];
  for (let i = 0; i < length; i++) {
    chars.push(ACCESS_CODE_ALPHABET[bytes[i] % ACCESS_CODE_ALPHABET.length]);
  }
  if (!chars.some((char) => letters.includes(char))) {
    chars[bytes[length] % length] = letters[bytes[length + 1] % letters.length];
  }
  return chars.join("");
}

function randomHex(bytesLength) {
  const bytes = new Uint8Array(bytesLength);
  crypto.getRandomValues(bytes);
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function hmac(secret, value) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return [...new Uint8Array(sig)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function safeEqual(left, right) {
  const a = await sha256Hex(String(left));
  const b = await sha256Hex(String(right));
  return a === b;
}

function stamp(ms) {
  const date = new Date(Number(ms));
  const two = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())} ${two(date.getHours())}:${two(date.getMinutes())}`;
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function html(body, status) {
  return new Response(body, {
    status,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

function text(body, status) {
  return new Response(body, {
    status,
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
