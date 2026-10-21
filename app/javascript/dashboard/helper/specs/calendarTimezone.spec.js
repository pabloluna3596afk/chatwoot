import { describe, expect, it } from 'vitest';
import {
  formatTime,
  dateAndTimeParts,
  weekBoundsIso,
  zonedDateTime,
  eventDateKey,
  formatEventWhen,
  rangeFromStartEnd,
  rangeFromParts,
} from '../calendarTime';
import { layoutDayEvents } from '../calendarGrid';

describe('account appointment timezone', () => {
  it.each(['America/Guayaquil', 'America/New_York'])(
    'round trips 10:00 in %s',
    zone => {
      const start = zonedDateTime('2030-07-15', 10, 0, zone);
      expect(formatTime(start, zone)).toBe('10:00');
      expect(dateAndTimeParts(start, zone)).toEqual({
        date: '2030-07-15',
        time: '10:00',
      });
      expect(new Date(start).toISOString()).toBe(
        zone === 'America/New_York'
          ? '2030-07-15T14:00:00.000Z'
          : '2030-07-15T15:00:00.000Z'
      );
    }
  );
  it('uses different offsets at the two weekly boundaries across DST', () => {
    const bounds = weekBoundsIso('2030-03-04', 7, 'America/New_York');
    expect(new Date(bounds.timeMin).toISOString()).toBe(
      '2030-03-04T05:00:00.000Z'
    );
    expect(new Date(bounds.timeMax).toISOString()).toBe(
      '2030-03-11T04:00:00.000Z'
    );
  });
  it('rejects nonexistent hours and chooses the earlier occurrence of repeated hours', () => {
    expect(zonedDateTime('2030-03-10', 2, 30, 'America/New_York')).toBeNull();
    expect(
      new Date(
        zonedDateTime('2030-11-03', 1, 30, 'America/New_York')
      ).toISOString()
    ).toBe('2030-11-03T05:30:00.000Z');
  });
  it('groups and lays out the same instant in the account day at the year boundary', () => {
    const event = {
      id: 'a',
      start: '2031-01-01T00:30:00Z',
      end: '2031-01-01T01:00:00Z',
    };
    expect(eventDateKey(event.start, 'Europe/Madrid')).toBe('2031-01-01');
    expect(
      layoutDayEvents([event], '2031-01-01', 0, 24, 'Europe/Madrid')[0].row
    ).toBe(90);
  });
  it('keeps all-day civil dates in both languages and timezones', () => {
    ['America/Guayaquil', 'America/New_York'].forEach(zone => {
      expect(eventDateKey('2031-01-01', zone)).toBe('2031-01-01');
      expect(formatEventWhen('2031-01-01', 'en', zone)).toContain('1');
      expect(formatEventWhen('2031-01-01', 'es', zone)).toContain('1');
    });
  });
});

it('retains the second DST occurrence on an unchanged edit', () => {
  const original = {
    start: '2030-11-03T01:30:00-05:00',
    end: '2030-11-03T02:00:00-05:00',
  };
  expect(
    rangeFromStartEnd(
      '2030-11-03',
      '01:30',
      '02:00',
      'America/New_York',
      original
    )
  ).toEqual(original);
});

it('places 10:00 on its clock row even when the visible grid crosses DST', () => {
  const event = {
    id: 'a',
    start: '2030-03-10T10:00:00-04:00',
    end: '2030-03-10T10:30:00-04:00',
  };
  const groups = layoutDayEvents(
    [event],
    '2030-03-10',
    0,
    23,
    'America/New_York'
  );
  expect(groups[0].lanes[0][0]).toMatchObject({ row: 600, rowSpan: 30 });
});

it('keeps two repeated-hour appointments in separate visual lanes', () => {
  const events = ['-04:00', '-05:00'].map((offset, id) => ({
    id,
    start: `2030-11-03T01:30:00${offset}`,
    end: `2030-11-03T01:45:00${offset}`,
  }));
  const groups = layoutDayEvents(
    events,
    '2030-11-03',
    0,
    23,
    'America/New_York'
  );
  expect(groups[0].lanes).toHaveLength(2);
  expect(groups[0].row).toBe(90);
});

it('advances the civil date when a duration crosses midnight', () => {
  const range = rangeFromParts('2030-12-31', '23:45', 30, 'America/New_York');
  expect(dateAndTimeParts(range.end, 'America/New_York')).toEqual({
    date: '2031-01-01',
    time: '00:15',
  });
});

it('leaves the missing opening hour empty instead of shifting the visible day', () => {
  const event = {
    id: 'a',
    start: '2030-03-10T03:00:00-04:00',
    end: '2030-03-10T03:30:00-04:00',
  };
  expect(
    layoutDayEvents([event], '2030-03-10', 2, 20, 'America/New_York')[0].row
  ).toBe(60);
});
