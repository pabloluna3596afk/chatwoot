import {
  buildTimeWindow,
  isValidTimeWindow,
  parseTimeWindow,
  summarizeTimeWindow,
} from '../timeWindow';

describe('parseTimeWindow', () => {
  it('reads hours and weekdays', () => {
    expect(parseTimeWindow('18:00-08:00')).toEqual({
      from: '18:00',
      to: '08:00',
      days: [],
    });
    expect(parseTimeWindow('09:00-13:00|mon,tue')).toEqual({
      from: '09:00',
      to: '13:00',
      days: ['mon', 'tue'],
    });
  });

  it.each([
    undefined,
    null,
    '',
    18,
    '18:00',
    '8:00-18:00',
    '24:00-08:00',
    '18:60-19:00',
    '09:00-09:00',
    '18:00-08:00|',
    '18:00-08:00|lun',
    '18:00-08:00|mon,mon',
    '18:00-08:00|MON',
  ])('rejects %s', value => {
    expect(parseTimeWindow(value)).toBeNull();
  });
});

describe('buildTimeWindow', () => {
  it('stays empty until both times exist', () => {
    expect(buildTimeWindow({ from: '18:00' })).toBe('');
    expect(buildTimeWindow({ to: '08:00', days: ['mon'] })).toBe('');
    expect(buildTimeWindow()).toBe('');
  });

  it('writes weekdays in calendar order whatever the click order was', () => {
    expect(
      buildTimeWindow({ from: '22:00', to: '06:00', days: ['sat', 'fri'] })
    ).toBe('22:00-06:00|fri,sat');
    expect(buildTimeWindow({ from: '18:00', to: '08:00' })).toBe('18:00-08:00');
  });
});

describe('isValidTimeWindow', () => {
  it('accepts a string or the one-item array the payload uses', () => {
    expect(isValidTimeWindow('18:00-08:00')).toBe(true);
    expect(isValidTimeWindow(['18:00-08:00|fri'])).toBe(true);
    expect(isValidTimeWindow('18:00-18:00')).toBe(false);
    expect(isValidTimeWindow([])).toBe(false);
  });
});

describe('summarizeTimeWindow', () => {
  const translate = key =>
    ({
      'AUTOMATION.TIME_WINDOW.SUMMARY_ALL_DAYS': 'Every day',
      'AUTOMATION.TIME_WINDOW.SUMMARY_WEEKDAYS': 'Mon–Fri',
      'DAYS_OF_WEEK.MONDAY': 'Monday',
      'DAYS_OF_WEEK.TUESDAY': 'Tuesday',
      'DAYS_OF_WEEK.FRIDAY': 'Friday',
      'DAYS_OF_WEEK.SATURDAY': 'Saturday',
    })[key] || key;

  it('summarizes empty and fully selected days as every day', () => {
    expect(summarizeTimeWindow('18:00-08:00', translate)).toBe(
      '18:00–08:00 · Every day'
    );
    expect(
      summarizeTimeWindow('18:00-08:00|sun,mon,tue,wed,thu,fri,sat', translate)
    ).toBe('18:00–08:00 · Every day');
  });

  it('summarizes weekdays and selected days in calendar order', () => {
    expect(
      summarizeTimeWindow('09:00-17:00|fri,mon,tue,wed,thu', translate)
    ).toBe('09:00–17:00 · Mon–Fri');
    expect(summarizeTimeWindow('09:00-17:00|sat,fri', translate)).toBe(
      '09:00–17:00 · Fri, Sat'
    );
  });

  it('does not render an invalid saved value', () => {
    expect(summarizeTimeWindow('09:00-09:00', translate)).toBe('');
  });
});
