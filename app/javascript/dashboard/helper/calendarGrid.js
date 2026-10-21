import {
  zonedDateTime,
  zonedParts,
  HOUR_START,
  HOUR_END,
  TIMEZONE,
} from './calendarTime';

const DAY_MILLISECONDS = 24 * 60 * 60 * 1000;
const DAY_MINUTES = 24 * 60;
const MINUTE_MILLISECONDS = 60 * 1000;
const HOUR_MILLISECONDS = 60 * MINUTE_MILLISECONDS;
const TRANSITION_PROBE_HOURS = 18;

// Find the offset transition near this civil day, once for the entire column.
// Noon avoids using a potentially nonexistent midnight as the anchor.
function dayTransition(dateKey, timezone) {
  const noon = new Date(zonedDateTime(dateKey, 12, 0, timezone)).getTime();
  const offsetAt = instant => {
    const { year, month, day, hour, minute } = zonedParts(
      new Date(instant),
      timezone
    );
    return (
      Date.UTC(year, month - 1, day, hour, minute) -
      Math.floor(instant / MINUTE_MILLISECONDS) * MINUTE_MILLISECONDS
    );
  };
  let before = noon - TRANSITION_PROBE_HOURS * HOUR_MILLISECONDS;
  let after = noon + TRANSITION_PROBE_HOURS * HOUR_MILLISECONDS;
  const initialOffset = offsetAt(before);
  if (initialOffset === offsetAt(after)) return null;
  while (after - before > MINUTE_MILLISECONDS) {
    const middle =
      Math.floor((before + after) / 2 / MINUTE_MILLISECONDS) *
      MINUTE_MILLISECONDS;
    if (offsetAt(middle) === initialOffset) before = middle;
    else after = middle;
  }
  return after;
}
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
  const transition = dayTransition(dateKey, timezone);
  const gridMinutes = (hourEnd - hourStart) * 60;
  const entries = events
    .filter(event => !event.all_day)
    .flatMap(event => {
      const start = new Date(event.start).getTime();
      const end = new Date(event.end).getTime();
      const boundaries =
        transition && start < transition && transition < end
          ? [start, transition, end]
          : [start, end];
      // Each piece has a constant UTC offset. A fold produces two pieces on
      // the same clock rows; a gap leaves its nonexistent clock rows empty.
      return boundaries.slice(0, -1).map((instant, index) => ({
        ...event,
        intervalStart: Math.max(wallMinute(instant), 0),
        intervalEnd: Math.min(
          wallMinute(boundaries[index + 1] - 1) + 1,
          gridMinutes
        ),
      }));
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
