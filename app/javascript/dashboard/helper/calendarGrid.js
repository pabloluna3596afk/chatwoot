import { zonedParts, HOUR_START, HOUR_END, TIMEZONE } from './calendarTime';

const DAY_MILLISECONDS = 24 * 60 * 60 * 1000;
const DAY_MINUTES = 24 * 60;
export const GRID_STEP_MINUTES = 1;
export const GRID_ROWS_PER_HOUR = 60 / GRID_STEP_MINUTES;
// Grid line numbers are one-based; layout rows are zero-based minutes.
export const gridRowStyle = (row, span) => ({
  gridRow: `${row + 1} / span ${span}`,
});

// Intersect each event with the visible day, then color the interval graph with
// the first free lane. Half-open intervals let adjacent appointments share a lane.
export function layoutDayEvents(
  events,
  dateKey,
  hourStart = HOUR_START,
  hourEnd = HOUR_END,
  timezone = TIMEZONE
) {
  const wallMinute = value => {
    const {
      dateKey: localDate,
      hour,
      minute,
    } = zonedParts(new Date(value), timezone);
    const dayOffset =
      (Date.parse(localDate) - Date.parse(dateKey)) / DAY_MILLISECONDS;
    return dayOffset * DAY_MINUTES + (hour - hourStart) * 60 + minute;
  };
  const gridMinutes = (hourEnd - hourStart) * 60;
  const entries = events
    .filter(event => !event.all_day)
    .map(event => {
      const start = wallMinute(event.start);
      const end = wallMinute(event.end);
      return {
        ...event,
        intervalStart: Math.max(start, 0),
        // A fold can end at an earlier clock reading. Keep its start visible;
        // both occurrences share clock rows and receive separate lanes.
        intervalEnd: Math.min(Math.max(end, start + 1), gridMinutes),
      };
    })
    .filter(event => event.intervalStart < event.intervalEnd)
    .sort(
      (a, b) =>
        a.intervalStart - b.intervalStart ||
        a.intervalEnd - b.intervalEnd ||
        String(a.id).localeCompare(String(b.id))
    );
  const groups = [];
  let group;
  entries.forEach(event => {
    if (!group || event.intervalStart >= group.end) {
      group = { end: event.intervalEnd, events: [], laneEnds: [] };
      groups.push(group);
    }
    let lane = group.laneEnds.findIndex(end => end <= event.intervalStart);
    if (lane < 0) lane = group.laneEnds.length;
    group.laneEnds[lane] = event.intervalEnd;
    group.end = Math.max(group.end, event.intervalEnd);
    const row = Math.min(
      (hourEnd - hourStart) * GRID_ROWS_PER_HOUR - 1,
      Math.round(event.intervalStart / GRID_STEP_MINUTES)
    );
    const endRow = Math.max(
      row + 1,
      Math.round(event.intervalEnd / GRID_STEP_MINUTES)
    );
    group.events.push({ ...event, lane, row, rowSpan: endRow - row });
  });
  return groups.map(item => ({
    lanes: item.laneEnds.map((_, lane) =>
      item.events.filter(event => event.lane === lane)
    ),
    row: Math.min(...item.events.map(event => event.row)),
    endRow: Math.max(...item.events.map(event => event.row + event.rowSpan)),
  }));
}
