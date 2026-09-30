import { Buffer } from "node:buffer";
import { readFileSync } from "node:fs";

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

// Phase 7 Sprint 7.33: the MIDI preview's observable signal is the note events
// the renderer decoded, so this fixture carries real notes. The retired literal
// declared a four-byte track and supplied three, so every decoder rejected it,
// and even a repaired empty track would render no notes to observe. Generated
// programmatically, so the bytes stay identical across runs and substrates.
export function tinyMidiBuffer() {
  const ticksPerQuarter = 96;
  const pitches = [60, 64, 67, 72];
  const events = [];
  for (const pitch of pitches) {
    // Delta times stay below 128, so each is a single-byte variable-length
    // quantity and the track needs no multi-byte encoding.
    events.push(0x00, 0x90, pitch, 0x64);
    events.push(ticksPerQuarter, 0x80, pitch, 0x40);
  }
  events.push(0x00, 0xff, 0x2f, 0x00);
  const track = Buffer.from(events);
  const buffer = Buffer.alloc(14 + 8 + track.length);
  buffer.write("MThd", 0, "ascii");
  buffer.writeUInt32BE(6, 4);
  buffer.writeUInt16BE(0, 8);
  buffer.writeUInt16BE(1, 10);
  buffer.writeUInt16BE(ticksPerQuarter, 12);
  buffer.write("MTrk", 14, "ascii");
  buffer.writeUInt32BE(track.length, 18);
  track.copy(buffer, 22);
  return buffer;
}

export function musicXmlBuffer() {
  // OpenSheetMusicDisplay requires a score with declared parts and musical
  // content. An empty score-partwise root is well-formed XML but is not a
  // renderable MusicXML positive control.
  return Buffer.from(
    [
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<score-partwise version="3.1">',
      '  <part-list>',
      '    <score-part id="P1"><part-name>Fixture</part-name></score-part>',
      '  </part-list>',
      '  <part id="P1">',
      '    <measure number="1">',
      '      <attributes>',
      '        <divisions>1</divisions>',
      '        <key><fifths>0</fifths></key>',
      '        <time><beats>4</beats><beat-type>4</beat-type></time>',
      '        <clef><sign>G</sign><line>2</line></clef>',
      '      </attributes>',
      '      <note>',
      '        <pitch><step>C</step><octave>4</octave></pitch>',
      '        <duration>4</duration>',
      '        <type>whole</type>',
      '      </note>',
      '    </measure>',
      '  </part>',
      '</score-partwise>',
    ].join("\n"),
    "utf8",
  );
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

// Phase 4 Sprint 4.48: the genuinely spoken mono 16 kHz whisper.cpp JFK sample,
// shared with the Haskell integration fixture. SHA-256:
// 59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e.
export function speechWavBuffer() {
  return readFileSync(new URL("../../../test/fixtures/speech-jfk.wav", import.meta.url));
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

// A real single-staff score IMAGE (grayscale PNG): a genuine engraved score
// (treble clef, 4/4, two bars of quarter notes) rendered by Verovio from
// MusicXML and rasterized to a 1400px grayscale PNG (interline ~27px) that
// Audiveris transcribes to real MusicXML. The prior synthetic 240x80 staff was
// below Audiveris's interline/resolution threshold and was correctly rejected
// as un-transcribable. Loaded from the committed test/fixtures binary.
export function scoreImagePngBuffer() {
  return readFileSync(new URL("./omr-score.png", import.meta.url));
}
