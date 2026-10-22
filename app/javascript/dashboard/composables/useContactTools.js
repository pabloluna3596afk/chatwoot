import { computed, toValue } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCaptainState } from './useCaptainState';
import { useCalendarTime } from './useCalendarTime';

const MILLISECONDS_PER_DAY = 24 * 60 * 60 * 1000;

// The registry owns availability, state and actions; rendering is shared by every tool.
export function useContactTools({
  chat,
  inboxAssistant,
  calendarConnected,
  nextEvent,
  now = () => new Date(),
  onOpenCalendar,
}) {
  const { t, locale } = useI18n();
  const { isAiAttended, isEscalated, assistant } = useCaptainState(chat);
  const { formatEventWhen, eventDateKey, todayKey, formatTime } =
    useCalendarTime();
  return computed(() => {
    const captainLegend = isAiAttended.value
      ? t('CONVERSATION_SIDEBAR.RESPONDER.ANSWERING', {
          name: assistant.value?.name || toValue(inboxAssistant)?.name,
        })
      : t('CONVERSATION_SIDEBAR.RESPONDER.ESCALATED');
    const appointment = toValue(nextEvent);
    let captainState = 'hidden';
    if (toValue(inboxAssistant)) {
      captainState = 'idle';
      if (isAiAttended.value) captainState = 'active';
      else if (isEscalated.value) captainState = 'warning';
    }
    let calendarState = 'hidden';
    if (toValue(calendarConnected))
      calendarState = appointment ? 'active' : 'idle';
    let when = '';
    if (appointment) {
      const days =
        (Date.parse(eventDateKey(appointment.start)) -
          Date.parse(todayKey(new Date(toValue(now))))) /
        MILLISECONDS_PER_DAY;
      when =
        days === 0 || days === 1
          ? `${new Intl.RelativeTimeFormat(locale.value, { numeric: 'auto' }).format(days, 'day')} ${formatTime(appointment.start)}`.trim()
          : formatEventWhen(appointment.start, locale.value);
    }
    return [
      {
        key: 'captain',
        icon: 'i-woot-captain',
        tone: 'teal',
        state: captainState,
        label: `Captain · ${isAiAttended.value || isEscalated.value ? captainLegend : t('CONVERSATION_SIDEBAR.RESPONDER.IDLE')}`,
        legend: captainLegend,
        onClick: undefined,
      },
      {
        key: 'calendar',
        icon: 'i-lucide-calendar',
        tone: 'blue',
        state: calendarState,
        label: `${t('CONVERSATION_SIDEBAR.ACCORDION.CALENDAR_EVENTS')} · ${appointment ? formatEventWhen(appointment.start, locale.value) : t('CONVERSATION_SIDEBAR.TOOLS.SCHEDULE')}`,
        legend: appointment
          ? `${when.charAt(0).toLocaleUpperCase(locale.value)}${when.slice(1)} · ${appointment.summary}`
          : '',
        onClick: () => onOpenCalendar(!appointment),
      },
    ];
  });
}
