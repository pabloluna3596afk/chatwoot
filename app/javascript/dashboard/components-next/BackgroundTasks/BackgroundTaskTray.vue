<script setup>
import { computed, shallowRef, watch, onBeforeUnmount } from 'vue';
import { useStore } from 'dashboard/composables/store';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BackgroundTaskItem from './BackgroundTaskItem.vue';

const store = useStore();
const expanded = shallowRef(false);
const tasks = computed(() => store.getters['backgroundTasks/ordered']);
watch(
  () => store.getters.getCurrentAccountId,
  () => {
    store.dispatch('backgroundTasks/reset');
    expanded.value = false;
  }
);
onBeforeUnmount(() => store.dispatch('backgroundTasks/reset'));
</script>

<template>
  <TeleportWithDirection>
    <section
      v-if="tasks.length"
      class="fixed end-[max(1rem,env(safe-area-inset-right))] top-[max(1rem,env(safe-area-inset-top))] z-40 flex max-h-[80dvh] w-[calc(100%_-_2rem)] max-w-[21.25rem] flex-col gap-2 overflow-y-auto rtl:end-[max(1rem,env(safe-area-inset-left))]"
      :aria-label="$t('BACKGROUND_TASKS.COUNT', { n: tasks.length })"
    >
      <Button
        v-if="tasks.length > 1"
        intent="secondary"
        class="self-end rounded-full"
        :aria-expanded="expanded"
        aria-controls="background-task-list"
        @click="expanded = !expanded"
      >
        <span role="status" aria-live="polite">{{
          $t('BACKGROUND_TASKS.COUNT', { n: tasks.length })
        }}</span>
      </Button>
      <div
        v-if="tasks.length === 1 || expanded"
        id="background-task-list"
        class="flex flex-col gap-2"
      >
        <BackgroundTaskItem
          v-for="task in tasks"
          :key="task.id"
          :task="task"
          @dismiss="store.dispatch('backgroundTasks/dismiss', $event)"
        />
      </div>
    </section>
  </TeleportWithDirection>
</template>
