<script setup>
import { computed, ref, watch } from 'vue';
import { useMutationObserver } from '@vueuse/core';
import { useStore } from 'dashboard/composables/store';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import BackgroundTaskItem from './BackgroundTaskItem.vue';

const store = useStore();
const MAX_VISIBLE_RUNNING_TASKS = 3;
const tray = ref(null);
const tasks = computed(() => store.getters['backgroundTasks/ordered']);
const visibleTasks = computed(() => {
  const finished = tasks.value.filter(task => task.status !== 'running');
  const running = tasks.value.filter(task => task.status === 'running');
  return [...finished, ...running.slice(0, MAX_VISIBLE_RUNNING_TASKS)];
});
const hiddenCount = computed(
  () => tasks.value.length - visibleTasks.value.length
);

// Like SnackbarContainer, use the top layer so native dialogs cannot cover notices.
const showPopover = () => {
  tray.value?.hidePopover?.();
  tray.value?.showPopover?.();
};
watch([tray, () => tasks.value.length], showPopover, { flush: 'post' });
useMutationObserver(
  document.body,
  mutations => {
    if (
      mutations.some(
        ({ target }) =>
          target.tagName === 'DIALOG' && target.hasAttribute('open')
      )
    )
      showPopover();
  },
  { attributes: true, attributeFilter: ['open'], subtree: true }
);
watch(
  () => store.getters.getCurrentAccountId,
  () => {
    store.dispatch('backgroundTasks/reset');
  }
);
</script>

<template>
  <TeleportWithDirection>
    <section
      v-if="tasks.length"
      ref="tray"
      popover="manual"
      class="pointer-events-none fixed inset-auto end-[max(1rem,env(safe-area-inset-right))] top-[max(1rem,env(safe-area-inset-top))] z-[10000] m-0 flex max-h-[80dvh] w-[calc(100%_-_2rem)] max-w-[21.25rem] flex-col gap-2 overflow-y-auto border-0 bg-transparent p-1 rtl:end-[max(1rem,env(safe-area-inset-left))]"
      :aria-label="$t('BACKGROUND_TASKS.COUNT', { n: tasks.length })"
    >
      <BackgroundTaskItem
        v-for="task in visibleTasks"
        :key="task.id"
        :task="task"
        @dismiss="store.dispatch('backgroundTasks/dismiss', $event)"
      />
      <p
        v-if="hiddenCount"
        role="status"
        aria-live="polite"
        class="m-0 self-end rounded-md bg-n-solid-1 px-2 py-1 text-xs text-n-slate-11 shadow-sm"
      >
        {{ $t('BACKGROUND_TASKS.MORE', { n: hiddenCount }) }}
      </p>
    </section>
  </TeleportWithDirection>
</template>
