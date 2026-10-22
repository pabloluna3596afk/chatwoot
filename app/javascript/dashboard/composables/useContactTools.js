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
  const { isAiAttended, isEscalated, isWaitingForCustomer, assistant } =
    useCaptainState(chat);
  const { formatEventWhen, eventDateKey, todayKey, formatTime } =
    useCalendarTime();
  return computed(() => {
    const captainName = {
      name: assistant.value?.name || toValue(inboxAssistant)?.name || 'Captain',
    };
    let captainLegend = t(
      'CONVERSATION_SIDEBAR.TOOLS.CAPTAIN_ESCALATED',
      captainName
    );
    if (isAiAttended.value) {
      captainLegend = isWaitingForCustomer.value
        ? t('CONVERSATION_SIDEBAR.TOOLS.CAPTAIN_WAITING', captainName)
        : t('CONVERSATION_SIDEBAR.TOOLS.CAPTAIN_REPLYING', captainName);
    }
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
        label:
          isAiAttended.value || isEscalated.value
            ? captainLegend
            : t('CONVERSATION_SIDEBAR.RESPONDER.IDLE'),
        legend: captainLegend,
        onClick: undefined,
      },
      {
        key: 'calendar',
        icon: 'i-lucide-calendar',
        tone: 'blue',
        state: calendarState,
        label: appointment
          ? appointment.summary
          : t('CONVERSATION_SIDEBAR.TOOLS.CALENDAR_IDLE'),
        legend: appointment
          ? t('CONVERSATION_SIDEBAR.TOOLS.NEXT_APPOINTMENT', {
              when: when.toLocaleLowerCase(locale.value),
            })
          : '',
        onClick: () => onOpenCalendar(!appointment),
      },
    ];
  });
}
