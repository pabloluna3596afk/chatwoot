import { formatInTimeZone, zonedTimeToUtc } from 'date-fns-tz';
import { calendarEventStatus, isCancelledEvent } from './appointmentStatus';

export const TIMEZONE = 'America/Guayaquil';
export const HOUR_START = 8;
export const HOUR_END = 20;
export const SLOT_MINUTES = 30;
const HOUR_MILLISECONDS = 60 * 60 * 1000;
const DST_OFFSET_PROBE_HOURS = 36;

export function addDaysKey(dateKey, amount) {
  const [year, month, day] = dateKey.split('-').map(Number);
  const next = new Date(Date.UTC(year, month - 1, day + amount));
  return next.toISOString().slice(0, 10);
}

export function zonedDateTime(dateKey, hours, minutes, timezone = TIMEZONE) {
  const day = addDaysKey(dateKey, Math.floor(hours / 24));
  const hh = String(hours % 24).padStart(2, '0');
  const mm = String(minutes).padStart(2, '0');
  const wall = `${day}T${hh}:${mm}:00`;
  const guess = zonedTimeToUtc(wall, timezone).getTime();
  // Probe offsets on both sides of a transition. Reject gaps; in a fold pick
  // the earlier instant, matching the server's local-input contract.
  const offsets = [-DST_OFFSET_PROBE_HOURS, 0, DST_OFFSET_PROBE_HOURS].map(
    hoursAway =>
      formatInTimeZone(
        new Date(guess + hoursAway * HOUR_MILLISECONDS),
        timezone,
        'xxx'
      )
  );
  const candidates = [...new Set(offsets)]
    .map(offset => `${wall}${offset}`)
    .filter(
      iso =>
        formatInTimeZone(new Date(iso), timezone, "yyyy-MM-dd'T'HH:mm:ss") ===
        wall
    )
    .sort((a, b) => new Date(a) - new Date(b));
  return candidates[0] || null;
}

export function zonedParts(date = new Date(), timezone = TIMEZONE) {
  const stamp = date.toLocaleString('sv-SE', { timeZone: timezone });
  const [dateKey, time] = stamp.split(' ');
  const [year, month, day] = dateKey.split('-').map(Number);
  const [hour, minute] = time.split(':').map(Number);
  return { year, month, day, hour, minute, dateKey };
}

export function todayKey(date = new Date(), timezone = TIMEZONE) {
  return zonedParts(date, timezone).dateKey;
}

export function eventInstant(iso, timezone = TIMEZONE) {
  if (!iso) return 0;
  if (iso.length <= 10)
    return new Date(zonedDateTime(iso, 0, 0, timezone)).getTime();
  return new Date(iso).getTime();
}

export function compareEventsByStart(a, b, timezone = TIMEZONE) {
  if (a.all_day && !b.all_day) return -1;
  if (!a.all_day && b.all_day) return 1;
  return eventInstant(a.start, timezone) - eventInstant(b.start, timezone);
}

export function eventDateKey(value, timezone = TIMEZONE) {
  if (!value) return '';
  if (value.length <= 10) return value;
  return zonedParts(new Date(value), timezone).dateKey;
}

export function isEventPast(event, now = Date.now(), timezone = TIMEZONE) {
  if (!event) return true;
  if (event.end) return eventInstant(event.end, timezone) <= now;
  if (event.all_day)
    return (
      eventDateKey(event.start, timezone) < todayKey(new Date(now), timezone)
    );
  return eventInstant(event.start, timezone) < now;
}

export function isEventCurrent(event, now = Date.now(), timezone = TIMEZONE) {
  if (!event) return false;
  if (event.all_day)
    return (
      eventDateKey(event.start, timezone) === todayKey(new Date(now), timezone)
    );
  const start = eventInstant(event.start, timezone);
  const end = event.end
    ? eventInstant(event.end, timezone)
    : start + 60 * 60 * 1000;
  return start <= now && now < end;
}

export function nowLinePercent(
  hourStart = HOUR_START,
  hourEnd = HOUR_END,
  date = new Date(),
  timezone = TIMEZONE
) {
  const { hour, minute } = zonedParts(date, timezone);
  const gridStart = hourStart * 60;
  const gridSpan = Math.max((hourEnd - hourStart) * 60, 60);
  const nowMin = hour * 60 + minute;
  if (nowMin < gridStart || nowMin > gridStart + gridSpan) return null;
  return ((nowMin - gridStart) / gridSpan) * 100;
}

export function dayNumberFromKey(dateKey) {
  return Number(dateKey.split('-')[2]) || 0;
}

export function startOfWeekKey(date = new Date(), timezone = TIMEZONE) {
  const { dateKey } = zonedParts(date, timezone);
  const [year, month, day] = dateKey.split('-').map(Number);
  const weekday = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
  const diff = weekday === 0 ? -6 : 1 - weekday;
  return addDaysKey(dateKey, diff);
}

export function weekDays(weekStartKey) {
  return Array.from({ length: 7 }, (_, index) =>
    addDaysKey(weekStartKey, index)
  );
}

export function weekBoundsIso(weekStartKey, days = 7, timezone = TIMEZONE) {
  return {
    timeMin: zonedDateTime(weekStartKey, 0, 0, timezone),
    timeMax: zonedDateTime(addDaysKey(weekStartKey, days), 0, 0, timezone),
  };
}

export function formatTime(value, timezone = TIMEZONE) {
  if (!value || value.length <= 10) return '';
  const { hour, minute } = zonedParts(new Date(value), timezone);
  return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

export function formatDayLabel(dateKey, locale, timezone = TIMEZONE) {
  const date = new Date(zonedDateTime(dateKey, 12, 0, timezone));
  return date.toLocaleDateString(locale, {
    timeZone: timezone,
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  });
}

// "mar, 15 ene · 10:15" in the calendar's timezone.
export function formatEventWhen(value, locale, timezone = TIMEZONE) {
  if (!value) return '';
  const dateKey = eventDateKey(value, timezone);
  const time = formatTime(value, timezone);
  return time
    ? `${formatDayLabel(dateKey, locale, timezone)} · ${time}`
    : formatDayLabel(dateKey, locale, timezone);
}

export function isUpcomingEvent(event, now = Date.now(), timezone = TIMEZONE) {
  return (
    !isCancelledEvent(event) &&
    eventInstant(event.end || event.start, timezone) >= now
  );
}

export function formatWeekdayMonth(dateKey, locale, timezone = TIMEZONE) {
  const date = new Date(zonedDateTime(dateKey, 12, 0, timezone));
  const weekday = date.toLocaleDateString(locale, {
    timeZone: timezone,
    weekday: 'short',
  });
  const month = date.toLocaleDateString(locale, {
    timeZone: timezone,
    month: 'short',
  });
  return `${weekday}, ${month}`;
}

export function slotFromClick(
  clientY,
  columnTop,
  columnHeight,
  hourStart = HOUR_START,
  hourEnd = HOUR_END
) {
  const ratio = Math.min(
    Math.max((clientY - columnTop) / columnHeight, 0),
    0.999
  );
  const totalMinutes = Math.floor(ratio * (hourEnd - hourStart) * 60);
  const snapped = Math.floor(totalMinutes / SLOT_MINUTES) * SLOT_MINUTES;
  const hours = hourStart + Math.floor(snapped / 60);
  const minutes = snapped % 60;
  return { hours, minutes };
}

export function dateAndTimeParts(iso, timezone = TIMEZONE) {
  if (!iso) {
    const now = zonedParts(new Date(), timezone);
    return {
      date: now.dateKey,
      time: `${String(now.hour).padStart(2, '0')}:${String(now.minute).padStart(2, '0')}`,
    };
  }
  if (iso.length <= 10) return { date: iso, time: '09:00' };
  const parts = zonedParts(new Date(iso), timezone);
  return {
    date: parts.dateKey,
    time: `${String(parts.hour).padStart(2, '0')}:${String(parts.minute).padStart(2, '0')}`,
  };
}

export function durationMinutes(startIso, endIso) {
  if (!startIso || !endIso) return SLOT_MINUTES;
  const diff =
    (new Date(endIso).getTime() - new Date(startIso).getTime()) / 60000;
  return diff > 0 ? diff : SLOT_MINUTES;
}

export function addMinutesToTime(time, minutesToAdd) {
  const [hours, minutes] = (time || '09:00').split(':').map(Number);
  const total = hours * 60 + minutes + minutesToAdd;
  const wrapped = ((total % (24 * 60)) + 24 * 60) % (24 * 60);
  return `${String(Math.floor(wrapped / 60)).padStart(2, '0')}:${String(wrapped % 60).padStart(2, '0')}`;
}

// Retain an existing explicit offset when its displayed civil fields are unchanged.
// This makes editing the second occurrence of a repeated hour lossless.
export function rangeFromStartEnd(
  date,
  startTime,
  endTime,
  timezone = TIMEZONE,
  original = {}
) {
  const instantFor = (value, time) => {
    if (!date || !time) return null;
    const parts = value && dateAndTimeParts(value, timezone);
    if (parts?.date === date && parts.time === time) return value;
    const [hours, minutes] = time.split(':').map(Number);
    return zonedDateTime(date, hours, minutes, timezone);
  };
  return {
    start: instantFor(original.start, startTime),
    end: instantFor(original.end, endTime),
  };
}

export function rangeFromParts(date, time, duration, timezone = TIMEZONE) {
  const [hours, minutes] = time.split(':').map(Number);
  const total = hours * 60 + minutes + duration;
  return {
    start: zonedDateTime(date, hours, minutes, timezone),
    end: zonedDateTime(
      addDaysKey(date, Math.floor(total / 1440)),
      Math.floor((total % 1440) / 60),
      total % 60,
      timezone
    ),
  };
}

export function calendarEventTooltip(event, t, timezone = TIMEZONE) {
  const time = event.all_day
    ? t('SIDEBAR.CALENDAR_PAGE.ALL_DAY')
    : `${formatTime(event.start, timezone)} – ${formatTime(event.end, timezone)}`;
  const status = t(
    `SIDEBAR.CALENDAR_PAGE.STATUS.${calendarEventStatus(event).toUpperCase()}`
  );
  return `${event.summary}\n${time}\n${status}`;
}
