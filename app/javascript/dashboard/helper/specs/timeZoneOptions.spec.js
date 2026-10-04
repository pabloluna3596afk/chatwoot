import {
  DEFAULT_ACCOUNT_TIMEZONE,
  accountTimeZoneOptions,
} from '../timeZoneOptions';

describe('accountTimeZoneOptions', () => {
  it('always lists the default zone of the account', () => {
    const values = accountTimeZoneOptions().map(option => option.value);

    expect(values).toContain(DEFAULT_ACCOUNT_TIMEZONE);
  });

  it('keeps a saved zone the browser does not list', () => {
    const values = accountTimeZoneOptions('Etc/Custom').map(
      option => option.value
    );

    expect(values).toContain('Etc/Custom');
  });

  it('has no repeated zones and readable labels', () => {
    const options = accountTimeZoneOptions('America/Guayaquil');
    const values = options.map(option => option.value);

    expect(new Set(values).size).toBe(values.length);
    expect(options.find(o => o.value === 'America/Los_Angeles').label).toBe(
      'America/Los Angeles'
    );
  });
});
