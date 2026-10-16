import { gridRowStyle, layoutDayEvents } from '../calendarGrid';

const date = '2030-01-15';
const event = (id, start, end) => ({
  id,
  summary: id,
  start: `${date}T${start}:00-05:00`,
  end: `${date}T${end}:00-05:00`,
});

describe('layoutDayEvents', () => {
  it('puts simultaneous appointments side by side in stable order', () => {
    const events = [event('b', '10:00', '10:30'), event('a', '10:00', '10:30')];
    const result = layoutDayEvents(events, date);
    expect(result[0].lanes.map(lane => lane[0].id)).toEqual(['a', 'b']);
    expect(layoutDayEvents([...events].reverse(), date)).toEqual(result);
    expect(result[0].lanes[0][0]).toMatchObject({ row: 120, rowSpan: 30 });
    expect(
      gridRowStyle(result[0].row, result[0].endRow - result[0].row)
    ).toEqual({
      gridRow: '121 / span 30',
    });
  });

  it('uses three lanes for a triple overlap', () => {
    const result = layoutDayEvents(
      ['a', 'b', 'c'].map(id => event(id, '10:00', '10:30')),
      date
    );
    expect(result[0].lanes).toHaveLength(3);
  });

  it('keeps a bridged cluster together and reuses free lanes', () => {
    const result = layoutDayEvents(
      [
        event('a', '10:00', '10:30'),
        event('bridge', '10:15', '11:15'),
        event('c', '11:00', '11:30'),
      ],
      date
    );
    expect(result).toHaveLength(1);
    expect(result[0].lanes.map(lane => lane.map(item => item.id))).toEqual([
      ['a', 'c'],
      ['bridge'],
    ]);
  });

  it('does not overlap adjacent appointments, including off-quarter starts', () => {
    const result = layoutDayEvents(
      [event('a', '10:10', '10:40'), event('b', '10:40', '11:10')],
      date
    );
    expect(result).toHaveLength(2);
    expect(result[0].endRow).toBe(result[1].row);
    expect(result.every(group => group.lanes.length === 1)).toBe(true);
    expect(result[0].lanes[0][0].rowSpan).toBe(30);
  });

  it('does not move events outside the visible range to the opening hour', () => {
    expect(
      layoutDayEvents(
        [event('early', '02:00', '02:30'), event('late', '21:00', '21:30')],
        date
      )
    ).toEqual([]);
  });

  it('intersects overnight events with each visible day', () => {
    const overnight = {
      id: 'night',
      start: '2030-01-14T23:30:00-05:00',
      end: '2030-01-15T00:30:00-05:00',
    };
    const result = layoutDayEvents([overnight], date, 0, 8);
    expect(result[0].lanes[0][0]).toMatchObject({ row: 0, rowSpan: 30 });
    expect(
      layoutDayEvents([{ ...overnight, all_day: true }], date, 0, 8)
    ).toEqual([]);
  });
});

it('keeps short adjacent meetings separate at minute precision', () => {
  const result = layoutDayEvents(
    [event('a', '10:01', '10:06'), event('b', '10:06', '10:11')],
    date
  );
  expect(result[0].endRow).toBe(result[1].row);
  expect(result[0].lanes[0][0]).toMatchObject({ row: 121, rowSpan: 5 });
});
