<script setup>
import { ref, computed, watch } from 'vue';
import ToolsDropdown from 'dashboard/components-next/captain/assistant/ToolsDropdown.vue';
import { useKeyboardNavigableList } from 'dashboard/composables/useKeyboardNavigableList';
import { useMapGetter } from 'dashboard/composables/store.js';

const props = defineProps({
  searchKey: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['selectTool', 'close']);

const tools = useMapGetter('captainTools/getRecords');

const selectedIndex = ref(0);

const filteredTools = computed(() => {
  const search = props.searchKey?.trim().toLowerCase() || '';

  return tools.value.filter(tool => tool.title.toLowerCase().includes(search));
});

const adjustScroll = () => {};

const onSelect = idx => {
  if (Number.isInteger(idx)) selectedIndex.value = idx;
  emit('selectTool', filteredTools.value[selectedIndex.value]);
};

useKeyboardNavigableList({
  items: filteredTools,
  onSelect,
  adjustScroll,
  selectedIndex,
});

watch(filteredTools, newListOfTools => {
  if (newListOfTools.length < selectedIndex.value + 1) {
    selectedIndex.value = 0;
  }
});
</script>

<template>
  <ToolsDropdown
    v-if="filteredTools.length"
    v-model:selected-index="selectedIndex"
    :items="filteredTools"
    class="absolute bottom-20 start-0 w-full"
    @select="onSelect"
    @close="emit('close')"
  />
  <template v-else />
</template>
