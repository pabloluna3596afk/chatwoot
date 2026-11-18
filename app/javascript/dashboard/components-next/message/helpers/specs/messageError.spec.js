import { parseExternalError } from '../messageError';
import enChatlist from 'dashboard/i18n/locale/en/chatlist.json';
import esChatlist from 'dashboard/i18n/locale/es/chatlist.json';

const channels = {
  'Channel::Whatsapp': 'WHATSAPP',
  'Channel::FacebookPage': 'FACEBOOK',
  'Channel::Instagram': 'INSTAGRAM',
  'Channel::Telegram': 'TELEGRAM',
  'Channel::TwilioSms': 'TWILIO',
  'Channel::Sms': 'SMS',
};

describe('parseExternalError', () => {
  it.each(Object.entries(channels))(
    'parses all provider formats for %s',
    (channelType, channel) => {
      expect(
        parseExternalError('(#131047) Re-engagement message', channelType)
      ).toEqual({
        code: '131047',
        key: `CHAT_LIST.SEND_ERRORS.${channel}.131047`,
      });
      expect(
        parseExternalError('131047: Re-engagement message', channelType)
      ).toEqual({
        code: '131047',
        key: `CHAT_LIST.SEND_ERRORS.${channel}.131047`,
      });
      expect(parseExternalError('10 - Message failed', channelType)).toEqual({
        code: '10',
        key: `CHAT_LIST.SEND_ERRORS.${channel}.10`,
      });
      expect(
        parseExternalError('403, Forbidden: blocked', channelType)
      ).toEqual({
        code: '403',
        key: `CHAT_LIST.SEND_ERRORS.${channel}.403`,
      });
    }
  );

  it.each(['999999: Unknown error', 'Provider error', '', null, undefined])(
    'preserves an unknown or missing code key for %s',
    raw => {
      const parsed = parseExternalError(raw, 'Channel::Whatsapp');
      expect(parsed.key).toMatch(/^CHAT_LIST\.SEND_ERRORS\.WHATSAPP\./);
      if (typeof raw === 'string' && raw.match(/^\d/)) {
        expect(parsed.code).toBe('999999');
      } else {
        expect(parsed.code).toBeNull();
      }
    }
  );
});

describe('send error translations', () => {
  const documentedCodes = {
    WHATSAPP: [
      '131047',
      '131026',
      '131049',
      '131050',
      '130472',
      '131056',
      '130429',
      '131048',
      '131064',
      '131042',
      '132000',
      '132012',
      '132001',
      '132015',
      '132016',
      '131053',
      '130403',
      '190',
      '0',
      '368',
      '131031',
      '131000',
      '1',
      '2',
      '131016',
      '133004',
    ],
    FACEBOOK: ['10', '2018278', '190', '551'],
    INSTAGRAM: ['10', '2018278', '190', '551'],
    TELEGRAM: ['403'],
    TWILIO: ['63016', '30003', '30005', '30007', '21610'],
    SMS: ['63016', '30003', '30005', '30007', '21610'],
  };

  it('defines every documented code in English and Spanish', () => {
    Object.entries(documentedCodes).forEach(([channel, codes]) => {
      codes.forEach(code => {
        expect(enChatlist.CHAT_LIST.SEND_ERRORS[channel][code]).toBeTruthy();
        expect(esChatlist.CHAT_LIST.SEND_ERRORS[channel][code]).toBeTruthy();
      });
    });
  });
});
