import { businessTimezoneOptions } from '../../account-details/timezoneOptions';

describe('businessTimezoneOptions', () => {
  afterEach(() => vi.restoreAllMocks());

  it('localizes country names, keeps IANA values and exposes search terms', () => {
    vi.spyOn(Intl, 'supportedValuesOf').mockReturnValue([
      'America/Guayaquil',
      'America/New_York',
    ]);
    const options = businessTimezoneOptions(
      '',
      'es',
      new Date('2026-01-15T12:00:00Z')
    );

    expect(options).toContainEqual({
      value: 'America/Guayaquil',
      label: 'Ecuador (GMT-5) · Guayaquil',
      searchTerms: ['America/Guayaquil', 'Guayaquil', 'Ecuador'],
    });
    expect(options.find(o => o.value === 'America/New_York')).toEqual({
      value: 'America/New_York',
      label: 'Estados Unidos (GMT-5) · New York',
      searchTerms: ['America/New_York', 'New York', 'Estados Unidos'],
    });
  });

  it.each([
    ['2026-01-15T12:00:00Z', 'GMT-5'],
    ['2026-07-15T12:00:00Z', 'GMT-4'],
  ])('calculates the offset with Intl for %s', (date, offset) => {
    vi.spyOn(Intl, 'supportedValuesOf').mockReturnValue(['America/New_York']);
    const option = businessTimezoneOptions('', 'en', new Date(date)).find(
      o => o.value === 'America/New_York'
    );

    expect(option.label).toBe(`United States (${offset}) · New York`);
  });

  it('preserves valid saved aliases missing from the browser list and fractional offsets', () => {
    vi.spyOn(Intl, 'supportedValuesOf').mockReturnValue(['Asia/Kolkata']);
    const options = businessTimezoneOptions(
      'US/Eastern',
      'es',
      new Date('2026-01-15T12:00:00Z')
    );

    expect(options.find(o => o.value === 'US/Eastern').label).toContain(
      'GMT-5'
    );
    expect(options.find(o => o.value === 'Asia/Kolkata').label).toContain(
      'GMT+5:30'
    );
    expect(new Set(options.map(o => o.value)).size).toBe(options.length);
  });
});
