import {
  handleSubscriberVolume,
  refusePublicDeltaSib,
} from "./sib-subscriber.js";

export default {
  async fetch(request, env) {
    const originBase = (env.ORIGIN_BASE || "").replace(/\/$/, "");
    const defaultPath = env.DEFAULT_PATH || "/";
    const incoming = new URL(request.url);
    if (incoming.pathname === "/health") return new Response("ok");
    if (incoming.pathname === "/jahanbit/sib/volume") {
      return handleSubscriberVolume(request, env);
    }
    const refused = refusePublicDeltaSib(incoming);
    if (refused) return refused;
    let path = incoming.pathname;
    if (path === "/" || path === "") path = defaultPath;
    if (!originBase) {
      return new Response("ORIGIN_BASE missing", { status: 500 });
    }
    const target = originBase + path + incoming.search;
    const headers = new Headers(request.headers);
    headers.delete("host");
    headers.delete("cf-connecting-ip");
    headers.delete("cf-ipcountry");
    headers.delete("cf-ray");
    headers.delete("cf-visitor");
    headers.delete("accept-encoding");
    const init = {
      method: request.method,
      headers,
      redirect: "manual",
    };
    if (request.method !== "GET" && request.method !== "HEAD") {
      init.body = request.body;
    }
    try {
      const upstream = await fetch(target, init);
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
          outHeaders.append(
            "set-cookie",
            c.replace(/;\s*Domain=[^;]*/gi, ""),
          );
        }
      }
      const ct = (outHeaders.get("content-type") || "").toLowerCase();
      if (
        ct.includes("text/html") ||
        ct.includes("javascript") ||
        ct.includes("text/css")
      ) {
        let body = await upstream.text();
        body = body.split(originBase).join(incoming.origin);
        outHeaders.delete("content-length");
        return new Response(body, {
          status: upstream.status,
          headers: outHeaders,
        });
      }
      return new Response(upstream.body, {
        status: upstream.status,
        headers: outHeaders,
      });
    } catch (e) {
      return new Response("upstream:" + String(e), { status: 502 });
    }
  },
};
