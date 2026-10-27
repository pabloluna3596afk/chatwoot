<script setup>
import { computed, inject, nextTick, ref, watch } from 'vue';
import {
  breakpointsTailwind,
  onClickOutside,
  useBreakpoints,
  useElementSize,
} from '@vueuse/core';
import { useDropdownPosition } from 'dashboard/composables/useDropdownPosition';
import DropdownMenu from './DropdownMenu.vue';

const props = defineProps({
  menuItems: { type: Array, default: () => [] },
  menuSections: { type: Array, default: () => [] },
  showSearch: { type: Boolean, default: false },
  searchPlaceholder: { type: String, default: '' },
  maxHeight: { type: Number, default: 320 },
  panelClass: { type: String, default: 'w-56 max-w-[calc(100vw-2rem)]' },
  align: { type: String, default: 'end' },
  side: { type: String, default: 'bottom' },
  label: { type: String, default: '' },
  matchWidth: { type: Boolean, default: false },
  dismissible: { type: Boolean, default: true },
  restoreFocusOnSelect: { type: Boolean, default: true },
});
const emit = defineEmits(['action', 'search']);
const open = defineModel('open', { type: Boolean, default: false });
const root = ref(null);
const trigger = ref(null);
const { width: triggerWidth } = useElementSize(trigger);
const menu = ref(null);
const modal = ref(null);
const breakpoints = useBreakpoints(breakpointsTailwind);
const isMobile = breakpoints.smaller('md');
const dialogPortalTarget = inject('dialogPortalTarget', null);
const teleportTarget = computed(() => dialogPortalTarget?.value || 'body');
const menuElement = computed(() => menu.value?.$el);
const { fixedPosition } = useDropdownPosition(trigger, menuElement, open, {
  align: props.align,
  side: props.side,
});
const panelStyle = computed(() => ({
  ...fixedPosition.value.style,
  maxHeight: `${Math.max(0, Math.min(props.maxHeight, parseFloat(fixedPosition.value.style.maxHeight ?? props.maxHeight)))}px`,
  width: props.matchWidth ? `${triggerWidth.value}px` : undefined,
  zIndex: 10050,
}));
const direction = computed(() =>
  open.value
    ? document.querySelector('#app[dir]')?.getAttribute('dir')
    : undefined
);
const close = async (restoreFocus = false) => {
  if (!props.dismissible) return;
  open.value = false;
  if (modal.value?.open) modal.value.close();
  if (restoreFocus) {
    await nextTick();
    trigger.value
      ?.querySelector('button, input')
      ?.focus({ preventScroll: true });
  }
};
watch([open, isMobile], async ([isOpen, mobile]) => {
  await nextTick();
  if (isOpen && mobile && !modal.value?.open) modal.value?.showModal();
  if ((!isOpen || !mobile) && modal.value?.open) modal.value.close();
});
onClickOutside(root, () => close(), { ignore: [menuElement] });
const onAction = item => {
  emit('action', item);
  close(props.restoreFocusOnSelect);
};
const onFocusOut = async event => {
  // Native search focuses on mount, before the parent receives its menu ref.
  await nextTick();
  if (
    event.relatedTarget &&
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
    ...menuElement.value.querySelectorAll(
      'button:not(:disabled), input[type="checkbox"]:not(:disabled)'
    ),
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
    <Teleport :to="teleportTarget">
      <dialog
        v-if="open && isMobile"
        ref="modal"
        :aria-label="label || undefined"
        tabindex="-1"
        class="fixed inset-0 m-0 h-dvh max-h-none w-full max-w-none border-0 bg-transparent p-4 pt-[max(1rem,10dvh)] z-[9999] [&::backdrop]:bg-n-alpha-black1"
        @click.self="close()"
        @cancel.prevent="close(true)"
        @close="open = false"
      >
        <DropdownMenu
          v-if="open"
          ref="menu"
          data-menu-popover
          role="dialog"
          :aria-label="label || undefined"
          :dir="direction"
          :menu-items="menuItems"
          :menu-sections="menuSections"
          :show-search="showSearch"
          :search-placeholder="searchPlaceholder"
          :show-section-dividers="false"
          class="!relative !inset-auto !w-full !max-w-none max-h-[calc(100dvh-2rem)]"
          :class="panelClass"
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
          <template #trailing-icon="slotProps">
            <slot name="trailing-icon" v-bind="slotProps">
              <span
                v-if="slotProps.item.isSelected"
                class="i-lucide-check size-4 shrink-0 ms-auto"
              />
            </slot>
          </template>
          <template v-if="$slots.footer" #footer>
            <slot name="footer" :close="close" />
          </template>
        </DropdownMenu>
      </dialog>
      <DropdownMenu
        v-else-if="open"
        ref="menu"
        data-menu-popover
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
        <template #trailing-icon="slotProps">
          <slot name="trailing-icon" v-bind="slotProps">
            <span
              v-if="slotProps.item.isSelected"
              class="i-lucide-check size-4 shrink-0 ms-auto"
            />
          </slot>
        </template>
        <template v-if="$slots.footer" #footer>
          <slot name="footer" :close="close" />
        </template>
      </DropdownMenu>
    </Teleport>
  </div>
</template>
