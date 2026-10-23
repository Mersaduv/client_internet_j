/**
 * Subscriber volume for Jahan Bit.
 *
 * The phone sends its own session. This worker logs in as the
 * DeltaSIB API reseller (secrets SIB_API_USERNAME / SIB_API_PASSWORD) and
 * returns that one user's creditinfo. The API password never goes to the app.
 *
 * Set the secrets on each province worker:
 *   wrangler secret put SIB_API_USERNAME
 *   wrangler secret put SIB_API_PASSWORD
 */

import { isStaff, usernameForSession } from "./sib-gate.js";

const ALLOWED_READS = new Set(["creditinfo", "list"]);

/** Public panel proxy must not forward the DeltaSIB API or its test console. */
export function refusePublicDeltaSib(url) {
  const path = url.pathname.toLowerCase();
  const blocked =
    path.startsWith("/1.0") ||
    path.includes("/webservice/") ||
    path.includes("test.login.php") ||
    path.includes("test.user.");
  if (!blocked) return null;
  return json({ error: "DeltaSIB API is not public" }, 403);
}

export async function handleSubscriberVolume(request, env) {
  if (request.method !== "POST") {
    return json({ error: "POST required" }, 405);
  }

  let body = {};
  try {
    body = await request.json();
  } catch (_) {
    body = {};
  }

  const sessionUser = await usernameForSession(env, body.session);
  const claimed = String(body.username || "").trim();
  if (!sessionUser) {
    return json(
      {
        error: "نشست پایان یافته است. نام کاربری و رمز را دوباره وارد کنید.",
        code: "session_expired",
      },
      401,
    );
  }
  if (claimed && claimed.toLowerCase() !== sessionUser.toLowerCase()) {
    return json({ error: "این نشست برای مشترک دیگری است." }, 403);
  }
  const username = sessionUser;
  if (!isSubscriberUsername(username)) {
    return json({ error: "invalid subscriber username" }, 400);
  }

  const apiUser = String(env.SIB_API_USERNAME || "").trim();
  const apiPass = String(env.SIB_API_PASSWORD || "");
  if (!apiUser || !apiPass) {
    return json(
      {
        error:
          "DeltaSIB API user is not configured. Set SIB_API_USERNAME and SIB_API_PASSWORD on the worker.",
      },
      503,
    );
  }

  const loaded = await loadSubscriberProfile(env, username, apiUser, apiPass);
  if (loaded.status === "missing-origin") {
    return json({ error: "ORIGIN_BASE is empty" }, 503);
  }
  if (loaded.status === "not-found") {
    return json({ error: "subscriber not found" }, 404);
  }
  if (loaded.status !== "ok") {
    return json({ error: "DeltaSIB unreachable" }, 502);
  }
  return json({
    username: loaded.username,
    name: loaded.name,
    credit: loaded.credit,
  });
}

/** Same lookup the staff panel uses. status is ok, not-found, unconfigured, or down. */
export async function lookupSubscriber(env, username) {
  const apiUser = String(env.SIB_API_USERNAME || "").trim();
  const apiPass = String(env.SIB_API_PASSWORD || "");
  if (!apiUser || !apiPass) return { status: "unconfigured" };
  return loadSubscriberProfile(env, username, apiUser, apiPass);
}

/** Staff-only read of one subscriber. The phone cannot call this. */
export async function handleStaffSubscriber(request, env) {
  if (request.method !== "GET") return json({ error: "GET required" }, 405);
  if (!(await isStaff(request, env))) {
    return json({ error: "وارد پنل نشده‌اید." }, 401);
  }
  const username = String(new URL(request.url).searchParams.get("username") || "").trim();
  if (!isSubscriberUsername(username)) {
    return json({ error: "نام کاربری نادرست است." }, 400);
  }
  const loaded = await lookupSubscriber(env, username);
  if (loaded.status === "unconfigured") return json({ error: "API user is not configured" }, 503);
  if (loaded.status === "not-found") return json({ error: "subscriber not found" }, 404);
  if (loaded.status !== "ok") return json({ error: "DeltaSIB unreachable" }, 502);
  return json({
    username: loaded.username,
    name: loaded.name,
    profile: scrubProfile(loaded.credit),
  });
}

async function loadSubscriberProfile(env, username, apiUser, apiPass) {
  const origins = panelOrigins(env);
  if (!origins.length) return { status: "missing-origin" };
  const safeName = username.replace(/'/g, "");
  const filter = `Username='${safeName}'`;
  for (const origin of origins) {
    try {
      const loginText = await postForm(
        `${origin.base}/test/webservice/api/restfull/test.login.php`,
        {
          Api_Username: apiUser,
          Api_Password: apiPass,
          submit: "Submit",
        },
        origin.host,
      );
      const token = parseToken(loginText);
      if (!token) continue;
      const creditText = await readSubscriber(origin, token, {
        action: "creditinfo",
        filter,
      });
      const credit = pickCredit(parsePayload(creditText), safeName);
      if (!credit) return { status: "not-found" };
      const listText = await readSubscriber(origin, token, {
        action: "list",
        filter,
        field: "User_Id,Username,Name,Family",
        limitCount: "5",
      });
      return {
        status: "ok",
        username: safeName,
        name: pickName(parsePayload(listText), safeName),
        credit,
      };
    } catch (_) {}
  }
  return { status: "down" };
}

function scrubProfile(row) {
  const out = {};
  if (!row || typeof row !== "object") return out;
  for (const [key, value] of Object.entries(row)) {
    if (/pass|token|secret|api|session/i.test(key)) continue;
    if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
      out[key] = value;
    }
  }
  return out;
}

function panelOrigins(env) {
  const list = [];
  const push = (base, host) => {
    const clean = String(base || "").replace(/\/$/, "");
    if (!clean || list.some((item) => item.base === clean)) return;
    list.push({ base: clean, host: host || "" });
  };
  const ip = String(env.PANEL_IP || "").trim();
  const port = String(env.PANEL_PORT || "").trim();
  const origin = String(env.ORIGIN_BASE || "");
  if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(ip) && port && !isPrivateLanIp(ip)) {
    const host = port === "80" ? ip : `${ip}:${port}`;
    if (origin.startsWith("https://")) {
      push(`https://${ip}.sslip.io:${port}`, host);
      push(`https://${ip}.nip.io:${port}`, host);
    }
    push(`http://${ip}.sslip.io:${port}`, host);
    push(`http://${ip}.nip.io:${port}`, host);
  }
  push(origin, "");
  return list;
}

function isPrivateLanIp(ip) {
  const parts = ip.split(".").map((part) => Number(part));
  if (parts.length !== 4 || parts.some((n) => !Number.isFinite(n))) return true;
  const [a, b] = parts;
  if (a === 10 || a === 127) return true;
  if (a === 192 && b === 168) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  return false;
}

async function readSubscriber(origin, token, { action, filter, field, limitCount }) {
  if (!ALLOWED_READS.has(action)) {
    throw new Error("refused");
  }
  return postForm(
    `${origin.base}/test/webservice/api/restfull/test.user.creditinfo.php`,
    {
      token,
      Object: "user",
      Action: action,
      Filter: filter,
      ...(field ? { Field: field } : {}),
      LimitFrom: "0",
      LimitCount: limitCount || "1",
      submit: "Submit",
    },
    origin.host,
  );
}

function isSubscriberUsername(value) {
  return /^[\p{L}\p{N}._@-]{1,64}$/u.test(value);
}

async function postForm(url, fields, hostHeader) {
  const headers = { "content-type": "application/x-www-form-urlencoded" };
  if (hostHeader) headers.host = hostHeader;
  const response = await fetch(url, {
    method: "POST",
    headers,
    body: new URLSearchParams(fields),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} ${clip(text)}`);
  }
  return text;
}

function parseToken(body) {
  const match = body.match(
    /\{\s*"token"\s*:\s*"([^"]+)"\s*,\s*"SessionTimeout"\s*:\s*"?(\d+)"?\s*\}/,
  );
  if (match) return match[1].replace(/\s+/g, "");
  const payload = parsePayload(body);
  if (payload && typeof payload === "object" && !Array.isArray(payload)) {
    const token = payload.token;
    if (typeof token === "string" && token) return token;
  }
  return "";
}

function parsePayload(body) {
  const cell = body.match(/Result<\/td>\s*<td[^>]*>([\s\S]*?)<\/td>/i);
  const region = cell ? cell[1] : body;
  const cleaned = region
    .replace(/<[^>]+>/g, " ")
    .replace(/&quot;/g, '"')
    .replace(/&#34;/g, '"')
    .replace(/&amp;/g, "&")
    .trim();
  const start = cleaned.indexOf("[") >= 0 &&
    (cleaned.indexOf("{") < 0 || cleaned.indexOf("[") < cleaned.indexOf("{"))
    ? cleaned.indexOf("[")
    : cleaned.indexOf("{");
  if (start < 0) return null;
  const endChar = cleaned[start] === "[" ? "]" : "}";
  const end = cleaned.lastIndexOf(endChar);
  if (end <= start) return null;
  try {
    return JSON.parse(cleaned.slice(start, end + 1));
  } catch (_) {
    return null;
  }
}

function pickCredit(payload, username) {
  const row = pickOwnRow(payload, username);
  return row;
}

function pickName(payload, username) {
  const match = pickOwnRow(payload, username);
  if (!match) return "";
  const name = String(match.Name || match.name || "").trim();
  const family = String(match.Family || match.family || "").trim();
  return `${name} ${family}`.trim();
}

function pickOwnRow(payload, username) {
  const rows = asRows(payload);
  if (!rows.length) return null;
  const match = rows.find((row) => sameUser(row, username));
  if (match) return match;
  if (rows.length !== 1) return null;
  const found = rowUsername(rows[0]);
  return found ? null : rows[0];
}

function rowUsername(row) {
  return String(row.Username || row.username || row.UserName || "").trim();
}

function asRows(payload) {
  if (!payload) return [];
  if (Array.isArray(payload)) return payload.filter((row) => row && typeof row === "object");
  if (typeof payload === "object") return [payload];
  return [];
}

function sameUser(row, username) {
  const found = rowUsername(row);
  return found.toLowerCase() === username.toLowerCase();
}

function clip(value) {
  const text = String(value || "").replace(/\s+/g, " ").trim();
  return text.length > 240 ? `${text.slice(0, 240)}…` : text;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
