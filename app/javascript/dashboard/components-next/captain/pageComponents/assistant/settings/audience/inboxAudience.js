export const MAX_ENTRIES = 1000;
export const MAX_ENTRY_LENGTH = 120;

const LIST_KEYS = {
  'Channel::Whatsapp': 'phones',
  'Channel::Sms': 'phones',
  'Channel::TwilioSms': 'phones',
  'Channel::Instagram': 'channel_ids',
  'Channel::FacebookPage': 'channel_ids',
  'Channel::WebWidget': 'emails',
  'Channel::Email': 'emails',
};

export const listKeyForInbox = inbox => LIST_KEYS[inbox.channel_type];

export const cleanLines = text => [
  ...new Set(
    text
      .split(/\r?\n/)
      .map(line => line.trim())
      .filter(Boolean)
  ),
];

export const listError = entries => {
  if (entries.length > MAX_ENTRIES) return 'TOO_MANY';
  if (entries.some(entry => [...entry].length > MAX_ENTRY_LENGTH)) {
    return 'TOO_LONG';
  }
  return '';
};
