export const apiBasePath = '/api';
export const maxInlineOutputLength = 80;
export const models = [
  { modelId: "echo-text", displayName: "Echo Text", family: "text", description: "Returns the input unchanged.", requestShape: [{ name: 'inputText', label: 'Input Text', fieldType: 'text' }] },
  { modelId: "uppercase-text", displayName: "Uppercase Text", family: "text", description: "Transforms input to uppercase.", requestShape: [{ name: 'inputText', label: 'Input Text', fieldType: 'text' }] },
  { modelId: "word-count", displayName: "Word Count", family: "analysis", description: "Returns the number of words in the input.", requestShape: [{ name: 'inputText', label: 'Input Text', fieldType: 'text' }] }
];
