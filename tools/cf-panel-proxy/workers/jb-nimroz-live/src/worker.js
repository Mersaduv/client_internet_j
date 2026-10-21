/**
 * Nimroz code panel and panel proxy. DeltaSIB for this province is the
 * Panel at http://149.54.23.54:9999/users/ , separate from Herat and Farah.
 *
 * Resilient ISP panel proxy for Cloudflare Workers.
 *
 * Cloudflare Workers cannot fetch raw IPs (error 1003). We reach the panel via:
 * 1) hostname aliases (sslip.io / nip.io) that resolve to the panel IP
 * 2) optional extra origins (live tunnels) from ORIGIN_CANDIDATES
 *
 * Never surfaces Cloudflare edge DNS errors (1016) when any candidate works.
 */
import { handleAdmin, handleDeleteAccount, handleLogout, handleRedeem } from "../../shared/sib-gate.js";
import {
  handleStaffSubscriber,
  handleSubscriberVolume,
  refusePublicDeltaSib,
} from "../../shared/sib-subscriber.js";

export default {
  async fetch(request, env) {
    const incoming = new URL(request.url);
    if (incoming.pathname === "/health") {
      return json({ ok: true, service: env.SERVICE_NAME || "panel-proxy" });
    }
    const withOrigin = {
      ...env,
      ORIGIN_BASE:
        env.ORIGIN_BASE ||
        `http://${env.PANEL_IP || "149.54.23.54"}:${env.PANEL_PORT || "9999"}`,
    };
    if (incoming.pathname === "/jahanbit/admin/api/subscriber") {
      return handleStaffSubscriber(request, withOrigin);
    }
    if (
      incoming.pathname === "/jahanbit/admin" ||
      incoming.pathname.startsWith("/jahanbit/admin/")
    ) {
      return handleAdmin(request, withOrigin);
    }
    if (incoming.pathname === "/jahanbit/sib/redeem") {
      return handleRedeem(request, withOrigin);
    }
    if (incoming.pathname === "/jahanbit/sib/logout") {
      return handleLogout(request, withOrigin);
    }
    if (incoming.pathname === "/jahanbit/sib/delete-account") {
      return handleDeleteAccount(request, withOrigin);
    }
    if (incoming.pathname === "/jahanbit/sib/volume") {
      return handleSubscriberVolume(request, withOrigin);
    }
    const refused = refusePublicDeltaSib(incoming);
    if (refused) return refused;

    const defaultPath = env.DEFAULT_PATH || "/";
    const isApi = incoming.pathname.startsWith("/1.0/");
    let path = incoming.pathname;
    if (!isApi && (path === "/" || path === "")) path = defaultPath;

    const candidates = isApi ? buildApiCandidates(env) : buildCandidates(env);
    if (!candidates.length) {
      return friendlyError(
        503,
        "هیچ مبدأیی برای پنل تنظیم نشده است.",
        "No panel origin configured.",
      );
    }

    const errors = [];
    for (const originBase of candidates) {
      try {
        const result = await proxyOnce(request, incoming, originBase, path);
        if (result) return result;
        errors.push({ origin: originBase, reason: "empty_or_bad_gateway" });
      } catch (e) {
        errors.push({ origin: originBase, reason: String(e) });
      }
    }

    if (isPrivateLanIp(env.PANEL_IP)) {
      return friendlyError(
        502,
        "این پنل روی شبکهٔ محلی ولایت است. وقتی به اینترنت همان ولایت (نیمروز/فراه) وصل باشید، اپ مستقیم به IP پنل وصل می‌شود.",
        "LAN panel is only reachable from that province network.",
        errors,
      );
    }

    return friendlyError(
      502,
      "فعلاً به پنل سرویس‌دهنده وصل نشد. چند ثانیه بعد دوباره تلاش کنید.",
      "All panel origins failed.",
      errors,
    );
  },
};

function isPrivateLanIp(ip) {
  const parts = String(ip || "")
    .trim()
    .split(".")
    .map((x) => Number(x));
  if (parts.length !== 4 || parts.some((n) => !Number.isFinite(n))) return false;
  const [a, b] = parts;
  if (a === 10) return true;
  if (a === 192 && b === 168) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  return false;
}

function buildApiCandidates(env) {
  const list = [];
  const push = (v) => {
    const s = String(v || "")
      .trim()
      .replace(/\/$/, "");
    if (s && !list.includes(s)) list.push(s);
  };
  const ip = String(env.PANEL_IP || "").trim();
  const port = String(env.API_PORT || "1043").trim();
  if (ip && !isPrivateLanIp(ip)) {
    push(`http://${ip}.sslip.io:${port}`);
    push(`http://${ip}.nip.io:${port}`);
    push(`https://${ip}.sslip.io:${port}`);
  }
  push(env.API_ORIGIN);
  return list;
}

function buildCandidates(env) {
  const list = [];
  const push = (v) => {
    const s = String(v || "")
      .trim()
      .replace(/\/$/, "");
    if (s && !list.includes(s)) list.push(s);
  };

  if (env.PANEL_IP && env.PANEL_PORT) {
    const ip = String(env.PANEL_IP).trim();
    const port = String(env.PANEL_PORT).trim();
    push(`http://${ip}.sslip.io:${port}`);
    push(`http://${ip}.nip.io:${port}`);
  }
  push(env.ORIGIN_BASE);

  // Comma/newline separated extras (tunnels, mirrors)
  const extras = String(env.ORIGIN_CANDIDATES || "");
  for (const part of extras.split(/[\n,]+/)) push(part);

  return list;
}

async function proxyOnce(request, incoming, originBase, path) {
  const target = originBase + path + incoming.search;
  const headers = new Headers(request.headers);
  headers.delete("host");
  headers.delete("cf-connecting-ip");
  headers.delete("cf-ipcountry");
  headers.delete("cf-ray");
  headers.delete("cf-visitor");
  headers.delete("accept-encoding");

  // Many ISP panels expect Host as ip:port even when reached via alias DNS.
  try {
    const originUrl = new URL(originBase);
    const hostLabel = originUrl.hostname;
    const ipMatch = hostLabel.match(
      /^(\d{1,3}(?:\.\d{1,3}){3})(?:\.(?:sslip|nip)\.io)?$/i,
    );
    if (ipMatch) {
      const port = originUrl.port || "80";
      headers.set("Host", port === "80" ? ipMatch[1] : `${ipMatch[1]}:${port}`);
    }
  } catch (_) {}

  const init = {
    method: request.method,
    headers,
    redirect: "manual",
  };
  if (request.method !== "GET" && request.method !== "HEAD") {
    init.body = request.body;
  }

  const upstream = await fetch(target, init);

  // Soft-fail edge / unreachable private origins → try next candidate
  if (
    upstream.status === 530 ||
    upstream.status === 1016 ||
    upstream.status === 502 ||
    upstream.status === 503
  ) {
    return null;
  }
  const probeText =
    upstream.status >= 400
      ? await upstream.clone().text().catch(() => "")
      : "";
  if (
    probeText.includes("error code: 1016") ||
    probeText.includes("error code: 1033") ||
    probeText.includes("error code: 1003") ||
    probeText.includes("error code: 1042")
  ) {
    return null;
  }
  // Cloudflare often returns bare 403 when the origin is a private LAN IP
  if (upstream.status === 403 && probeText.length < 200) {
    return null;
  }

  const outHeaders = new Headers(upstream.headers);
  const loc = outHeaders.get("location");
  if (loc) {
    try {
      const abs = new URL(loc, originBase);
      if (abs.host === new URL(originBase).host) {
        outHeaders.set(
          "location",
          incoming.origin + abs.pathname + abs.search + abs.hash,
        );
      }
    } catch (_) {}
  }

  const cookies = upstream.headers.getSetCookie?.() || [];
  if (cookies.length) {
    outHeaders.delete("set-cookie");
    for (const c of cookies) {
      outHeaders.append("set-cookie", c.replace(/;\s*Domain=[^;]*/gi, ""));
    }
  }

  const ct = (outHeaders.get("content-type") || "").toLowerCase();
  if (
    ct.includes("text/html") ||
    ct.includes("javascript") ||
    ct.includes("text/css")
  ) {
    let body = probeText || (await upstream.text());
    body = rewriteBody(body, originBase, incoming.origin);
    outHeaders.delete("content-length");
    return new Response(body, { status: upstream.status, headers: outHeaders });
  }

  return new Response(upstream.body, {
    status: upstream.status,
    headers: outHeaders,
  });
}

function rewriteBody(body, originBase, publicOrigin) {
  let out = body.split(originBase).join(publicOrigin);
  try {
    const u = new URL(originBase);
    const host = u.host;
    const ip = u.hostname.match(/^(\d{1,3}(?:\.\d{1,3}){3})/)?.[1];
    out = out.split(`http://${host}`).join(publicOrigin);
    out = out.split(`https://${host}`).join(publicOrigin);
    if (ip) {
      out = out.split(`http://${ip}:${u.port || "80"}`).join(publicOrigin);
      out = out.split(`http://${ip}`).join(publicOrigin);
      out = out
        .split(`http://${ip}.sslip.io:${u.port || "80"}`)
        .join(publicOrigin);
      out = out
        .split(`http://${ip}.nip.io:${u.port || "80"}`)
        .join(publicOrigin);
    }
  } catch (_) {}
  return out;
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function friendlyError(status, fa, en, details) {
  const html = `<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>اتصال پنل</title>
<style>body{font-family:Tahoma,sans-serif;background:#0f172a;color:#e2e8f0;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0}main{max-width:28rem;padding:1.5rem;background:#1e293b;border-radius:1rem}button{margin-top:1rem;padding:.7rem 1rem;border:0;border-radius:.7rem;background:#38bdf8;color:#0f172a;font-weight:700;width:100%}</style></head>
<body><main><h1 style="font-size:1.1rem;margin:0 0 .5rem">اتصال به پنل برقرار نشد</h1><p style="margin:0;line-height:1.7;opacity:.9">${fa}</p><p style="margin:.75rem 0 0;opacity:.65;font-size:.85rem">${en}</p><button onclick="location.reload()">تلاش دوباره</button></main>
<script>setTimeout(function(){location.reload()},8000)</script></body></html>`;
  return new Response(html, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "x-panel-proxy-errors": details ? JSON.stringify(details).slice(0, 800) : "",
      "cache-control": "no-store",
    },
  });
}
