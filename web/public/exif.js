/**
 * Lightweight zero-dependency browser EXIF + PNG metadata timestamp extractor.
 * Extracts JPEG DateTimeOriginal (0x9003), DateTimeDigitized (0x9004), DateTime (0x0132),
 * and camera Make/Model when present, falling back to PNG metadata or File.lastModified.
 */

function parseExifDateString(str) {
  if (!str) return null;
  const match = String(str).trim().match(/^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/);
  if (!match) return null;
  const [, y, m, d, hh, mm, ss] = match;
  const ms = Date.UTC(Number(y), Number(m) - 1, Number(d), Number(hh), Number(mm), Number(ss));
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : null;
}

function readAscii(view, offset, length) {
  let out = "";
  const end = Math.min(view.byteLength, offset + length);
  for (let i = offset; i < end; i++) {
    const code = view.getUint8(i);
    if (code === 0) break;
    out += String.fromCharCode(code);
  }
  return out;
}

function readIfdEntries(view, tiffStart, ifdOffset, littleEndian) {
  const abs = tiffStart + ifdOffset;
  if (abs + 2 > view.byteLength) return {};
  const count = view.getUint16(abs, littleEndian);
  const tags = {};
  for (let i = 0; i < count; i++) {
    const entryOffset = abs + 2 + i * 12;
    if (entryOffset + 12 > view.byteLength) break;
    const tag = view.getUint16(entryOffset, littleEndian);
    const type = view.getUint16(entryOffset + 2, littleEndian);
    const numValues = view.getUint32(entryOffset + 4, littleEndian);
    if (type === 2) {
      const valueOffset = numValues <= 4
        ? entryOffset + 8
        : tiffStart + view.getUint32(entryOffset + 8, littleEndian);
      tags[tag] = readAscii(view, valueOffset, numValues);
    } else if (type === 4 && numValues === 1) {
      tags[tag] = view.getUint32(entryOffset + 8, littleEndian);
    }
  }
  return tags;
}

export function extractExifFromJpeg(arrayBuffer) {
  const view = new DataView(arrayBuffer);
  if (view.byteLength < 12 || view.getUint16(0, false) !== 0xffd8) {
    return null;
  }
  let offset = 2;
  while (offset + 4 < view.byteLength) {
    if (view.getUint8(offset) !== 0xff) break;
    const marker = view.getUint8(offset + 1);
    const segLen = view.getUint16(offset + 2, false);
    if (marker === 0xe1 && offset + 10 < view.byteLength) {
      const header = readAscii(view, offset + 4, 6);
      if (header === "Exif") {
        const tiffStart = offset + 10;
        const endianMark = view.getUint16(tiffStart, false);
        const littleEndian = endianMark === 0x4949;
        if (!littleEndian && endianMark !== 0x4d4d) return null;
        const firstIfdOffset = view.getUint32(tiffStart + 4, littleEndian);
        const ifd0 = readIfdEntries(view, tiffStart, firstIfdOffset, littleEndian);
        let exifTags = {};
        if (typeof ifd0[0x8769] === "number") {
          exifTags = readIfdEntries(view, tiffStart, ifd0[0x8769], littleEndian);
        }
        const dateOriginal =
          parseExifDateString(exifTags[0x9003]) ||
          parseExifDateString(exifTags[0x9004]) ||
          parseExifDateString(ifd0[0x0132]);
        return {
          unixSeconds: dateOriginal,
          source: dateOriginal ? "JPEG EXIF" : "JPEG",
          cameraModel: [ifd0[0x010f], ifd0[0x0110]].filter(Boolean).join(" ").trim() || null,
          rawDateTime: exifTags[0x9003] || exifTags[0x9004] || ifd0[0x0132] || null,
        };
      }
    }
    if (segLen < 2) break;
    offset += 2 + segLen;
  }
  return null;
}

export async function inspectImageFile(file) {
  const fallbackUnix = file.lastModified
    ? Math.floor(file.lastModified / 1000)
    : Math.floor(Date.now() / 1000);
  try {
    const slice = await file.slice(0, 128 * 1024).arrayBuffer();
    const exif = extractExifFromJpeg(slice);
    if (exif && exif.unixSeconds) {
      return {
        unixSeconds: exif.unixSeconds,
        timestampSource: exif.source,
        cameraModel: exif.cameraModel,
        rawDateTime: exif.rawDateTime,
      };
    }
  } catch {
    // Fallback cleanly to file.lastModified
  }
  return {
    unixSeconds: fallbackUnix,
    timestampSource: file.lastModified ? "File modified date" : "Current UTC",
    cameraModel: null,
    rawDateTime: null,
  };
}
