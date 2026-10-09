<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  modelValue: { type: [String, Number], required: true },
  options: { type: Array, required: true },
  label: { type: String, required: true },
  icon: { type: String, default: 'i-lucide-filter' },
  searchThreshold: { type: Number, default: 6 },
  groups: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue']);
const isOpen = ref(false);
const selected = computed(() =>
  props.options.find(option => option.value === props.modelValue)
);
const menuItems = computed(() =>
  props.options.map(option => ({
    ...option,
    isSelected: option.value === props.modelValue,
  }))
);
const menuSections = computed(() => {
  if (!props.groups.length) return [];
  return [
    { items: menuItems.value.filter(item => !item.group) },
    ...props.groups.map(group => ({
      title: group.label,
      items: menuItems.value.filter(item => item.group === group.key),
    })),
  ];
});
const choose = item => {
  emit('update:modelValue', item.value);
};
</script>

<template>
  <MenuPopover
    v-model:open="isOpen"
    :menu-items="menuItems"
    :menu-sections="menuSections"
    :show-search="options.length > searchThreshold"
    :label="label"
    panel-class="min-w-56 max-w-80"
    align="start"
    @action="choose"
  >
    <template #trigger="{ toggle }">
      <Button
        :icon="icon"
        color="slate"
        size="sm"
        class="max-w-full"
        :class="{ 'bg-n-slate-9/10': isOpen }"
        :aria-label="label"
        :title="selected?.label || label"
        aria-haspopup="dialog"
        :aria-expanded="isOpen"
        @click="toggle"
      >
        <span class="min-w-0 truncate">{{
          selected?.triggerLabel || selected?.label || label
        }}</span>
        <Icon icon="i-lucide-chevron-down" class="shrink-0 size-4" />
      </Button>
    </template>
    <template #label="{ item }">
      <span
        class="min-w-0 truncate text-sm font-420"
        :aria-current="item.isSelected ? 'true' : undefined"
        :class="{ 'text-n-slate-11': item.count === 0 }"
        >{{ item.label }}</span
      >
    </template>
    <template #trailing-icon="{ item }">
      <span class="ms-auto text-xs tabular-nums text-n-slate-11">{{
        item.count
      }}</span>
      <Icon
        v-if="item.isSelected"
        icon="i-lucide-check"
        class="shrink-0 size-4 text-n-slate-12"
      />
    </template>
  </MenuPopover>
</template>
