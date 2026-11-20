import { computed, ref } from 'vue';
import {
  createSharedComposable,
  useEventListener,
  useIntervalFn,
} from '@vueuse/core';
import { useLocale } from 'shared/composables/useLocale';
import { useExactTimestamp } from 'shared/composables/useExactTimestamp';

const useActivityClock = createSharedComposable(() => {
  const now = ref(Date.now());
  const update = () => {
    now.value = Date.now();
  };
  useIntervalFn(update, 60_000);
  useEventListener(document, 'visibilitychange', () => {
    if (document.visibilityState === 'visible') update();
  });
  return now;
});

export function useActivityTime(createdAt) {
  const now = useActivityClock();
  const { resolvedLocale } = useLocale();
  const formatExactTime = useExactTimestamp({ showTimeZone: true });
  const date = computed(() => new Date(createdAt.value * 1000));
  const isoTime = computed(() => date.value.toISOString());
  const exactTime = computed(() => formatExactTime(createdAt.value));
  const relativeTime = computed(() => {
    const seconds = Math.max(
      0,
      Math.floor((now.value - date.value.getTime()) / 1000)
    );
    const [unit, divisor] = [
      ['day', 86400],
      ['hour', 3600],
      ['minute', 60],
    ].find(([, duration]) => seconds >= duration) || ['minute', 60];
    return new Intl.RelativeTimeFormat(resolvedLocale.value, {
      style: 'short',
      numeric: 'auto',
    }).format(-Math.floor(seconds / divisor), unit);
  });
  return { isoTime, exactTime, relativeTime };
}
