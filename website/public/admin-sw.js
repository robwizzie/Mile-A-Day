/* Mile A Day desk remote: web push. Shows what the server sends (already
   end-to-end encrypted to this phone) and opens the remote when tapped.
   Nothing is cached: the panel always loads fresh. */
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { title: "Mile A Day", body: event.data ? event.data.text() : "" };
  }
  const url = typeof data.url === "string" && data.url.startsWith("/admin") ? data.url : "/admin/desk";
  event.waitUntil(self.registration.showNotification(data.title || "Mile A Day", {
    body: data.body || "",
    icon: "/images/mad-circle-icon.png",
    badge: "/images/mad-circle-icon.png",
    tag: data.tag || undefined,
    renotify: Boolean(data.tag),
    data: { url },
  }));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || "/admin/desk";
  event.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const w of wins) {
      if (w.url.includes("/admin")) {
        await w.focus();
        if ("navigate" in w) await w.navigate(url);
        return;
      }
    }
    await self.clients.openWindow(url);
  })());
});
