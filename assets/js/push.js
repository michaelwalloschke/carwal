import { csrfToken } from "./app"

function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - base64String.length % 4) % 4);
  const base64 = (base64String + padding)
    .replace(/\-/g, '+')
    .replace(/_/g, '/');

  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);

  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

export default {
  mounted() {
    const vapidKey = this.el.dataset.vapidKey;
    if (!vapidKey) {
      console.warn("No VAPID public key provided in dataset.");
      return;
    }

    if ('serviceWorker' in navigator && 'PushManager' in window) {
      // Register service worker (idempotent)
      navigator.serviceWorker.register('/sw.js')
        .then(reg => {
          console.log('Service Worker registered successfully:', reg);
        })
        .catch(err => {
          console.error('Service Worker registration failed:', err);
        });

      const btn = this.el.querySelector('#enable-push-btn');
      if (btn) {
        btn.addEventListener('click', async () => {
          try {
            const reg = await navigator.serviceWorker.ready;
            const perm = await Notification.requestPermission();
            if (perm !== 'granted') {
              this.pushEvent('push_unsubscribed', {});
              return;
            }

            const applicationServerKey = urlBase64ToUint8Array(vapidKey);
            const sub = await reg.pushManager.subscribe({
              userVisibleOnly: true,
              applicationServerKey: applicationServerKey
            });

            const response = await fetch('/push/subscribe', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'x-csrf-token': csrfToken
              },
              body: JSON.stringify(sub),
              credentials: 'same-origin'
            });

            if (response.ok) {
              this.pushEvent('push_subscribed', {});
            } else {
              console.error('Failed to subscribe on server:', response.statusText);
            }
          } catch (e) {
            console.error('Error subscribing to push notifications:', e);
          }
        });
      }
    } else {
      console.warn('Push notifications are not supported in this browser.');
      const btn = this.el.querySelector('#enable-push-btn');
      if (btn) {
        btn.disabled = true;
        btn.innerText = "Nicht unterstützt";
      }
    }
  }
};
