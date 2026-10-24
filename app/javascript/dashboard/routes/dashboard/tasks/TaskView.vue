<script setup>
import { computed, ref } from 'vue';
import { onBeforeRouteLeave } from 'vue-router';
import { useWindowSize } from '@vueuse/core';
import { useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import TaskList from 'dashboard/components-next/InternalTasks/TaskList.vue';
import TaskKanban from 'dashboard/components-next/InternalTasks/TaskKanban.vue';
import TaskDetail from 'dashboard/components-next/InternalTasks/TaskDetail.vue';

const props = defineProps({
  taskId: { type: [String, Number], default: 0 },
});

const store = useStore();
const taskListRef = ref(null);
const taskKanbanRef = ref(null);

const { width } = useWindowSize();
const isOnExpandedLayout = computed(() => width.value < 768);
const showBoard = ref(false);

const hasTaskSelected = computed(() => Boolean(Number(props.taskId)));

const showTaskList = computed(
  () =>
    !isOnExpandedLayout.value || (!hasTaskSelected.value && !showBoard.value)
);

const onTaskUpdated = () => {
  taskListRef.value?.refresh();
  taskKanbanRef.value?.refresh();
};

onBeforeRouteLeave(() => {
  store.dispatch('internalTasks/clearSelectedState');
});
</script>

<template>
  <section
    class="flex flex-col md:flex-row w-full h-full min-h-0 min-w-0 overflow-hidden bg-n-surface-1"
  >
    <div
      v-if="isOnExpandedLayout && !hasTaskSelected"
      class="flex shrink-0 gap-2 p-2 border-b border-n-weak"
    >
      <Button
        class="min-h-11 flex-1"
        color="slate"
        :variant="showBoard ? 'ghost' : 'faded'"
        :label="$t('INTERNAL_TASKS.VIEW.LIST')"
        :aria-pressed="!showBoard"
        @click="showBoard = false"
      />
      <Button
        class="min-h-11 flex-1"
        color="slate"
        :variant="showBoard ? 'faded' : 'ghost'"
        :label="$t('INTERNAL_TASKS.VIEW.KANBAN')"
        :aria-pressed="showBoard"
        @click="showBoard = true"
      />
    </div>
    <TaskList
      ref="taskListRef"
      :task-id="taskId"
      :show-task-list="showTaskList"
      :is-on-expanded-layout="isOnExpandedLayout"
    />

    <TaskDetail
      v-if="hasTaskSelected"
      :task-id="taskId"
      :is-on-expanded-layout="isOnExpandedLayout"
      @updated="onTaskUpdated"
    />

    <TaskKanban
      v-show="!hasTaskSelected && (!isOnExpandedLayout || showBoard)"
      ref="taskKanbanRef"
      :task-id="taskId"
      :is-on-expanded-layout="isOnExpandedLayout"
    />
  </section>
</template>
