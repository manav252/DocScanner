{{flutter_js}}
{{flutter_build_config}}

// Start the app (Flutter's own service worker is not used: it only unregisters itself).
_flutter.loader.load();

// Offline support: our service worker (sw.js) keeps a copy of the whole app,
// including OpenCV, Tesseract and pdf.js, after the first visit.
// Changes with every build, so a new build replaces the old offline copy.
const buildVersion = {{flutter_service_worker_version}};
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js?v=' + buildVersion).catch((e) => {
      console.warn('Offline support unavailable:', e.message);
    });
  });
}
