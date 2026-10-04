const HIDDEN_KEYS = ['flow_token'];
const HIDDEN_KEY_PATTERN = /password|passcode|otp|secret/i;

export const formatFlowResponseLabel = key =>
  key
    .replace(/([a-z\d])([A-Z])/g, '$1 $2')
    .replace(/[_-]+/g, ' ')
    .replace(/\b\w/g, character => character.toUpperCase());

export const formatFlowResponseValue = value => {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'object') return JSON.stringify(value, null, 2);

  return String(value);
};

const isHidden = key =>
  HIDDEN_KEYS.includes(key) || HIDDEN_KEY_PATTERN.test(key);

const isPlainObject = value =>
  value && typeof value === 'object' && !Array.isArray(value);

// A nested answer ({ appointment: { day: 'Monday' } }) becomes one row per field ("Appointment Day").
const flatten = (response, prefix = '') =>
  Object.entries(response).flatMap(([key, value]) => {
    const path = prefix ? `${prefix}_${key}` : key;
    if (isHidden(key)) return [];
    if (isPlainObject(value) && Object.keys(value).length)
      return flatten(value, path);
    return [[path, value]];
  });

export const buildFlowResponseEntries = response => {
  const entries = isPlainObject(response)
    ? flatten(response)
    : [['response', response]];

  return entries.map(([key, value]) => ({
    key,
    label: formatFlowResponseLabel(key),
    value: formatFlowResponseValue(value),
  }));
};

// The answers as plain text ("Label: value" per line), to paste them somewhere else.
export const flowResponseToText = entries =>
  entries.map(entry => `${entry.label}: ${entry.value}`).join('\n');
