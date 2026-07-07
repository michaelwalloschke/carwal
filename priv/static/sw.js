self.addEventListener('push', event => {
  const payload = event.data ? event.data.text() : "";
  event.waitUntil(
    self.registration.showNotification('CarWal', {
      body: payload,
      icon: '/images/logo.svg',
      badge: '/images/logo.svg',
      data: { url: '/' }
    })
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clientList => {
      for (const client of clientList) {
        if (client.url.endsWith('/') && 'focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
    })
  );
});
