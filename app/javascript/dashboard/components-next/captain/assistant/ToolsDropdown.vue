<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';

const props = defineProps({
  items: { type: Array, required: true },
  selectedIndex: { type: Number, default: 0 },
});
const emit = defineEmits(['select', 'close', 'update:selectedIndex']);
const open = ref(true);
const toolsDropdownRef = ref(null);
const selectedToolId = computed(() => `tool-item-${props.selectedIndex}`);

watch(selectedToolId, async () => {
  await nextTick();
  toolsDropdownRef.value
    ?.querySelector(`#${selectedToolId.value}`)
    ?.scrollIntoView({ block: 'nearest', behavior: 'auto' });
});

const onKeydown = event => {
  // The editor owns navigation while typing @; focused menu buttons own it here.
  if (['Enter', ' '].includes(event.key)) {
    event.stopPropagation();
    return;
  }
  if (!['ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) return;
  event.preventDefault();
  event.stopPropagation();
  let index = props.selectedIndex;
  if (event.key === 'Home') index = 0;
  else if (event.key === 'End') index = props.items.length - 1;
  else
    index =
      (index + (event.key === 'ArrowDown' ? 1 : -1) + props.items.length) %
      props.items.length;
  toolsDropdownRef.value?.querySelector(`#tool-item-${index}`)?.focus();
};
</script>

<template>
  <MenuPopover
    v-model:open="open"
    align="start"
    :restore-focus-on-select="false"
    panel-class="w-[22.5rem] max-w-[calc(100vw-2rem)]"
    @update:open="!$event && emit('close')"
  >
    <template #trigger>
      <span aria-hidden="true" class="block h-px w-full" />
    </template>
    <template #content>
      <div
        ref="toolsDropdownRef"
        class="flex flex-col gap-1"
        @mousedown.prevent
        @keydown="onKeydown"
      >
        <button
          v-for="(tool, idx) in items"
          :id="`tool-item-${idx}`"
          :key="tool.id || idx"
          type="button"
          :class="{ 'bg-n-alpha-black2': idx === selectedIndex }"
          class="flex flex-col gap-1 text-start rounded-md py-2 px-2 min-h-11 sm:min-h-0 cursor-pointer hover:bg-n-alpha-black2"
          @focus="emit('update:selectedIndex', idx)"
          @click="emit('select', idx)"
        >
          <span class="text-n-slate-12 font-medium text-sm break-words">{{
            tool.title
          }}</span>
          <span class="text-n-slate-11 text-sm break-words">{{
            tool.description
          }}</span>
        </button>
      </div>
    </template>
  </MenuPopover>
</template>
