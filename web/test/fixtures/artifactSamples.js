import { Buffer } from "node:buffer";
import { deflateSync } from "node:zlib";

export const textPreviewBody = "browser text preview from routed artifact upload\n";
export const jsonPreviewBody = "{\"source\":\"browser\",\"preview\":\"json\"}";

export function tinyPngBuffer() {
  return Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=",
    "base64",
  );
}

export function tinyWavBuffer() {
  return Buffer.from(
    "UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YQAAAAA=",
    "base64",
  );
}

export function tinyMp4Buffer() {
  return Buffer.from("000000186674797069736f6d0000020069736f6d69736f3261766331", "hex");
}

export function tinyPdfBuffer() {
  return Buffer.from("%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n", "utf8");
}

export function tinyMidiBuffer() {
  return Buffer.from("TVRoZAAAAAYAAAABAGBNVHJrAAAABAAP/w==", "base64");
}

export function musicXmlBuffer() {
  return Buffer.from("<score-partwise version=\"4.0\"></score-partwise>", "utf8");
}

export function binaryArtifactBuffer() {
  return Buffer.from([0, 1, 2, 3, 4, 5, 6, 7]);
}

// Phase 4 Sprint 4.23: real per-family input fixtures, generated
// programmatically so they are deterministic (byte-identical across runs and
// substrates) and carry genuine signal rather than the degenerate
// silence-WAV / 1x1-PNG inputs. The browser per-model smoke matrix routes
// each family's upload through these; the OMR/tool row now receives a real
// score IMAGE (PNG) instead of MusicXML.

function clampToInt16(amplitude) {
  return Math.max(-32768, Math.min(32767, Math.round(amplitude * 32767)));
}

function encodePcm16Wav(sampleRate, channels, samples) {
  const blockAlign = channels * 2;
  const byteRate = sampleRate * blockAlign;
  const dataLength = samples.length * 2;
  const buffer = Buffer.alloc(44 + dataLength);
  buffer.write("RIFF", 0, "ascii");
  buffer.writeUInt32LE(36 + dataLength, 4);
  buffer.write("WAVE", 8, "ascii");
  buffer.write("fmt ", 12, "ascii");
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20); // PCM
  buffer.writeUInt16LE(channels, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(byteRate, 28);
  buffer.writeUInt16LE(blockAlign, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write("data", 36, "ascii");
  buffer.writeUInt32LE(dataLength, 40);
  for (let index = 0; index < samples.length; index += 1) {
    buffer.writeInt16LE(clampToInt16(samples[index]), 44 + index * 2);
  }
  return buffer;
}

function deterministicNoise(index) {
  const seeded = (1103515245 * (index + 12345) + 12345) % 2147483648;
  return seeded / 1073741824 - 1;
}

// A non-silent, speech-like mono 16 kHz waveform: a falling-pitch sawtooth
// glottal source shaped by two gliding formants plus light aspiration noise.
// Speech-shaped, not genuinely spoken; a real utterance should be sourced for
// the cohort gate.
export function speechWavBuffer() {
  const sampleRate = 16000;
  const durationSeconds = 1.6;
  const sampleCount = Math.round(durationSeconds * sampleRate);
  const samples = new Array(sampleCount);
  for (let index = 0; index < sampleCount; index += 1) {
    const t = index / sampleRate;
    const progress = t / durationSeconds;
    const f0 = 150 - 55 * progress;
    let source = 0;
    for (let harmonic = 1; harmonic <= 12; harmonic += 1) {
      source += (1 / harmonic) * Math.sin(2 * Math.PI * f0 * harmonic * t);
    }
    const formant1 = 500 + 300 * progress;
    const formant2 = 1500 + 700 * progress;
    const shaped =
      source * (0.6 + 0.4 * Math.sin(2 * Math.PI * formant1 * t)) +
      0.3 * source * Math.sin(2 * Math.PI * formant2 * t);
    const noise = deterministicNoise(index) * 0.08;
    const envelope = Math.min(1, Math.min(progress * 8, (1 - progress) * 8));
    samples[index] = 0.5 * envelope * (shaped + noise);
  }
  return encodePcm16Wav(sampleRate, 1, samples);
}

// A real music-like mixture for source separation: a sustained major triad, a
// low bass tone, and a rhythmic percussive pulse, 44.1 kHz stereo.
export function separationMixtureWavBuffer() {
  const sampleRate = 44100;
  const durationSeconds = 2.0;
  const sampleCount = Math.round(durationSeconds * sampleRate);
  const samples = new Array(sampleCount * 2);
  for (let index = 0; index < sampleCount; index += 1) {
    const t = index / sampleRate;
    const chord =
      Math.sin(2 * Math.PI * 261.63 * t) +
      Math.sin(2 * Math.PI * 329.63 * t) +
      Math.sin(2 * Math.PI * 392.0 * t);
    const bass = Math.sin(2 * Math.PI * 82.41 * t);
    const beatPhase = index % Math.floor(sampleRate / 2);
    const decay = Math.exp(-beatPhase / 1200);
    const pulse = decay * Math.sin(2 * Math.PI * 1800 * t);
    samples[index * 2] = 0.32 * (chord + 0.25 * pulse + 0.5 * bass);
    samples[index * 2 + 1] = 0.32 * (0.6 * chord + 0.3 * pulse + bass);
  }
  return encodePcm16Wav(sampleRate, 2, samples);
}

// A real instrument-like phrase for audio->MIDI / music transcription: a
// C-major arpeggio of distinct sustained sawtooth notes at 22.05 kHz mono,
// each with an attack/decay envelope so the transcriber sees note onsets.
export function instrumentArpeggioWavBuffer() {
  const sampleRate = 22050;
  const noteSeconds = 0.4;
  const noteSampleCount = Math.round(noteSeconds * sampleRate);
  const arpeggio = [261.63, 329.63, 392.0, 523.25, 392.0, 329.63];
  const samples = [];
  for (const frequency of arpeggio) {
    for (let index = 0; index < noteSampleCount; index += 1) {
      const t = index / sampleRate;
      const progress = index / noteSampleCount;
      let tone = 0;
      for (let harmonic = 1; harmonic <= 8; harmonic += 1) {
        tone += (1 / harmonic) * Math.sin(2 * Math.PI * frequency * harmonic * t);
      }
      const envelope = Math.min(1, progress * 12) * Math.exp(-progress * 1.5);
      samples.push(0.5 * envelope * tone);
    }
  }
  return encodePcm16Wav(sampleRate, 1, samples);
}

// A real single-staff score IMAGE (grayscale PNG, not MusicXML): five staff
// lines, a clef-like glyph, and a few filled noteheads rasterized into a real
// pixel buffer and zlib-encoded via node:zlib. This is the fixture that fixes
// the OMR input-type bug where the tool row used to be fed MusicXML.
export function scoreImagePngBuffer() {
  const width = 240;
  const height = 80;
  const staffLineRows = [20, 30, 40, 50, 60];
  const noteheads = [
    [70, 50],
    [110, 40],
    [150, 30],
    [190, 45],
  ];
  const isStaffLine = (y) => staffLineRows.includes(y);
  const isClef = (x, y) => x >= 14 && x <= 18 && y >= 16 && y <= 64;
  const isNotehead = (x, y) =>
    noteheads.some(([cx, cy]) => {
      const dx = x - cx;
      const dy = y - cy;
      return dx * dx + dy * dy <= 36;
    });
  // Each scanline is prefixed by a 0 filter-type byte.
  const raw = Buffer.alloc(height * (width + 1));
  let offset = 0;
  for (let y = 0; y < height; y += 1) {
    raw[offset] = 0;
    offset += 1;
    for (let x = 0; x < width; x += 1) {
      const ink =
        isClef(x, y) ||
        isNotehead(x, y) ||
        (isStaffLine(y) && x >= 8 && x <= width - 8);
      raw[offset] = ink ? 0 : 255;
      offset += 1;
    }
  }
  return encodeGrayscalePng(width, height, raw);
}

function pngChunk(type, data) {
  const typeBuffer = Buffer.from(type, "ascii");
  const lengthBuffer = Buffer.alloc(4);
  lengthBuffer.writeUInt32BE(data.length, 0);
  const crcBuffer = Buffer.alloc(4);
  crcBuffer.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])) >>> 0, 0);
  return Buffer.concat([lengthBuffer, typeBuffer, data, crcBuffer]);
}

function encodeGrayscalePng(width, height, rawScanlines) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 0; // grayscale color type
  ihdr[10] = 0; // compression
  ihdr[11] = 0; // filter
  ihdr[12] = 0; // interlace
  return Buffer.concat([
    signature,
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflateSync(rawScanlines)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

const crc32Table = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buffer) {
  let crc = 0xffffffff;
  for (let index = 0; index < buffer.length; index += 1) {
    crc = crc32Table[(crc ^ buffer[index]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
