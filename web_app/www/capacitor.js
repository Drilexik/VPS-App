// This file is replaced by the real Capacitor runtime when bundled
// into the Android APK (via `npx cap sync android`).
// In the browser (for local testing), Capacitor is undefined → the
// app falls back to localStorage + in-app toasts gracefully.
if (typeof window.Capacitor === 'undefined') {
  console.log('[Drilex] Browser mode – Capacitor plugins disabled');
}
