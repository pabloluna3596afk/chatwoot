import { ref, watch, onScopeDispose } from 'vue';
import { eventInstant } from 'dashboard/helper/calendarTime';
import { isCancelledEvent } from 'dashboard/helper/appointmentStatus';

const MAX_TIMEOUT_MS = 2147483647;

// One timeout at the next boundary, with no network polling. Visibility refresh
// handles browsers suspending timers while the tab is in the background.
export function useAppointmentClock(events, timezone) {
  const now = ref(Date.now());
  let timer;
  const schedule = () => {
    clearTimeout(timer);
    now.value = Date.now();
    const boundary = events.value
      .filter(event => !isCancelledEvent(event))
      .flatMap(event => [event.start, event.end || event.start])
      .map(value => eventInstant(value, timezone.value) + 1)
      .filter(value => value > now.value)
      .sort((a, b) => a - b)[0];
    if (boundary)
      timer = setTimeout(
        schedule,
        Math.min(boundary - now.value, MAX_TIMEOUT_MS)
      );
  };
  watch([events, timezone], schedule, { immediate: true });
  const onVisible = () => {
    if (!document.hidden) schedule();
  };
  document.addEventListener('visibilitychange', onVisible);
  onScopeDispose(() => {
    clearTimeout(timer);
    document.removeEventListener('visibilitychange', onVisible);
  });
  return now;
}
