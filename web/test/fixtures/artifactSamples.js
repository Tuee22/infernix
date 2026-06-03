import { Buffer } from "node:buffer";

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
