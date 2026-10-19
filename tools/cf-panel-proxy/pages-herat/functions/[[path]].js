export async function onRequest(context) {
  const originBase = "http://165.99.189.40:9394";
  const incoming = new URL(context.request.url);
  const blocked = incoming.pathname.toLowerCase();
  if (
    blocked.startsWith("/1.0") ||
    blocked.includes("/webservice/") ||
    blocked.includes("test.login.php") ||
    blocked.includes("test.user.")
  ) {
    return new Response(JSON.stringify({ error: "DeltaSIB API is not public" }), {
      status: 403,
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
  let path = incoming.pathname;
  if (path === "/" || path === "") path = "/users/";
  const target = originBase + path + incoming.search;
  const headers = new Headers(context.request.headers);
  headers.delete("host");
  headers.set("Host", "165.99.189.40:9394");
  headers.delete("accept-encoding");
  const init = { method: context.request.method, headers, redirect: "manual" };
  if (context.request.method !== "GET" && context.request.method !== "HEAD") {
    init.body = context.request.body;
  }
  try {
    const upstream = await fetch(target, init);
    const outHeaders = new Headers(upstream.headers);
    const loc = outHeaders.get("location");
    if (loc) {
      try {
        const abs = new URL(loc, originBase);
        if (abs.host === "165.99.189.40:9394" || abs.hostname === "165.99.189.40") {
          outHeaders.set("location", incoming.origin + abs.pathname + abs.search + abs.hash);
        }
      } catch {}
    }
    const ct = (outHeaders.get("content-type") || "").toLowerCase();
    if (ct.includes("text/html") || ct.includes("javascript") || ct.includes("text/css")) {
      let body = await upstream.text();
      body = body.split("http://165.99.189.40:9394").join(incoming.origin);
      body = body.split("https://165.99.189.40:9394").join(incoming.origin);
      outHeaders.delete("content-length");
      return new Response(body, { status: upstream.status, headers: outHeaders });
    }
    return new Response(upstream.body, { status: upstream.status, headers: outHeaders });
  } catch (e) {
    return new Response(String(e), { status: 502 });
  }
}