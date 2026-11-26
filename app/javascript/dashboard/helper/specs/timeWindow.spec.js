import {
  buildTimeWindow,
  isValidTimeWindow,
  parseTimeWindow,
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
