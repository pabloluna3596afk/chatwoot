import {
  buildTimeWindow,
  getTimeWindowState,
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

  it('rehydrates legacy values without days and explicit all-day values', () => {
    expect(parseTimeWindow('18:00-08:00')?.days).toEqual([]);
    expect(
      parseTimeWindow('18:00-08:00|sun,mon,tue,wed,thu,fri,sat')?.days
    ).toHaveLength(7);
  });

  it('keeps equal times readable so the form can show the validation error', () => {
    expect(parseTimeWindow('09:00-09:00')).toEqual({
      from: '09:00',
      to: '09:00',
      days: [],
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
    expect(
      buildTimeWindow({
        from: '09:00',
        to: '18:00',
        days: ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'],
      })
    ).toBe('09:00-18:00');
  });

  it('rejects equal times without writing a value', () => {
    expect(buildTimeWindow({ from: '09:00', to: '09:00' })).toBe('');
    expect(buildTimeWindow({ from: '09:00', to: '18:00' })).toBe('09:00-18:00');
  });
});

describe('getTimeWindowState', () => {
  it.each([
    [{ from: '', to: '' }, 'empty'],
    [{ from: '09:00', to: '' }, 'empty'],
    [{ from: '09:00', to: '09:00' }, 'same'],
    [{ from: '09:00', to: '18:00' }, 'valid'],
  ])('returns %s as %s', (value, expected) => {
    expect(getTimeWindowState(value)).toBe(expected);
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
  const translate = (key, params) => {
    const translated = {
      'AUTOMATION.TIME_WINDOW.SUMMARY_ALL_DAYS': 'Every day',
      'AUTOMATION.TIME_WINDOW.SUMMARY_WEEKDAYS': 'Mon–Fri',
      'AUTOMATION.TIME_WINDOW.SUMMARY_IN': ({ from, to, days }) =>
        `Applies ${from}–${to} · ${days}`,
      'AUTOMATION.TIME_WINDOW.SUMMARY_OUT': ({ from, to, days }) =>
        `Applies outside ${from}–${to} · ${days}`,
      'AUTOMATION.TIME_WINDOW.OVERNIGHT': 'overnight',
      'AUTOMATION.TIME_WINDOW.INBOX_TIME_ZONE': 'inbox time zone',
      'DAYS_OF_WEEK.MONDAY': 'Monday',
      'DAYS_OF_WEEK.TUESDAY': 'Tuesday',
      'DAYS_OF_WEEK.FRIDAY': 'Friday',
      'DAYS_OF_WEEK.SATURDAY': 'Saturday',
    }[key];
    return typeof translated === 'function'
      ? translated(params)
      : translated || key;
  };

  it('summarizes empty and fully selected days as every day', () => {
    expect(summarizeTimeWindow('18:00-08:00', translate)).toBe(
      '18:00–08:00 · Every day'
    );
    expect(
      summarizeTimeWindow('18:00-08:00|sun,mon,tue,wed,thu,fri,sat', translate)
    ).toBe('18:00–08:00 · Every day');
  });

  it('summarizes inside, outside, inbox time zone, and overnight windows', () => {
    expect(
      summarizeTimeWindow('22:00-06:00', translate, { withZone: true })
    ).toBe('Applies 22:00–06:00 · Every day · overnight · inbox time zone');
    expect(
      summarizeTimeWindow('09:00-18:00|mon,tue,wed,thu,fri', translate, {
        negate: true,
        withZone: true,
      })
    ).toBe('Applies outside 09:00–18:00 · Mon–Fri · inbox time zone');
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
