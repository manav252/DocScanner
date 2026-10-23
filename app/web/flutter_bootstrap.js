{{flutter_js}}
{{flutter_build_config}}

// Start the app (Flutter's own service worker is not used: it only unregisters itself).
_flutter.loader.load();

// Offline support: our service worker (sw.js) keeps a copy of the whole app,
// including OpenCV, Tesseract and pdf.js, after the first visit.
// Changes with every build, so a new build replaces the old offline copy.
const buildVersion = {{flutter_service_worker_version}};
// Registered a few seconds after start, when the browser is idle: the offline
// copy (~50 MB) is then downloaded without slowing the app's first screen.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    const register = () =>
      navigator.serviceWorker.register('sw.js?v=' + buildVersion).catch((e) => {
        console.warn('Offline support unavailable:', e.message);
      });
    setTimeout(() => ('requestIdleCallback' in window ? requestIdleCallback(register, { timeout: 5000 }) : register()), 4000);
  });
}
