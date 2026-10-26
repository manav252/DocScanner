// The OCR runner's two-pass logic (mirrors lib/features/editor/ocr_runner.dart),
// for eval_ocr.js.

/** Fewer than this many letters/digits in total: "little text", try the second variant. */
const LITTLE_TEXT = 40;

const littleText = (r) => (r.text.match(/[\p{L}\p{N}]/gu) || []).length < LITTLE_TEXT;

/** First pass's lines, plus the second pass's lines that do not overlap them (boxes 0..1). */
function mergeOcr(a, b) {
  const overlap = (p, q) => {
    const x = Math.max(0, Math.min(p[0] + p[2], q[0] + q[2]) - Math.max(p[0], q[0]));
    const y = Math.max(0, Math.min(p[1] + p[3], q[1] + q[3]) - Math.max(p[1], q[1]));
    return (x * y) / Math.min(p[2] * p[3], q[2] * q[3]);
  };
  const lines = [...a.lines, ...b.lines.filter((l) => !a.lines.some((m) => overlap(l.box, m.box) > 0.5))];
  lines.sort((p, q) => p.box[1] - q.box[1] || p.box[0] - q.box[0]);
  return { ...a, text: lines.map((l) => l.text).join('\n'), lines };
}

/** [first image, () => second image] for the page image (RGBA). */
const prepareOcrVariants = (cv, S, render) => [S.prepareOcr(cv, render, 'main'), () => S.prepareOcr(cv, render, 'contrast')];

module.exports = { littleText, mergeOcr, prepareOcrVariants, LITTLE_TEXT };
