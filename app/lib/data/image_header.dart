// Read the pixel size of a JPEG/PNG/WebP from its header (pure Dart, any platform).
import 'dart:typed_data';

/// (width, height), or null if the format is not recognised. JPEG EXIF
/// orientation is not applied; callers pass images we produced ourselves.
(int, int)? imageHeaderSize(Uint8List b) {
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    final d = ByteData.sublistView(b);
    return (d.getUint32(16), d.getUint32(20)); // IHDR
  }
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0xFF) {
        i += marker == 0xFF ? 1 : 2;
        continue;
      }
      final len = (b[i + 2] << 8) | b[i + 3];
      // SOF0..SOF15 except DHT (C4), JPG (C8), DAC (CC).
      if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
        return ((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
      }
      i += 2 + len;
    }
    return null;
  }
  if (b.length > 30 &&
      String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
    final chunk = String.fromCharCodes(b.sublist(12, 16));
    if (chunk == 'VP8X') return (1 + (b[24] | b[25] << 8 | b[26] << 16), 1 + (b[27] | b[28] << 8 | b[29] << 16));
    if (chunk == 'VP8 ') return ((b[26] | b[27] << 8) & 0x3fff, (b[28] | b[29] << 8) & 0x3fff);
    if (chunk == 'VP8L') {
      final bits = b[21] | b[22] << 8 | b[23] << 16 | b[24] << 24;
      return (1 + (bits & 0x3fff), 1 + ((bits >> 14) & 0x3fff));
    }
  }
  return null;
}
