<script setup>
import { computed, nextTick, ref } from 'vue';
import { onClickOutside, useElementSize } from '@vueuse/core';
import { useDropdownPosition } from 'dashboard/composables/useDropdownPosition';
import DropdownMenu from './DropdownMenu.vue';

const props = defineProps({
  menuItems: { type: Array, default: () => [] },
  menuSections: { type: Array, default: () => [] },
  showSearch: { type: Boolean, default: false },
  searchPlaceholder: { type: String, default: '' },
  panelClass: { type: String, default: 'w-56 max-w-[calc(100vw-2rem)]' },
  align: { type: String, default: 'end' },
  label: { type: String, default: '' },
  matchWidth: { type: Boolean, default: false },
});
const emit = defineEmits(['action', 'search']);
const open = defineModel('open', { type: Boolean, default: false });
const root = ref(null);
const trigger = ref(null);
const { width: triggerWidth } = useElementSize(trigger);
const menu = ref(null);
const menuElement = computed(() => menu.value?.$el);
const { fixedPosition } = useDropdownPosition(trigger, menuElement, open, {
  align: props.align,
});
const MENU_MAX_HEIGHT = 320;
const panelStyle = computed(() => ({
  ...fixedPosition.value.style,
  maxHeight: `${Math.max(0, Math.min(MENU_MAX_HEIGHT, parseFloat(fixedPosition.value.style.maxHeight ?? MENU_MAX_HEIGHT)))}px`,
  width: props.matchWidth ? `${triggerWidth.value}px` : undefined,
  zIndex: 9999,
}));
const direction = computed(() =>
  open.value
    ? document.querySelector('#app[dir]')?.getAttribute('dir')
    : undefined
);
const close = async (restoreFocus = false) => {
  open.value = false;
  if (restoreFocus) {
    await nextTick();
    trigger.value?.querySelector('button')?.focus({ preventScroll: true });
  }
};
onClickOutside(root, () => close(), { ignore: [menuElement] });
const onAction = item => {
  emit('action', item);
  close(true);
};
const onFocusOut = event => {
  if (
    !root.value?.contains(event.relatedTarget) &&
    !menuElement.value?.contains(event.relatedTarget)
  )
    close();
};
const onKeydown = async event => {
  if (event.key === 'Escape' && open.value) {
    event.preventDefault();
    event.stopPropagation();
    close(true);
    return;
  }
  if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
  if (event.target.tagName === 'INPUT' && ['Home', 'End'].includes(event.key))
    return;
  event.preventDefault();
  const wasOpen = open.value;
  open.value = true;
  await nextTick();
  const buttons = [
    ...menuElement.value.querySelectorAll('button:not(:disabled)'),
  ];
  const current = wasOpen ? buttons.indexOf(event.target) : -1;
  let index;
  if (event.key === 'Home') index = 0;
  else if (event.key === 'End') index = buttons.length - 1;
  else if (current < 0)
    index = event.key === 'ArrowUp' ? buttons.length - 1 : 0;
  else
    index =
      (current + (event.key === 'ArrowDown' ? 1 : -1) + buttons.length) %
      buttons.length;
  buttons[index]?.focus({ preventScroll: true });
};
defineExpose({ close });
</script>

<template>
  <div
    ref="root"
    class="relative min-w-0"
    @keydown="onKeydown"
    @focusout="onFocusOut"
  >
    <div ref="trigger" class="flex items-center">
      <slot name="trigger" :open="open" :toggle="() => (open = !open)" />
    </div>
    <Teleport to="body">
      <DropdownMenu
        v-if="open"
        ref="menu"
        role="dialog"
        :aria-label="label || undefined"
        :dir="direction"
        :menu-items="menuItems"
        :menu-sections="menuSections"
        :show-search="showSearch"
        :search-placeholder="searchPlaceholder"
        :show-section-dividers="false"
        :class="panelClass"
        :style="panelStyle"
        portal
        @action="onAction"
        @search="emit('search', $event)"
        @keydown="onKeydown"
        @focusout="onFocusOut"
      >
        <template v-if="$slots.content" #content>
          <slot name="content" :close="close" />
        </template>
        <template v-if="$slots.label" #label="slotProps">
          <slot name="label" v-bind="slotProps" />
        </template>
        <template v-if="$slots.thumbnail" #thumbnail="slotProps">
          <slot name="thumbnail" v-bind="slotProps" />
        </template>
        <template v-if="$slots['trailing-icon']" #trailing-icon="slotProps">
          <slot name="trailing-icon" v-bind="slotProps" />
        </template>
        <template v-if="$slots.footer" #footer>
          <slot name="footer" :close="close" />
        </template>
      </DropdownMenu>
    </Teleport>
  </div>
</template>
