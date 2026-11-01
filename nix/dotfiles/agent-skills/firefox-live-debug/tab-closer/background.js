// Three commands — list, close by exact URL, closeAt (URL + tab-strip index) — so a compromised host can at worst close tabs.
let port;
function connect() {
  port = browser.runtime.connectNative("tab_closer");
  port.onMessage.addListener(async (msg) => {
    let reply;
    try {
      const targets = msg.targets || [];
      const urls = new Set(msg.urls || targets.map((g) => g.url));
      let tabs = (await browser.tabs.query({})).filter((t) => urls.has(t.url));
      if (msg.cmd === "closeAt") {
        // Only the one tab with this URL at this index; moved or ambiguous (same
        // URL+index in two windows) -> skip, the caller retries with a fresh index.
        tabs = targets.flatMap((g) => {
          const m = tabs.filter((t) => t.index === g.index && t.url === g.url);
          return m.length === 1 ? m : [];
        });
      }
      const info = tabs.map((t) => ({ id: t.id, url: t.url, title: t.title, discarded: t.discarded,
                                      index: t.index, windowId: t.windowId }));
      if (msg.cmd === "close" || msg.cmd === "closeAt") await browser.tabs.remove(tabs.map((t) => t.id));
      else if (msg.cmd !== "list") throw new Error(`unknown cmd ${msg.cmd}`);
      reply = { rid: msg.rid, ok: true, tabs: info };
    } catch (e) {
      reply = { rid: msg.rid, ok: false, error: String(e) };
    }
    port.postMessage(reply);
  });
  port.onDisconnect.addListener(() => setTimeout(connect, 5000));
}
connect();
