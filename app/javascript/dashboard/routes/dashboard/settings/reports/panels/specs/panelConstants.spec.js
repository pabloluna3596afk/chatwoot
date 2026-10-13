import {
  cleanTableOptions,
  formatPanelMeasure,
  isAdditiveMeasure,
  defaultTableWidget,
  defaultPivotConfig,
  pivotColumnKey,
  parsePivotColumnKey,
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

describe('dynamic table settings', () => {
  it('encodes crossed columns like the backend and keeps blank values distinct from text markers', () => {
    expect(pivotColumnKey('conversations_count', '')).toBe(
      'conversations_count__pv__'
    );
    expect(pivotColumnKey('conversations_count', 'A ~!*()')).toBe(
      'conversations_count__pv__A%20%7E%21%2A%28%29'
    );
    ['', '__blank__', 'A ~!*()', 'ñ / %'].forEach(value => {
      expect(
        parsePivotColumnKey(pivotColumnKey('conversations_count', value)).value
      ).toBe(value);
    });
  });

  it('creates tables with an explicit row dimension', () => {
    expect(defaultPivotConfig()).toEqual({
      row_attribute: 'agent',
      column_attribute: '',
      column_values: [],
      show_row_totals: true,
    });
    expect(defaultTableWidget()).not.toHaveProperty('sort');
    expect(defaultTableWidget().pivot.row_attribute).toBe('agent');
  });

  it('remaps base and expanded references while preserving currency settings', () => {
    const widget = {
      table_kind: 'pivot',
      columns: ['name', 'ca:amount__sum'],
      pivot: { row_attribute: 'agent', column_attribute: 'ca:stage' },
      sort: { column: 'ca:amount__count__pv__A', direction: 'desc' },
      top_n: { limit: 5, column: 'ca:amount__count', include_others: true },
      column_formats: {
        'ca:amount__count': {
          type: 'currency',
          currency_symbol: 'EUR ',
          decimals: 1,
        },
      },
      measure_display: { 'ca:amount__count': 'row_percent' },
    };
    cleanTableOptions(widget, 'ca:amount__count', 'ca:amount__sum');
    expect(widget.sort.column).toBe('ca:amount__sum__pv__A');
    expect(widget.top_n.column).toBe('ca:amount__sum');
    expect(widget.column_formats).toEqual({
      'ca:amount__sum': {
        type: 'currency',
        currency_symbol: 'EUR ',
        decimals: 1,
      },
    });
    expect(widget.measure_display).toEqual({ 'ca:amount__sum': 'row_percent' });
    widget.pivot.column_attribute = '';
    cleanTableOptions(widget);
    expect(widget.sort).toBeUndefined();
    expect(widget.top_n.column).toBe('ca:amount__sum');
  });

  it('clears orphan settings, non-additive displays, contact Others and summary options on detail tables', () => {
    const widget = {
      table_kind: 'pivot',
      columns: ['name', 'contact_ca:amount__avg'],
      sort: { column: 'missing', direction: 'asc' },
      top_n: {
        limit: 5,
        column: 'contact_ca:amount__avg',
        include_others: true,
      },
      column_formats: { missing: { type: 'currency' } },
      measure_display: { 'contact_ca:amount__avg': 'column_percent' },
    };
    cleanTableOptions(widget);
    expect(widget.sort).toBeUndefined();
    expect(widget.column_formats).toEqual({});
    expect(widget.measure_display).toEqual({});
    expect(widget.top_n.include_others).toBe(false);
    widget.table_kind = 'contacts';
    cleanTableOptions(widget);
    expect(widget.top_n).toBeUndefined();
    expect(widget.column_formats).toBeUndefined();
  });

  it.each([
    'conversations_count',
    'resolved_conversations_count',
    'ca:amount__sum',
    'contact_ca:amount__count',
  ])('offers percentages for %s', column => {
    expect(isAdditiveMeasure(column)).toBe(true);
  });
  it.each(['ca:amount__avg', 'ca:amount__min', 'ca:amount__max', 'name'])(
    'does not offer percentages for %s',
    column => {
      expect(isAdditiveMeasure(column)).toBe(false);
    }
  );

  it('formats cells and footers with the same base configuration and retains raw numbers', () => {
    const value = 10.9;
    const config = { type: 'currency', currency_symbol: 'EUR ', decimals: 1 };
    const number = value.toLocaleString(undefined, {
      minimumFractionDigits: 1,
      maximumFractionDigits: 1,
    });
    expect(formatPanelMeasure(value, config)).toBe(`EUR ${number}`);
    expect(formatPanelMeasure(25, { type: 'percent', decimals: 0 })).toBe(
      '25%'
    );
    expect(formatPanelMeasure(value, { type: 'integer' })).toBe('11');
    expect(formatPanelMeasure(null, config)).toBe('—');
    expect(value).toBe(10.9);
  });
});
