<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import {
  isActivityPanelOpen,
  activityIndicatorSnapshot,
  persistSeenActivity,
  seenActivity,
  taskVersion,
} from './activitySeen';
import { useActivityIndicator } from './useActivityIndicator';
import {
  reserveActivityPanel,
  releaseActivityPanel,
  setActivityPanelOpen,
} from 'dashboard/composables/useBackgroundTaskRecovery';
import Popover from 'dashboard/components-next/popover/Popover.vue';

const props = defineProps({
  collapsed: { type: Boolean, default: false },
  triggerOnly: { type: Boolean, default: false },
});

const {
  store,
  t,
  tasks,
  seenKey,
  visible,
  summary,
  iconName,
  iconTone,
  statusTone: indicatorStatusTone,
  active,
  failed,
} = useActivityIndicator();
const panel = ref(null);
const open = ref(false);
const panelId = 'background-activity-panel';
const panelTaskIds = ref([]);
const triggerLabel = computed(
  () => `${t('BACKGROUND_TASKS.ACTIVITY')}: ${summary.value}`
);
const resultIsUnseen = task =>
  seenActivity.value[task.id] !== taskVersion(task);
const eligibleTasks = computed(() =>
  tasks.value.filter(task => task.status === 'running' || resultIsUnseen(task))
);
const displayedTasks = computed(() => {
  const visibleTasks = open.value
    ? tasks.value.filter(task => panelTaskIds.value.includes(task.id))
    : eligibleTasks.value;
  const priority = task => {
    if (task.status === 'error') return 0;
    if (task.status === 'running' && task.phase !== 'waiting') return 1;
    if (task.status === 'running') return 2;
    return 3;
  };
  return [...visibleTasks].sort((a, b) => priority(a) - priority(b));
});

watch(
  tasks,
  () => {
    if (!open.value) return;
    const ids = new Set(panelTaskIds.value);
    eligibleTasks.value.forEach(task => ids.add(task.id));
    panelTaskIds.value = [...ids];
  },
  { deep: true }
);

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

const onShow = () => {
  if (!reserveActivityPanel(panel.value)) {
    panel.value?.hide();
    return;
  }
  panelTaskIds.value = eligibleTasks.value.map(task => task.id);
  open.value = true;
  isActivityPanelOpen.value = true;
  activityIndicatorSnapshot.value = {
    summary: summary.value,
    iconName: iconName.value,
    iconTone: iconTone.value,
    statusTone: indicatorStatusTone.value,
  };
  setActivityPanelOpen(true);
  emitter.emit('backgroundTask:opened');
  const nextSeen = { ...seenActivity.value };
  panelTaskIds.value.forEach(id => {
    const task = tasks.value.find(item => item.id === id);
    if (task && task.status !== 'running') nextSeen[id] = taskVersion(task);
  });
  seenActivity.value = nextSeen;
  persistSeenActivity(seenKey.value, nextSeen);
};
const onHide = () => {
  const nextSeen = { ...seenActivity.value };
  panelTaskIds.value.forEach(id => {
    const task = tasks.value.find(item => item.id === id);
    if (task && task.status !== 'running') nextSeen[id] = taskVersion(task);
  });
  seenActivity.value = nextSeen;
  persistSeenActivity(seenKey.value, nextSeen);
  open.value = false;
  isActivityPanelOpen.value = false;
  activityIndicatorSnapshot.value = null;
  panelTaskIds.value = [];
  setActivityPanelOpen(false);
  releaseActivityPanel(panel.value);
};
const openPanel = () => {
  if (reserveActivityPanel(panel.value)) panel.value?.show();
};
const openListener = () => openPanel();
if (!props.triggerOnly) emitter.on('backgroundTask:open', openListener);
onBeforeUnmount(() => {
  emitter.off('backgroundTask:open', openListener);
  if (open.value) setActivityPanelOpen(false);
  if (open.value) isActivityPanelOpen.value = false;
  if (open.value) activityIndicatorSnapshot.value = null;
  releaseActivityPanel(panel.value);
});

const openFromHeader = () => emitter.emit('backgroundTask:open');
</script>

<template>
  <button
    v-if="triggerOnly && visible"
    type="button"
    :aria-label="triggerLabel"
    :title="triggerLabel"
    :aria-expanded="isActivityPanelOpen"
    aria-controls="background-activity-panel"
    aria-haspopup="dialog"
    class="relative flex size-8 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 focus-visible:outline-none md:hidden"
    @click="openFromHeader"
  >
    <span
      class="size-3"
      :class="[
        iconName,
        iconTone,
        { 'motion-safe:animate-spin': active && !failed },
      ]"
      aria-hidden="true"
    />
  </button>
  <Popover
    v-else-if="!triggerOnly"
    ref="panel"
    class="w-full"
    align="start"
    side="top"
    mobile-sheet
    focus-content
    labelledby="activity-title"
    @show="onShow"
    @hide="onHide"
  >
    <template #default>
      <button
        v-if="visible"
        type="button"
        :aria-expanded="open"
        :aria-controls="panelId"
        aria-haspopup="dialog"
        :aria-label="triggerLabel"
        :title="collapsed ? triggerLabel : undefined"
        class="relative flex h-5 min-h-5 w-full items-center gap-1.5 overflow-hidden bg-n-alpha-1 text-start text-[11px] text-n-slate-11 hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 focus-visible:outline-none motion-reduce:transition-none"
        :class="collapsed ? 'justify-center px-0' : 'justify-start px-3'"
      >
        <span
          class="size-3 shrink-0"
          :class="[
            iconName,
            iconTone,
            { 'motion-safe:animate-spin': active && !failed },
          ]"
          aria-hidden="true"
        />
        <span v-if="!collapsed" class="truncate whitespace-nowrap">
          {{ summary }}
        </span>
      </button>
    </template>
    <template #content="{ hide, isMobile }">
      <section
        :id="panelId"
        class="flex w-[21rem] max-w-[calc(100vw-1rem)] flex-col overflow-hidden rounded-[10px] bg-n-solid-1 text-n-slate-12 shadow-lg"
        :class="
          isMobile
            ? 'w-screen max-w-none max-h-[82dvh]'
            : 'max-h-[min(28rem,70dvh)]'
        "
        aria-labelledby="activity-title"
        role="dialog"
      >
        <header
          class="flex shrink-0 items-start justify-between gap-2 pe-1.5 pb-1 ps-3 pt-2"
        >
          <div class="min-w-0">
            <h2 id="activity-title" class="m-0 text-[13px] font-semibold">
              {{ t('BACKGROUND_TASKS.TITLE') }}
            </h2>
            <p
              class="m-0 truncate whitespace-nowrap text-[11px] text-n-slate-11"
            >
              {{ summary }}
            </p>
          </div>
          <button
            type="button"
            class="flex size-6 shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 focus-visible:outline-none"
            :aria-label="t('BACKGROUND_TASKS.CLOSE')"
            @click="hide"
          >
            <span class="i-lucide-x size-4" aria-hidden="true" />
          </button>
        </header>
        <p
          v-if="store.state.backgroundTasks.loading"
          class="m-0 px-3 py-2 text-xs text-n-slate-11"
        >
          {{ t('BACKGROUND_TASKS.LOADING') }}
        </p>
        <div v-else-if="failed" class="px-3 py-2 text-xs">
          <p class="m-0 text-n-slate-11">
            {{ t('BACKGROUND_TASKS.LOAD_ERROR') }}
          </p>
          <button
            class="mt-2 text-n-brand underline"
            type="button"
            @click="emitter.emit('backgroundTask:reload')"
          >
            {{ t('BACKGROUND_TASKS.RELOAD') }}
          </button>
        </div>
        <p
          v-else-if="!displayedTasks.length"
          class="m-0 px-3 py-2 text-xs text-n-slate-11"
        >
          {{ t('BACKGROUND_TASKS.EMPTY') }}
        </p>
        <ul
          v-else
          class="m-0 min-h-0 list-none overflow-y-auto overflow-x-hidden p-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
          :aria-label="t('BACKGROUND_TASKS.TITLE')"
        >
          <li v-for="task in displayedTasks" :key="task.id">
            <RouterLink
              v-if="task.link?.route"
              :to="task.link.route"
              class="flex min-h-8 items-center gap-2 px-2 text-[13px] hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 focus-visible:outline-none"
              :class="{ 'min-h-11': isMobile }"
              :aria-label="`${task.title}. ${statusText(task)}`"
              @click="hide"
            >
              <span
                class="size-3 shrink-0"
                :class="[statusIcon(task), statusTone(task)]"
                aria-hidden="true"
              />
              <span class="min-w-0 flex-1 truncate">{{ task.title }}</span>
              <span class="max-w-[40%] truncate text-[11px] text-n-slate-11">{{
                statusText(task)
              }}</span>
            </RouterLink>
            <div
              v-else
              class="flex min-h-8 items-center gap-2 px-2 text-[13px]"
              :class="{ 'min-h-11': isMobile }"
              :aria-label="`${task.title}. ${statusText(task)}`"
            >
              <span
                class="size-3 shrink-0"
                :class="[statusIcon(task), statusTone(task)]"
                aria-hidden="true"
              />
              <span class="min-w-0 flex-1 truncate">{{ task.title }}</span>
              <span class="max-w-[40%] truncate text-[11px] text-n-slate-11">{{
                statusText(task)
              }}</span>
            </div>
          </li>
        </ul>
      </section>
    </template>
  </Popover>
</template>
