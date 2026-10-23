// "How it works": run the app's real detector (app/web/opencv/scanner.js) in a
// worker on the user's photo and draw every intermediate step.
const status = document.getElementById('status');
const input = document.getElementById('photo');
const sampleBtn = document.getElementById('sample');
const worker = new Worker('js/pipeline_worker.js');
let ready = false;
let busy = false;

function setStatus(text) {
  status.textContent = text;
}

function draw(step, img) {
  const li = document.querySelector(`[data-step="${step}"]`);
  let canvas = li.querySelector('canvas');
  if (!canvas) {
    canvas = document.createElement('canvas');
    canvas.setAttribute('role', 'img');
    li.insertBefore(canvas, li.querySelector('h3').nextSibling);
  }
  canvas.width = img.width;
  canvas.height = img.height;
  canvas.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(img.data), img.width, img.height), 0, 0);
  canvas.setAttribute('aria-label', `${li.querySelector('h3').textContent.replace(/^\d+/, '')} step image, ${img.width} by ${img.height} pixels`);
}

async function toImageData(blob) {
  // Respect the photo's EXIF orientation, like the app does.
  const bmp = await createImageBitmap(blob, { imageOrientation: 'from-image' });
  const scale = Math.min(1, 2000 / Math.max(bmp.width, bmp.height));
  const w = Math.round(bmp.width * scale), h = Math.round(bmp.height * scale);
  const c = new OffscreenCanvas(w, h);
  c.getContext('2d').drawImage(bmp, 0, 0, w, h);
  return c.getContext('2d').getImageData(0, 0, w, h);
}

async function run(blob, name) {
  if (!ready || busy) return;
  busy = true;
  setStatus(`Processing ${name}…`);
  try {
    const img = await toImageData(blob);
    worker.postMessage({ type: 'explain', image: { data: img.data, width: img.width, height: img.height } }, [img.data.buffer]);
  } catch (e) {
    busy = false;
    setStatus(`That file could not be read as a photo (${e.message}).`);
  }
}

worker.onmessage = ({ data }) => {
  if (data.type === 'ready') {
    ready = true;
    setStatus('Ready. Choose a photo of a page, or use the sample.');
  } else if (data.type === 'result') {
    busy = false;
    for (const [step, img] of Object.entries(data.steps)) draw(step, img);
    const r = data.result;
    setStatus(
      r.found
        ? `Page found (covers ${(r.score * 100).toFixed(0)}% of the photo; ${data.contourCount} outlines checked; ${data.pass} pass) in ${data.ms} ms.`
        : `No page found in this photo (${data.contourCount} outlines checked). The app would keep the full photo and let you set the corners.`,
    );
  } else if (data.type === 'error') {
    busy = false;
    setStatus(`Something went wrong: ${data.message}`);
  }
};
worker.onerror = (e) => setStatus(`Could not start the detector: ${e.message}`);

input.addEventListener('change', () => {
  const f = input.files?.[0];
  if (f) run(f, f.name);
});
sampleBtn.addEventListener('click', async () => {
  const r = await fetch('img/sample-page.jpg');
  run(await r.blob(), 'the sample photo');
});
