import { defineComponent, h } from 'vue';
import MarkdownIt from 'markdown-it';

const linkifier = new MarkdownIt({ linkify: true }).linkify;

// Tokenize only template source. Variable values enter afterwards as Vue slots.
const inline = (text, renderField, isLiteral = false) => {
  function tokenAt(source, field, literal, lineStart) {
    const variable = source.match(/^{{\s*([^}]+?)\s*}}/);
    if (variable)
      return { length: variable[0].length, nodes: field(variable[1]) };
    if (literal) return null;
    const block = lineStart && source.match(/^(- |\* |\d+\. |> )([^\n]*)/);
    if (block) {
      const quote = block[1] === '> ';
      const bullet = ['- ', '* '].includes(block[1]);
      const content = inline(block[2], field);
      const node = quote
        ? h(
            'span',
            {
              class:
                'inline-block max-w-full border-s-2 border-n-slate-8 ps-2 align-top text-n-slate-11',
            },
            content
          )
        : h(
            'span',
            { role: 'list', class: 'inline-block max-w-full align-top' },
            [
              h('span', { role: 'listitem', class: 'flex gap-2' }, [
                h(
                  'span',
                  { 'aria-hidden': 'true' },
                  bullet ? '\u2022' : block[1].trim()
                ),
                h('span', { class: 'min-w-0' }, content),
              ]),
            ]
          );
      return { length: block[0].length, nodes: [node] };
    }
    const url =
      /^https?:\/\//.test(source) &&
      linkifier.matchAtStart(source.split('{{')[0]);
    if (url)
      return {
        length: url.lastIndex,
        nodes: [
          h(
            'a',
            {
              href: url.url,
              target: '_blank',
              rel: 'noopener noreferrer',
              class: 'text-n-blue-11 underline break-all',
            },
            url.text
          ),
        ],
      };
    const marker = ['```', '`', '*', '_', '~'].find(value =>
      source.startsWith(value)
    );
    if (!marker || !source[marker.length] || /\s/.test(source[marker.length]))
      return null;
    let end = -1;
    let cursor = marker.length;
    while (cursor < source.length && end === -1) {
      const codeMarker = source.startsWith('```', cursor) ? '```' : '`';
      const codeEnd =
        !marker.includes('`') && source.startsWith(codeMarker, cursor)
          ? source.indexOf(codeMarker, cursor + codeMarker.length)
          : -1;
      if (codeEnd !== -1) cursor = codeEnd + codeMarker.length;
      else if (
        source.startsWith(marker, cursor) &&
        !/\s/.test(source[cursor - 1])
      )
        end = cursor;
      else cursor += 1;
    }
    if (end === -1) return null;
    const code = marker.includes('`');
    const tag = code ? 'code' : { '*': 'strong', _: 'em', '~': 's' }[marker];
    return {
      length: end + marker.length,
      nodes: [
        h(
          tag,
          { class: code ? 'font-mono whitespace-pre-wrap' : undefined },
          inline(source.slice(marker.length, end), field, code)
        ),
      ],
    };
  }
  const nodes = [];
  let offset = 0;
  while (offset < text.length) {
    const rest = text.slice(offset);
    const token = tokenAt(
      rest,
      renderField,
      isLiteral,
      offset === 0 || text[offset - 1] === '\n'
    );
    nodes.push(...(token ? token.nodes : [text[offset]]));
    offset += token ? token.length : 1;
  }
  return nodes;
};

export default defineComponent({
  name: 'WhatsAppText',
  props: { text: { type: String, default: '' } },
  setup(props, { slots }) {
    return () =>
      h(
        'div',
        { class: 'whitespace-pre-wrap leading-[1.5]' },
        inline(props.text, key => slots.field?.({ key }) || [`{{${key}}}`])
      );
  },
});
