import { computed, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import {
  activityIndicatorSnapshot,
  isActivityPanelOpen,
  loadSeenActivity,
  seenActivity,
  taskVersion,
} from './activitySeen';

export const useActivityIndicator = () => {
  const store = useStore();
  const { t } = useI18n();
  const accountId = useMapGetter('getCurrentAccountId');
  const currentUser = useMapGetter('getCurrentUser');
  const tasks = computed(() => store.getters['backgroundTasks/ordered']);
  const seenKey = computed(
    () => `activity-seen:${currentUser.value?.id || ''}:${accountId.value}`
  );
  watch(seenKey, loadSeenActivity, { immediate: true });

  const unseenResults = computed(() =>
    tasks.value.filter(
      task =>
        ['success', 'error'].includes(task.status) &&
        seenActivity.value[task.id] !== taskVersion(task)
    )
  );
  const errors = computed(
    () => unseenResults.value.filter(task => task.status === 'error').length
  );
  const active = computed(
    () =>
      tasks.value.filter(
        task => task.status === 'running' && task.phase !== 'waiting'
      ).length
  );
  const waiting = computed(
    () =>
      tasks.value.filter(
        task => task.status === 'running' && task.phase === 'waiting'
      ).length
  );
  const successes = computed(
    () => unseenResults.value.filter(task => task.status === 'success').length
  );
  const failed = computed(() => store.state.backgroundTasks.failed);
  const visible = computed(
    () =>
      failed.value ||
      active.value ||
      waiting.value ||
      unseenResults.value.length ||
      isActivityPanelOpen.value
  );
  const summary = computed(() => {
    if (isActivityPanelOpen.value && activityIndicatorSnapshot.value)
      return activityIndicatorSnapshot.value.summary;
    if (failed.value) return t('BACKGROUND_TASKS.UNAVAILABLE');
    const values = [];
    if (errors.value)
      values.push(t('BACKGROUND_TASKS.NEW_ERRORS', { count: errors.value }));
    if (active.value)
      values.push(t('BACKGROUND_TASKS.ACTIVE_COUNT', { count: active.value }));
    if (waiting.value)
      values.push(
        t('BACKGROUND_TASKS.WAITING_COUNT', { count: waiting.value })
      );
    if (successes.value)
      values.push(
        t('BACKGROUND_TASKS.NEW_SUCCESSES', { count: successes.value })
      );
    return values.join(t('BACKGROUND_TASKS.SEPARATOR'));
  });
  const iconName = computed(() => {
    if (isActivityPanelOpen.value && activityIndicatorSnapshot.value)
      return activityIndicatorSnapshot.value.iconName;
    if (failed.value) return 'i-lucide-triangle-alert';
    if (errors.value) return 'i-lucide-circle-alert';
    if (active.value) return 'i-lucide-loader-circle';
    if (waiting.value) return 'i-lucide-clock-3';
    return 'i-lucide-circle-check';
  });
  const iconTone = computed(() => {
    if (isActivityPanelOpen.value && activityIndicatorSnapshot.value)
      return activityIndicatorSnapshot.value.iconTone;
    if (failed.value || errors.value) return 'text-n-ruby-11';
    if (active.value) return 'text-n-brand';
    if (successes.value) return 'text-n-teal-11';
    return 'text-n-slate-11';
  });
  const statusTone = computed(() => {
    if (isActivityPanelOpen.value && activityIndicatorSnapshot.value)
      return activityIndicatorSnapshot.value.statusTone;
    if (failed.value || errors.value) return 'error';
    if (active.value) return 'active';
    if (successes.value) return 'success';
    return 'waiting';
  });

  return {
    store,
    t,
    tasks,
    seenKey,
    visible,
    summary,
    iconName,
    iconTone,
    statusTone,
    errors,
    active,
    waiting,
    successes,
    failed,
  };
};
