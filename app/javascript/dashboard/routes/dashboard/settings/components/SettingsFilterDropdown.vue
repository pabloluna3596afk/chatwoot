<script setup>
import { computed, ref } from 'vue';

import Button from 'dashboard/components-next/button/Button.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  modelValue: {
    type: [String, Number],
    default: 'all',
  },
  options: {
    type: Array,
    default: () => [],
  },
  icon: {
    type: String,
    default: '',
  },
  actionKey: {
    type: String,
    default: 'filter',
  },
});

const emit = defineEmits(['update:modelValue']);

const isOpen = ref(false);

const menuItems = computed(() =>
  props.options.map(option => ({
    ...option,
    action: props.actionKey,
    isSelected: option.value === props.modelValue,
  }))
);

const selectedLabel = computed(() => {
  const selected = menuItems.value.find(item => item.isSelected);
  return selected?.label || menuItems.value[0]?.label || '';
});

const handleAction = ({ value }) => {
  emit('update:modelValue', value);
};
</script>

<template>
  <MenuPopover
    v-model:open="isOpen"
    :menu-items="menuItems"
    :show-search="options.length > 6"
    :label="selectedLabel"
    panel-class="min-w-52 max-w-80"
    align="start"
    @action="handleAction"
  >
    <template #trigger="{ toggle }">
      <Button
        :icon="icon || undefined"
        color="slate"
        size="sm"
        :class="{ 'bg-n-slate-9/10': isOpen }"
        @click="toggle"
      >
        <span class="min-w-0 truncate">{{ selectedLabel }}</span>
        <Icon icon="i-lucide-chevron-down" class="shrink-0 size-4" />
      </Button>
    </template>
  </MenuPopover>
</template>
