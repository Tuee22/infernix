"use strict";

// Browser WebSocket message events surface the payload as a String when
// the binary type is "blob" and the server sent text. We simply assert
// the string here; if the payload is a Blob/ArrayBuffer the decode
// downstream will surface the diagnostic.
export const unsafeAsString = function (value) {
  return String(value);
};
