// Segment the source before substitution: identical example words outside a variable stay plain text.
export const variableSegments = (text, examples) => {
  const segments = [];
  let cursor = 0;
  [...text.matchAll(/\{\{\s*([^{}\s]+)\s*\}\}/g)].forEach(match => {
    if (match.index > cursor)
      segments.push({ text: text.slice(cursor, match.index), variable: false });
    const value = examples[match[1]];
    const filled = value !== undefined && value !== '';
    segments.push({ text: filled ? value : match[0], variable: filled });
    cursor = match.index + match[0].length;
  });
  if (cursor < text.length)
    segments.push({ text: text.slice(cursor), variable: false });
  return segments;
};
