// Only two commands — list and close by exact URL — so a compromised host can at worst close tabs.
let port;
function connect() {
  port = browser.runtime.connectNative("tab_closer");
  port.onMessage.addListener(async (msg) => {
    let reply;
    try {
      const urls = new Set(msg.urls || []);
      const tabs = (await browser.tabs.query({})).filter((t) => urls.has(t.url));
      const info = tabs.map((t) => ({ id: t.id, url: t.url, title: t.title, discarded: t.discarded }));
      if (msg.cmd === "close") await browser.tabs.remove(tabs.map((t) => t.id));
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
