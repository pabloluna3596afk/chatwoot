<script setup>
import { computed, nextTick, ref } from 'vue';
import { onClickOutside } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
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
const root = ref(null);
const menu = ref(null);
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
const close = async (restoreFocus = false) => {
  isOpen.value = false;
  if (restoreFocus) {
    await nextTick();
    root.value.querySelector('button').focus();
  }
};
onClickOutside(root, () => close());
const choose = item => {
  emit('update:modelValue', item.value);
  close(true);
};
const focusOption = async (last = false) => {
  await nextTick();
  const buttons = menu.value?.$el.querySelectorAll('button:not(:disabled)');
  buttons?.[last ? buttons.length - 1 : 0]?.focus();
};
const handleKey = async event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    close(true);
    return;
  }
  if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
  if (event.target.tagName === 'INPUT' && ['Home', 'End'].includes(event.key))
    return;
  event.preventDefault();
  if (!isOpen.value) {
    isOpen.value = true;
    await focusOption(event.key === 'ArrowUp' || event.key === 'End');
    return;
  }
  const buttons = [...menu.value.$el.querySelectorAll('button:not(:disabled)')];
  const current = buttons.indexOf(event.target);
  let index;
  if (event.key === 'Home') index = 0;
  else if (event.key === 'End') index = buttons.length - 1;
  else if (current < 0)
    index = event.key === 'ArrowUp' ? buttons.length - 1 : 0;
  else
    index =
      (current + (event.key === 'ArrowDown' ? 1 : -1) + buttons.length) %
      buttons.length;
  buttons[index]?.focus();
};
const handleFocusOut = event => {
  if (!root.value.contains(event.relatedTarget)) close();
};
</script>

<template>
  <div
    ref="root"
    class="relative min-w-0"
    @keydown="handleKey"
    @focusout="handleFocusOut"
  >
    <Button
      :icon="icon"
      color="slate"
      size="sm"
      class="max-w-full"
      :class="{ 'bg-n-slate-9/10': isOpen }"
      :aria-label="label"
      aria-haspopup="dialog"
      :aria-expanded="isOpen"
      @click="isOpen = !isOpen"
    >
      <span class="min-w-0 truncate">{{ selected?.label || label }}</span>
      <Icon icon="i-lucide-chevron-down" class="shrink-0 size-4" />
    </Button>
    <DropdownMenu
      v-if="isOpen"
      ref="menu"
      role="dialog"
      :aria-label="label"
      :menu-items="menuItems"
      :menu-sections="menuSections"
      :show-search="options.length > searchThreshold"
      class="mt-2 min-w-56 max-w-80 max-h-80 top-full start-0"
      @action="choose"
    >
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
    </DropdownMenu>
  </div>
</template>
