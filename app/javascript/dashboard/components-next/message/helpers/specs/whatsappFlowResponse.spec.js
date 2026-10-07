import {
  buildFlowResponseEntries,
  formatFlowResponseLabel,
  formatFlowResponseValue,
  flowResponseToText,
} from '../whatsappFlowResponse';

describe('whatsappFlowResponse', () => {
  it('humanizes original snake case and camel case keys', () => {
    expect(formatFlowResponseLabel('home_city')).toBe('Home City');
    expect(formatFlowResponseLabel('appointmentDate')).toBe('Appointment Date');
  });

  it('formats empty and primitive answers and arrays', () => {
    expect(formatFlowResponseValue(null)).toBe('\u2014');
    expect(formatFlowResponseValue('')).toBe('\u2014');
    expect(formatFlowResponseValue(false)).toBe('false');
    expect(formatFlowResponseValue(3)).toBe('3');
    expect(formatFlowResponseValue(['morning', 'afternoon'])).toBe(
      'morning, afternoon'
    );
  });

  it('uses metadata titles for scalar and multiple choices', () => {
    const metadata = {
      fields: [
        {
          key: 'interests',
          label: 'Interests',
          type: 'checkbox',
          options: [{ id: 'a', title: 'Advice' }],
        },
        {
          key: 'channel',
          label: 'Contact via',
          type: 'radio',
          options: [{ id: 'wa', title: 'WhatsApp' }],
        },
      ],
    };
    expect(
      buildFlowResponseEntries(
        { interests: ['a', 'other'], channel: 'wa' },
        metadata
      )
    ).toEqual([
      {
        key: 'interests',
        label: 'Interests',
        value: 'Advice, other',
        chips: ['Advice', 'other'],
      },
      { key: 'channel', label: 'Contact via', value: 'WhatsApp' },
    ]);
  });

  it('hides sensitive keys at every depth, including objects within arrays', () => {
    const entries = buildFlowResponseEntries({
      flow_token: 'hidden',
      flowToken: 'hidden',
      otp_code: 'hidden',
      password: 'hidden',
      appointment: { day: 'Monday', secret: 'hidden' },
      list: [{ value: 'ok', passcode: 'hidden' }],
    });
    expect(entries.map(entry => entry.key)).toEqual([
      'appointment_day',
      'list',
    ]);
    expect(flowResponseToText(entries)).not.toContain('hidden');
  });

  it('replaces photos and documents with localized plain rows', () => {
    const fields = ['photo', 'document'].map(type => ({
      key: type,
      label: type,
      type,
    }));
    const entries = buildFlowResponseEntries(
      { photo: [{ media_id: 'hidden' }], document: { url: 'hidden' } },
      { fields },
      'File received'
    );
    expect(entries.map(entry => entry.value)).toEqual([
      'File received',
      'File received',
    ]);
    expect(flowResponseToText(entries, 'Sales')).toBe(
      'Sales\nphoto: File received\ndocument: File received'
    );
  });

  it('copies without a name when metadata is absent', () => {
    expect(
      flowResponseToText(
        buildFlowResponseEntries({ home_city: 'Quito', consent: false })
      )
    ).toBe('Home City: Quito\nConsent: false');
  });

  it('has no structured entries for old messages', () => {
    expect(buildFlowResponseEntries(undefined)).toEqual([]);
  });
});
