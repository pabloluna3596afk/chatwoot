import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import * as calendarTime from 'dashboard/helper/calendarTime';

export function useCalendarTime() {
  const { currentAccount } = useAccount();
  const timezone = computed(
    () => currentAccount.value?.calendar_timezone || calendarTime.TIMEZONE
  );
  return {
    timezone,
    todayKey: date => calendarTime.todayKey(date, timezone.value),
    eventDateKey: value => calendarTime.eventDateKey(value, timezone.value),
    compareEventsByStart: (a, b) =>
      calendarTime.compareEventsByStart(a, b, timezone.value),
    isEventPast: (event, now) =>
      calendarTime.isEventPast(event, now, timezone.value),
    startOfWeekKey: date => calendarTime.startOfWeekKey(date, timezone.value),
    weekBoundsIso: (weekStartKey, days) =>
      calendarTime.weekBoundsIso(weekStartKey, days, timezone.value),
    formatTime: value => calendarTime.formatTime(value, timezone.value),
    formatDayLabel: (dateKey, locale) =>
      calendarTime.formatDayLabel(dateKey, locale, timezone.value),
    formatEventWhen: (value, locale) =>
      calendarTime.formatEventWhen(value, locale, timezone.value),
    isUpcomingEvent: (event, now) =>
      calendarTime.isUpcomingEvent(event, now, timezone.value),
    formatWeekdayMonth: (dateKey, locale) =>
      calendarTime.formatWeekdayMonth(dateKey, locale, timezone.value),
    dateAndTimeParts: iso => calendarTime.dateAndTimeParts(iso, timezone.value),
    rangeFromStartEnd: (date, startTime, endTime, original) =>
      calendarTime.rangeFromStartEnd(
        date,
        startTime,
        endTime,
        timezone.value,
        original
      ),
    calendarEventTooltip: (event, t) =>
      calendarTime.calendarEventTooltip(event, t, timezone.value),
    nowLinePercent: (hourStart, hourEnd, date) =>
      calendarTime.nowLinePercent(hourStart, hourEnd, date, timezone.value),
  };
}
