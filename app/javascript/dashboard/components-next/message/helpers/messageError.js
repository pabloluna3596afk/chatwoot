const CHANNELS = {
  'Channel::Whatsapp': 'WHATSAPP',
  'Channel::FacebookPage': 'FACEBOOK',
  'Channel::Instagram': 'INSTAGRAM',
  'Channel::Telegram': 'TELEGRAM',
  'Channel::TwilioSms': 'TWILIO',
  'Channel::Sms': 'SMS',
};

const ERROR_CODE_PATTERNS = [/^\(#(\d+)\)/, /^(\d+):/, /^(\d+)\s+-/, /^(\d+),/];

export function parseExternalError(raw, channelType) {
  const channel = CHANNELS[channelType] || 'UNKNOWN';
  const errorText = typeof raw === 'string' ? raw.trim() : '';
  const code = ERROR_CODE_PATTERNS.map(pattern =>
    errorText.match(pattern)
  ).find(match => match)?.[1];

  return {
    code: code || null,
    key: `CHAT_LIST.SEND_ERRORS.${channel}.${code || 'UNKNOWN'}`,
  };
}
