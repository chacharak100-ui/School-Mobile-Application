importScripts("https://www.gstatic.com/firebasejs/10.0.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.0.0/firebase-messaging-compat.js");

// Initialize Firebase with your project credentials
firebase.initializeApp({
  apiKey: "AIzaSyB_-To5uuSVfoElk_RqKWzRojp6smfcX3g",
  authDomain: "mizora-school-app.firebaseapp.com",
  projectId: "mizora-school-app",
  storageBucket: "mizora-school-app.firebasestorage.app",
  messagingSenderId: "693583997868",
  appId: "1:693583997868:web:29c5d21d6a1c4e990a6809",
  measurementId: "G-KVB66P28ZW"
});

const messaging = firebase.messaging();

// Handle background notifications when Chrome is closed or minimized
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message: ', payload);
  const notificationTitle = payload.notification?.title || "New Notification";
  const notificationOptions = {
    body: payload.notification?.body || "",
    icon: '/icons/Icon-192.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});