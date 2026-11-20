import DOMPurify from 'dompurify';

const WORD_CHARACTER = '[\\p{L}\\p{M}\\p{N}_]';

const escapeRegExp = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const namePattern = name => {
  const escapedName = escapeRegExp(name);
  const startsWithWordCharacter = /^[\p{L}\p{M}\p{N}_]/u.test(name);
  const endsWithWordCharacter = /[\p{L}\p{M}\p{N}_]$/u.test(name);
  const leftBoundary = startsWithWordCharacter ? `(?<!${WORD_CHARACTER})` : '';
  const rightBoundary = endsWithWordCharacter ? `(?!${WORD_CHARACTER})` : '';

  return new RegExp(`${leftBoundary}${escapedName}${rightBoundary}`, 'u');
};

const textNodes = root => {
  const walker = root.ownerDocument.createTreeWalker(
    root,
    NodeFilter.SHOW_TEXT
  );
  const nodes = [];
  let node = walker.nextNode();

  while (node) {
    nodes.push(node);
    node = walker.nextNode();
  }

  return nodes;
};

const wrapFirstMatch = (root, name) => {
  const pattern = namePattern(name);

  textNodes(root).some(node => {
    if (node.parentElement?.closest('b.nm')) {
      return false;
    }

    const match = pattern.exec(node.textContent);
    if (!match) {
      return false;
    }

    const before = node.textContent.slice(0, match.index);
    const after = node.textContent.slice(match.index + name.length);
    const bold = root.ownerDocument.createElement('b');
    bold.className = 'nm font-semibold text-n-slate-12';
    bold.textContent = name;

    node.replaceWith(
      root.ownerDocument.createTextNode(before),
      bold,
      root.ownerDocument.createTextNode(after)
    );
    return true;
  });
};

export const highlightActivityNames = (html, names) => {
  if (!Array.isArray(names) || names.length === 0) {
    return html;
  }

  const safeHtml = DOMPurify.sanitize(html || '');
  const documentRoot = new DOMParser().parseFromString(safeHtml, 'text/html');
  const root = documentRoot.body;

  names
    .filter(name => typeof name === 'string' && name.length > 0)
    .forEach(name => wrapFirstMatch(root, name));

  return root.innerHTML;
};
