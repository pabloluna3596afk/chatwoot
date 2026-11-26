import { onBeforeUnmount, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import BackgroundTasksAPI from 'dashboard/api/backgroundTasks';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

export let activityPanelOpen = false;
export const setActivityPanelOpen = value => {
  activityPanelOpen = value;
};
let selectedActivityPanel = null;
export const reserveActivityPanel = panel => {
  if (selectedActivityPanel && selectedActivityPanel !== panel) return false;
  selectedActivityPanel = panel;
  return true;
};
export const releaseActivityPanel = panel => {
  if (selectedActivityPanel === panel) selectedActivityPanel = null;
};
let completed = [];
let groupingTimer;
let nextToastAt = 0;
const pendingToastTimers = new Set();

const flushCompletions = t => {
  const batch = completed;
  completed = [];
  if (!batch.length || activityPanelOpen) return;
  const errors = batch.filter(task => task.status === 'error').length;
  const message = errors
    ? t('BACKGROUND_TASKS.NOTICE.MIXED', { count: batch.length, errors })
    : t('BACKGROUND_TASKS.NOTICE.SUCCESS', { count: batch.length });
  const delay = Math.max(0, nextToastAt - Date.now());
  const timer = setTimeout(() => {
    pendingToastTimers.delete(timer);
    if (activityPanelOpen) return;
    useAlert(message, {
      type: 'callback',
      message: t('BACKGROUND_TASKS.VIEW_ACTIVITY'),
      duration: 6000,
      onClick: () => emitter.emit('backgroundTask:open'),
    });
    nextToastAt = Date.now() + 6000;
  }, delay);
  pendingToastTimers.add(timer);
};

export const useBackgroundTaskRecovery = () => {
  const store = useStore();
  const { t } = useI18n();
  const { run, abort } = useAbortableRequest();
  const recover = async () => {
    const accountId = store.getters.getCurrentAccountId;
    if (!accountId) return;
    store.commit('backgroundTasks/setLoading', true);
    store.commit('backgroundTasks/setFailed', false);
    const initial = { ...store.state.backgroundTasks.tasks };
    try {
      const response = await run(signal =>
        BackgroundTasksAPI.get(accountId, { signal })
      );
      if (!response) return;
      const recoveredIds = new Set(response.data.map(task => task.id));
      response.data
        .slice()
        .reverse()
        .forEach(task => {
          if (store.state.backgroundTasks.tasks[task.id] === initial[task.id]) {
            store.dispatch('backgroundTasks/upsert', task);
          }
        });
      Object.entries(initial).forEach(([id, task]) => {
        if (
          !recoveredIds.has(id) &&
          store.state.backgroundTasks.tasks[id] === task
        ) {
          store.dispatch('backgroundTasks/dismiss', id);
        }
      });
    } catch {
      store.commit('backgroundTasks/setFailed', true);
    } finally {
      store.commit('backgroundTasks/setLoading', false);
    }
  };
  const onVisibility = () => {
    if (document.visibilityState === 'visible') recover();
  };
  const onReconnect = () => recover();
  const onReload = () => recover();
  const onCompleted = task => {
    completed.push(task);
    clearTimeout(groupingTimer);
    groupingTimer = setTimeout(() => flushCompletions(t), 1000);
  };
  watch(
    () => store.getters.getCurrentAccountId,
    (value, previous) => {
      abort();
      if (previous && value !== previous)
        store.dispatch('backgroundTasks/reset');
      if (value) recover();
    },
    { immediate: true }
  );
  onMounted(() => {
    document.addEventListener('visibilitychange', onVisibility);
    emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, onReconnect);
    emitter.on('backgroundTask:reload', onReload);
    emitter.on('backgroundTask:completed', onCompleted);
  });
  onBeforeUnmount(() => {
    abort();
    document.removeEventListener('visibilitychange', onVisibility);
    emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, onReconnect);
    emitter.off('backgroundTask:reload', onReload);
    emitter.off('backgroundTask:completed', onCompleted);
    clearTimeout(groupingTimer);
    completed = [];
    pendingToastTimers.forEach(clearTimeout);
    pendingToastTimers.clear();
  });
  return { recover };
};
