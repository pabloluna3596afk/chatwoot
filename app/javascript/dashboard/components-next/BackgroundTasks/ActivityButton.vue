<script setup>
import { computed, onBeforeUnmount, ref, useId, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import {
  reserveActivityPanel,
  releaseActivityPanel,
  setActivityPanelOpen,
} from 'dashboard/composables/useBackgroundTaskRecovery';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SidebarUnreadBadge from 'dashboard/components-next/sidebar/SidebarUnreadBadge.vue';

const props = defineProps({
  collapsed: { type: Boolean, default: false },
  mobile: { type: Boolean, default: false },
  mobileLabel: { type: Boolean, default: false },
});
const store = useStore();
const { t } = useI18n();
const panel = ref(null);
const open = ref(false);
const panelId = useId();
const tasks = computed(() => store.getters['backgroundTasks/ordered']);
const accountId = useMapGetter('getCurrentAccountId');
const currentUser = useMapGetter('getCurrentUser');
const userId = computed(() => currentUser.value?.id || '');
const seenKey = computed(
  () => `activity-seen:${userId.value}:${accountId.value}`
);
const seen = ref({});
const taskVersion = task => String(task.version || task.updated_at || '0');
const readSeen = () => {
  try {
    seen.value = JSON.parse(localStorage.getItem(seenKey.value) || '{}');
  } catch {
    seen.value = {};
  }
};
readSeen();
watch(seenKey, readSeen);
const results = computed(() =>
  tasks.value.filter(task => task.status !== 'running')
);
const unseen = computed(() =>
  results.value.filter(task => seen.value[task.id] !== taskVersion(task))
);
const errors = computed(
  () => unseen.value.filter(task => task.status === 'error').length
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
  () => unseen.value.filter(task => task.status === 'success').length
);
const indicatorSnapshot = ref(null);
const indicatorErrors = computed(
  () => indicatorSnapshot.value?.errors ?? errors.value
);
const indicatorActive = computed(
  () => indicatorSnapshot.value?.active ?? active.value
);
const indicatorWaiting = computed(
  () => indicatorSnapshot.value?.waiting ?? waiting.value
);
const indicatorSuccesses = computed(
  () => indicatorSnapshot.value?.successes ?? successes.value
);
const indicatorLoading = computed(
  () => indicatorSnapshot.value?.loading ?? store.state.backgroundTasks.loading
);
const indicatorFailed = computed(
  () => indicatorSnapshot.value?.failed ?? store.state.backgroundTasks.failed
);
const badgeCount = computed(
  () =>
    [
      indicatorErrors.value,
      indicatorActive.value,
      indicatorWaiting.value,
      indicatorSuccesses.value,
    ].find(Boolean) || 0
);
const badgeTone = computed(() => {
  if (indicatorErrors.value) return 'urgent';
  if (indicatorSuccesses.value) return 'success';
  return 'default';
});
const iconName = computed(() => {
  if (indicatorFailed.value) return 'i-lucide-triangle-alert';
  if (indicatorErrors.value) return 'i-lucide-circle-alert';
  if (indicatorActive.value) return '';
  if (indicatorWaiting.value) return 'i-lucide-clock-3';
  if (indicatorSuccesses.value) return 'i-lucide-check';
  return 'i-lucide-list-check';
});
const iconTone = computed(() => {
  if (indicatorErrors.value) return 'text-n-ruby-11';
  if (indicatorActive.value) return 'text-n-brand';
  if (indicatorSuccesses.value) return 'text-n-teal-11';
  return 'text-n-slate-11';
});
const summary = computed(() => {
  if (indicatorFailed.value) return t('BACKGROUND_TASKS.LOAD_ERROR');
  if (indicatorLoading.value && !tasks.value.length)
    return t('BACKGROUND_TASKS.LOADING');
  const values = [];
  if (indicatorActive.value)
    values.push(
      t('BACKGROUND_TASKS.ACTIVE_COUNT', { count: indicatorActive.value })
    );
  if (indicatorWaiting.value)
    values.push(
      t('BACKGROUND_TASKS.WAITING_COUNT', { count: indicatorWaiting.value })
    );
  if (indicatorErrors.value)
    values.push(
      t('BACKGROUND_TASKS.NEW_ERRORS', { count: indicatorErrors.value })
    );
  if (indicatorSuccesses.value)
    values.push(
      t('BACKGROUND_TASKS.NEW_SUCCESSES', { count: indicatorSuccesses.value })
    );
  return (
    values.join(t('BACKGROUND_TASKS.SEPARATOR')) || t('BACKGROUND_TASKS.IDLE')
  );
});
const triggerLabel = computed(
  () => `${t('BACKGROUND_TASKS.ACTIVITY')}: ${summary.value}`
);
const orderedTasks = computed(() =>
  [...tasks.value].sort((a, b) => {
    const priority = task => {
      if (task.status === 'error' && seen.value[task.id] !== taskVersion(task))
        return 0;
      if (task.status === 'running' && task.phase !== 'waiting') return 1;
      if (task.status === 'running') return 2;
      return 3;
    };
    return priority(a) - priority(b);
  })
);
const onShow = () => {
  if (!reserveActivityPanel(panel.value)) {
    panel.value?.hide();
    return;
  }
  open.value = true;
  setActivityPanelOpen(true);
  emitter.emit('backgroundTask:opened');
  indicatorSnapshot.value = {
    errors: errors.value,
    active: active.value,
    waiting: waiting.value,
    successes: successes.value,
    loading: store.state.backgroundTasks.loading,
    failed: store.state.backgroundTasks.failed,
  };
  results.value.forEach(task => {
    seen.value[task.id] = taskVersion(task);
  });
  try {
    localStorage.setItem(seenKey.value, JSON.stringify(seen.value));
  } catch {
    /* Results remain visible; live alerts still work. */
  }
};
const onHide = () => {
  open.value = false;
  setActivityPanelOpen(false);
  indicatorSnapshot.value = null;
  releaseActivityPanel(panel.value);
};
const openPanel = () => {
  const bounds = panel.value?.$el?.getBoundingClientRect();
  if (
    bounds &&
    bounds.bottom > 0 &&
    bounds.top < window.innerHeight &&
    bounds.right > 0 &&
    bounds.left < window.innerWidth
  ) {
    if (reserveActivityPanel(panel.value)) panel.value?.show();
  }
};
const openListener = () => openPanel();
emitter.on('backgroundTask:open', openListener);
onBeforeUnmount(() => {
  emitter.off('backgroundTask:open', openListener);
  if (open.value) setActivityPanelOpen(false);
  releaseActivityPanel(panel.value);
});
const statusText = task => {
  if (task.status === 'error')
    return task.detail || t('BACKGROUND_TASKS.STATUS.ERROR');
  if (task.status === 'success')
    return task.detail || t('BACKGROUND_TASKS.STATUS.SUCCESS');
  if (task.phase === 'waiting')
    return task.detail || t('BACKGROUND_TASKS.STATUS.WAITING');
  return task.detail || t('BACKGROUND_TASKS.STATUS.RUNNING');
};
const statusIcon = task => {
  if (task.status === 'error') return 'i-lucide-circle-alert';
  if (task.status === 'success') return 'i-lucide-circle-check';
  if (task.phase === 'waiting') return 'i-lucide-clock-3';
  return 'i-lucide-loader-circle';
};
const statusTone = task => {
  if (task.status === 'error') return 'text-n-ruby-11';
  if (task.status === 'success') return 'text-n-teal-11';
  if (task.phase === 'waiting') return 'text-n-slate-11';
  return 'text-n-brand';
};
const triggerClass = computed(() => {
  if (props.mobile && props.mobileLabel)
    return '!mx-0 !w-auto !rounded-full !px-3';
  if (props.mobile) return '!mx-0 !size-11 !rounded-full !p-0';
  if (props.collapsed) return 'mx-auto size-11 justify-center p-0';
  return 'mx-2 w-[calc(100%-1rem)] px-2';
});
</script>

<template>
  <Popover
    ref="panel"
    align="start"
    mobile-sheet
    focus-content
    labelledby="activity-title"
    @show="onShow"
    @hide="onHide"
  >
    <template #default>
      <button
        type="button"
        :aria-expanded="open"
        :aria-controls="panelId"
        aria-haspopup="dialog"
        :aria-label="triggerLabel"
        :title="collapsed ? triggerLabel : undefined"
        class="relative flex min-h-11 items-center gap-2 rounded-lg bg-transparent text-sm hover:bg-n-alpha-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="triggerClass"
        @focus="readSeen"
      >
        <Spinner
          v-if="(indicatorActive && !indicatorFailed) || indicatorLoading"
          class="size-4 text-n-brand motion-reduce:animate-none"
        />
        <span
          v-else
          class="size-4 shrink-0"
          :class="[iconName, iconTone]"
          aria-hidden="true"
        />
        <span
          v-if="!collapsed || mobileLabel"
          class="min-w-0 flex-1 truncate text-start text-n-slate-12"
        >
          {{ t('BACKGROUND_TASKS.ACTIVITY') }}
        </span>
        <SidebarUnreadBadge
          v-if="badgeCount"
          :count="badgeCount"
          :tone="badgeTone"
        />
      </button>
    </template>
    <template #content="{ hide, isMobile }">
      <section
        :id="panelId"
        class="flex w-[24rem] max-w-[calc(100vw-2rem)] flex-col overflow-hidden rounded-xl bg-n-solid-1 text-n-slate-12 shadow-lg"
        :class="
          isMobile
            ? 'w-screen max-w-none max-h-[82dvh]'
            : 'max-h-[min(28rem,70dvh)]'
        "
        aria-labelledby="activity-title"
        role="dialog"
      >
        <header
          class="flex shrink-0 items-start justify-between gap-3 border-b border-n-weak px-4 py-3"
        >
          <div class="min-w-0">
            <h2 id="activity-title" class="m-0 text-sm font-semibold">
              {{ t('BACKGROUND_TASKS.TITLE') }}
            </h2>
            <p class="m-0 mt-1 text-xs text-n-slate-11">
              {{ t('BACKGROUND_TASKS.PANEL_SUMMARY', { count: tasks.length })
              }}<template v-if="active">
                {{ t('BACKGROUND_TASKS.SEPARATOR') }}
                {{ t('BACKGROUND_TASKS.ACTIVE_COUNT', { count: active }) }}
              </template>
              <template v-if="errors">
                {{ t('BACKGROUND_TASKS.SEPARATOR') }}
                {{ t('BACKGROUND_TASKS.NEW_ERRORS', { count: errors }) }}
              </template>
            </p>
          </div>
          <button
            type="button"
            class="flex size-11 shrink-0 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :aria-label="t('BACKGROUND_TASKS.CLOSE')"
            @click="hide"
          >
            <span class="i-lucide-x size-4" aria-hidden="true" />
          </button>
        </header>
        <p
          v-if="store.state.backgroundTasks.loading"
          class="m-0 p-4 text-sm text-n-slate-11"
          role="status"
        >
          {{ t('BACKGROUND_TASKS.LOADING') }}
        </p>
        <div
          v-else-if="store.state.backgroundTasks.failed"
          class="p-4 text-sm"
          role="alert"
        >
          <p class="m-0 text-n-slate-11">
            {{ t('BACKGROUND_TASKS.LOAD_ERROR') }}
          </p>
          <button
            class="mt-3 min-h-11 text-n-brand underline"
            type="button"
            @click="emitter.emit('backgroundTask:reload')"
          >
            {{ t('BACKGROUND_TASKS.RELOAD') }}
          </button>
        </div>
        <p v-else-if="!tasks.length" class="m-0 p-4 text-sm text-n-slate-11">
          {{ t('BACKGROUND_TASKS.EMPTY') }}
        </p>
        <ul
          v-else
          class="m-0 min-h-0 list-none overflow-y-auto overflow-x-hidden p-2 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
          :aria-label="t('BACKGROUND_TASKS.TITLE')"
        >
          <li v-for="task in orderedTasks" :key="task.id">
            <RouterLink
              v-if="task.link?.route"
              :to="task.link.route"
              class="flex min-h-11 items-center gap-2 rounded-lg px-2 text-sm hover:bg-n-alpha-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :aria-label="`${task.title}. ${statusText(task)}`"
              @click="hide"
            >
              <span
                class="size-4 shrink-0"
                :class="[statusIcon(task), statusTone(task)]"
                aria-hidden="true"
              />
              <span class="min-w-0 flex-1 truncate">{{ task.title }}</span>
              <span class="max-w-[40%] truncate text-xs text-n-slate-11">{{
                statusText(task)
              }}</span>
              <span
                class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-10"
                aria-hidden="true"
              />
            </RouterLink>
            <div
              v-else
              class="flex min-h-11 items-center gap-2 rounded-lg px-2 text-sm"
              :aria-label="`${task.title}. ${statusText(task)}`"
            >
              <span
                class="size-4 shrink-0"
                :class="statusIcon(task)"
                aria-hidden="true"
              />
              <span class="min-w-0 flex-1 truncate">{{ task.title }}</span>
              <span class="max-w-[40%] truncate text-xs text-n-slate-11">
                {{ statusText(task) }}
              </span>
            </div>
          </li>
        </ul>
      </section>
    </template>
  </Popover>
</template>
