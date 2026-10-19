/**
 * Free HTTPS front for Herat ISP panel (workers.dev).
 * Proxies https://<worker>.workers.dev/* → http://165.99.189.40:9394/*
 */
import {
  handleSubscriberVolume,
  refusePublicDeltaSib,
} from "../../shared/sib-subscriber.js";

export default {
  async fetch(request, env) {
    const incoming = new URL(request.url);
    if (incoming.pathname === "/jahanbit/sib/volume") {
      return handleSubscriberVolume(request, env);
    }
    const refused = refusePublicDeltaSib(incoming);
    if (refused) return refused;

    const originBase = (env.ORIGIN_BASE || "http://165.99.189.40:9394").replace(
      /\/$/,
      "",
    );

    // Default landing → /users/
    let path = incoming.pathname;
    if (path === "/" || path === "") {
      path = "/users/";
    }

    const target = new URL(originBase + path + incoming.search);

    const headers = new Headers(request.headers);
    headers.delete("host");
    headers.set("Host", new URL(originBase).host);
    // Avoid compressing through worker when we may rewrite HTML.
    headers.delete("accept-encoding");

    const init = {
      method: request.method,
      headers,
      redirect: "manual",
    };
    if (request.method !== "GET" && request.method !== "HEAD") {
      init.body = request.body;
    }

    let upstream;
    try {
      upstream = await fetch(target.toString(), init);
    } catch (err) {
      return new Response(
        `Upstream unreachable: ${originBase}\n${String(err)}`,
        { status: 502, headers: { "content-type": "text/plain; charset=utf-8" } },
      );
    }

    const outHeaders = new Headers(upstream.headers);
    const location = outHeaders.get("location");
    if (location) {
      outHeaders.set(
        "location",
        rewriteLocation(location, originBase, incoming.origin),
      );
    }

    // Cookies: drop Domain= so browser binds to workers.dev host
    const cookies = upstream.headers.getSetCookie?.() || [];
    if (cookies.length) {
      outHeaders.delete("set-cookie");
      for (const c of cookies) {
        outHeaders.append(
          "set-cookie",
          c.replace(/;\s*Domain=[^;]*/gi, "").replace(/;\s*Secure/gi, ""),
        );
      }
    }

    const contentType = (outHeaders.get("content-type") || "").toLowerCase();
    if (
      contentType.includes("text/html") ||
      contentType.includes("application/javascript") ||
      contentType.includes("text/css")
    ) {
      let body = await upstream.text();
      body = rewriteBody(body, originBase, incoming.origin);
      outHeaders.delete("content-length");
      return new Response(body, {
        status: upstream.status,
        statusText: upstream.statusText,
        headers: outHeaders,
      });
    }

    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: outHeaders,
    });
  },
};

function rewriteLocation(location, originBase, publicOrigin) {
  try {
    const abs = new URL(location, originBase);
    const originUrl = new URL(originBase);
    if (abs.host === originUrl.host) {
      return publicOrigin + abs.pathname + abs.search + abs.hash;
    }
  } catch (_) {}
  return location;
}

function rewriteBody(body, originBase, publicOrigin) {
  const originUrl = new URL(originBase);
  const hostPort = originUrl.host; // may include :9394
  const patterns = [
    `http://${hostPort}`,
    `https://${hostPort}`,
    `//${hostPort}`,
  ];
  let out = body;
  for (const p of patterns) {
    out = out.split(p).join(publicOrigin);
  }
  // Bare IP without scheme in some templates
  out = out.split(hostPort).join(new URL(publicOrigin).host);
  return out;
}
