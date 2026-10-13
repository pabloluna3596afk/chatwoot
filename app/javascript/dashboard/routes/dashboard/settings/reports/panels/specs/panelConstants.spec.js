import {
  panelRangeToDates,
  panelRangeToPickerDates,
  panelPickerRangeToUnix,
  panelReportingToday,
} from '../panelConstants';

describe('panel date presets (D1)', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-12T02:00:00Z'));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it.each([
    ['today', '2026-10-11T05:00:00Z', '2026-10-12T04:59:59Z'],
    ['yesterday', '2026-10-10T05:00:00Z', '2026-10-11T04:59:59Z'],
    ['last_7_days', '2026-10-05T05:00:00Z', '2026-10-12T04:59:59Z'],
    ['last_30_days', '2026-09-12T05:00:00Z', '2026-10-12T04:59:59Z'],
  ])(
    'matches server boundaries for %s in the account timezone',
    (preset, since, until) => {
      const panel = {
        date_preset: preset,
        reporting_timezone: 'America/Guayaquil',
      };
      const expected = [since, until].map(
        value => new Date(value).getTime() / 1000
      );
      expect(
        panelRangeToDates(panel).map(date => date.getTime() / 1000)
      ).toEqual(expected);
      expect(
        panelPickerRangeToUnix(
          panelRangeToPickerDates(panel),
          panel.reporting_timezone
        )
      ).toEqual(expected);
    }
  );

  it('uses the effective application timezone supplied by the server', () => {
    const dates = panelRangeToDates({
      date_preset: 'today',
      reporting_timezone: 'Asia/Tokyo',
    });
    expect(dates.map(date => date.toISOString())).toEqual([
      '2026-10-11T15:00:00.000Z',
      '2026-10-12T14:59:59.000Z',
    ]);
  });

  it('counts calendar days across daylight saving changes', () => {
    vi.setSystemTime(new Date('2026-03-09T02:00:00Z'));
    const dates = panelRangeToDates({
      date_preset: 'last_7_days',
      reporting_timezone: 'America/New_York',
    });
    expect(dates.map(date => date.toISOString())).toEqual([
      '2026-03-02T05:00:00.000Z',
      '2026-03-09T03:59:59.000Z',
    ]);
  });

  it('initializes picker presets using the account calendar day', () => {
    const today = panelReportingToday('America/Guayaquil');
    expect([today.getFullYear(), today.getMonth(), today.getDate()]).toEqual([
      2026, 9, 11,
    ]);
  });

  it('converts manual calendar days to account midnights', () => {
    expect(
      panelPickerRangeToUnix(
        [new Date(2026, 9, 5), new Date(2026, 9, 11)],
        'America/Guayaquil'
      )
    ).toEqual([
      new Date('2026-10-05T05:00:00Z').getTime() / 1000,
      new Date('2026-10-12T04:59:59Z').getTime() / 1000,
    ]);
  });

  it('preserves custom timestamps, including zero', () => {
    expect(
      panelRangeToDates({
        date_preset: 'custom',
        custom_since: 0,
        custom_until: 3600,
        reporting_timezone: 'America/Guayaquil',
      }).map(date => date.getTime() / 1000)
    ).toEqual([0, 3600]);
  });
});
