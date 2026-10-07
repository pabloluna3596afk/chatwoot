const HIDDEN_KEY_PATTERN = /flow_?token|password|passcode|otp|secret/i;
const FILE_TYPES = ['photo', 'document'];

export const formatFlowResponseLabel = key =>
  key
    .replace(/([a-z\d])([A-Z])/g, '$1 $2')
    .replace(/[_-]+/g, ' ')
    .replace(/\b\w/g, character => character.toUpperCase());

const isPlainObject = value =>
  value && typeof value === 'object' && !Array.isArray(value);

const visibleValue = value => {
  if (Array.isArray(value)) return value.map(visibleValue);
  if (isPlainObject(value)) {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => !HIDDEN_KEY_PATTERN.test(key))
        .map(([key, item]) => [key, visibleValue(item)])
    );
  }
  return value;
};

export const formatFlowResponseValue = value => {
  if (value === null || value === undefined || value === '') return '—';
  if (Array.isArray(value))
    return value.map(formatFlowResponseValue).join(', ');
  if (typeof value === 'object')
    return JSON.stringify(visibleValue(value), null, 2);

  return String(value);
};

export const buildFlowResponseEntries = (
  response,
  metadata = {},
  fileReceived = ''
) => {
  const fields = metadata.fields ?? [];
  const entries = (answers, prefix = '') =>
    Object.entries(answers).flatMap(([key, value]) => {
      if (HIDDEN_KEY_PATTERN.test(key)) return [];
      const path = prefix ? `${prefix}_${key}` : key;
      const field = fields.find(item => item.key === path);
      const label = field?.label || formatFlowResponseLabel(path);
      if (FILE_TYPES.includes(field?.type)) {
        return [{ key: path, label, value: fileReceived }];
      }
      if (isPlainObject(value) && Object.keys(value).length) {
        return entries(value, path);
      }
      const optionTitle = item =>
        field?.options?.find(option => option.id === item)?.title ?? item;
      if (Array.isArray(value)) {
        const chips = value.map(item =>
          formatFlowResponseValue(optionTitle(item))
        );
        return [{ key: path, label, value: chips.join(', '), chips }];
      }
      return [
        {
          key: path,
          label,
          value: formatFlowResponseValue(optionTitle(value)),
        },
      ];
    });

  return isPlainObject(response) ? entries(response) : [];
};

export const flowResponseToText = (entries, name) =>
  [name, ...entries.map(entry => `${entry.label}: ${entry.value}`)]
    .filter(Boolean)
    .join('\n');
