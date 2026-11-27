import { resolveVariablesInMessage } from './editorHelper';

// Preview only: leave the editor's unresolved values intact for server-side Liquid.
export const resolvePreviewText = (content, variables, missing) =>
  resolveVariablesInMessage(content || '', variables).replace(
    /{{[\s\S]*?}}|{%[\s\S]*?%}/g,
    () => `\`${missing}\``
  );

export const formatMacroPreviewValue = (value, variables, t) => {
  if (value === null || value === undefined || value === '') return '';
  if (Array.isArray(value)) {
    return value
      .map(item => formatMacroPreviewValue(item, variables, t))
      .join(', ');
  }
  if (typeof value === 'object') {
    if ('attribute_key' in value) {
      return `${value.attribute_key} = ${formatMacroPreviewValue(value.value, variables, t)}`;
    }
    return Object.entries(value)
      .map(
        ([key, item]) =>
          `${key} = ${formatMacroPreviewValue(item, variables, t)}`
      )
      .join('\n');
  }
  const text = String(value).replace(
    /{{\s*date\.today(?:\s*\|\s*(plus_days|minus_days):\s*(\d+))?\s*}}/g,
    (_, operation, days) =>
      operation
        ? t('CONVERSATION.PICKER.PREVIEW.RELATIVE_DAYS', {
            sign: operation === 'plus_days' ? '+' : '−',
            days,
          })
        : t('CONVERSATION.PICKER.PREVIEW.TODAY')
  );
  return resolvePreviewText(
    text,
    variables,
    t('CONVERSATION.PICKER.PREVIEW.MISSING')
  );
};
