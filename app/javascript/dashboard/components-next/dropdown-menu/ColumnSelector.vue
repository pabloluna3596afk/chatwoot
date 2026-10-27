<script setup>
import Draggable from 'vuedraggable';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const props = defineProps({
  visibleKeys: { type: Array, default: () => [] },
  pinnedColumn: { type: Object, default: null },
  isFiltering: { type: Boolean, default: false },
  hasItems: { type: Boolean, default: true },
  emptyLabel: { type: String, default: '' },
});

const emit = defineEmits(['toggle', 'dragStart', 'dragEnd']);

const items = defineModel('items', { type: Array, default: () => [] });

const isChecked = key => props.visibleKeys.includes(key);
</script>

<template>
  <div class="flex flex-col gap-0.5 overflow-y-auto min-h-0 pe-0.5 -me-0.5 p-1">
    <label
      v-if="pinnedColumn"
      class="flex items-center gap-2 rounded-lg px-1.5 py-1.5 opacity-60 cursor-not-allowed"
    >
      <span
        class="inline-flex size-5 shrink-0 items-center justify-center text-n-slate-10"
        aria-hidden="true"
      >
        <span class="i-lucide-pin size-3.5" />
      </span>
      <Checkbox model-value disabled />
      <span class="truncate text-sm text-n-slate-12">
        {{ pinnedColumn.label }}
      </span>
    </label>

    <Draggable
      v-model="items"
      item-key="key"
      :disabled="isFiltering"
      :animation="200"
      force-fallback
      filter=".column-no-drag"
      :prevent-on-filter="false"
      ghost-class="opacity-50"
      class="flex flex-col gap-0.5"
      @start="emit('dragStart')"
      @end="emit('dragEnd')"
    >
      <template #item="{ element: column }">
        <div
          class="flex items-center gap-2 rounded-lg px-1.5 py-1.5 hover:bg-n-alpha-2 select-none min-w-0"
          :class="
            isFiltering
              ? 'cursor-default'
              : 'cursor-grab active:cursor-grabbing'
          "
        >
          <span
            class="inline-flex size-5 shrink-0 items-center justify-center text-n-slate-11"
            :class="isFiltering ? 'opacity-40' : ''"
            aria-hidden="true"
          >
            <span class="i-lucide-grip-vertical size-3.5" />
          </span>
          <label
            class="column-no-drag flex min-w-0 flex-1 items-center gap-2.5 text-sm text-n-slate-12 cursor-pointer"
          >
            <Checkbox
              :model-value="isChecked(column.key)"
              @change="emit('toggle', column.key, $event.target.checked)"
            />
            <span class="truncate">{{ column.label }}</span>
          </label>
        </div>
      </template>
    </Draggable>

    <p v-if="!hasItems" class="text-sm text-n-slate-11 text-center py-6">
      {{ emptyLabel }}
    </p>
  </div>
</template>
