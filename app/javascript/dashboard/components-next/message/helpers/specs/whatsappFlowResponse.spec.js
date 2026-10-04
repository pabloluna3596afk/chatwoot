import {
  buildFlowResponseEntries,
  formatFlowResponseLabel,
  formatFlowResponseValue,
  flowResponseToText,
} from '../whatsappFlowResponse';

describe('whatsappFlowResponse', () => {
  describe('formatFlowResponseLabel', () => {
    it('formats snake case and generated Flow field names', () => {
      expect(formatFlowResponseLabel('flow_token')).toBe('Flow Token');
      expect(formatFlowResponseLabel('screen_0_Rating_0')).toBe(
        'Screen 0 Rating 0'
      );
    });

    it('formats camel case labels', () => {
      expect(formatFlowResponseLabel('appointmentDate')).toBe(
        'Appointment Date'
      );
    });
  });

  describe('formatFlowResponseValue', () => {
    it('formats primitive values', () => {
      expect(formatFlowResponseValue('excellent')).toBe('excellent');
      expect(formatFlowResponseValue(false)).toBe('false');
      expect(formatFlowResponseValue(3)).toBe('3');
    });

    it('formats empty values', () => {
      expect(formatFlowResponseValue(null)).toBe('—');
      expect(formatFlowResponseValue('')).toBe('—');
    });

    it('formats structured values without losing data', () => {
      expect(formatFlowResponseValue({ day: 'Monday' })).toBe(
        '{\n  "day": "Monday"\n}'
      );
      expect(formatFlowResponseValue(['morning', 'afternoon'])).toBe(
        '[\n  "morning",\n  "afternoon"\n]'
      );
    });
  });

  describe('buildFlowResponseEntries', () => {
    it('builds readable answer entries while keeping the flow token as metadata', () => {
      expect(
        buildFlowResponseEntries({
          flow_token: 'correlation-token',
          rating: 'excellent',
          appointment: { day: 'Monday' },
        })
      ).toEqual([
        { key: 'rating', label: 'Rating', value: 'excellent' },
        { key: 'appointment_day', label: 'Appointment Day', value: 'Monday' },
      ]);
    });

    it('hides secrets and shows an empty answer as a dash', () => {
      expect(
        buildFlowResponseEntries({
          city: 'Quito',
          otp_code: '1234',
          notes: '',
        }).map(({ label, value }) => [label, value])
      ).toEqual([
        ['City', 'Quito'],
        ['Notes', '—'],
      ]);
    });

    it('writes the answers as one "Label: value" line each', () => {
      expect(
        flowResponseToText(
          buildFlowResponseEntries({ rating: 'excellent', city: 'Quito' })
        )
      ).toBe('Rating: excellent\nCity: Quito');
    });

    it('displays a raw response as a single readable entry', () => {
      expect(buildFlowResponseEntries('{invalid-json')).toEqual([
        {
          key: 'response',
          label: 'Response',
          value: '{invalid-json',
        },
      ]);
    });
  });
});
