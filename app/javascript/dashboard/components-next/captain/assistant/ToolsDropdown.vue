<script setup>
import {
  computed,
  inject,
  nextTick,
  onMounted,
  provide,
  ref,
  watch,
} from 'vue';
import { useEventListener, useWindowSize } from '@vueuse/core';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';

const props = defineProps({
  items: { type: Array, required: true },
  selectedIndex: { type: Number, default: 0 },
});
const emit = defineEmits(['select', 'close', 'update:selectedIndex']);
const open = ref(true);
const source = ref(null);
const portal = ref(null);
const dialogTarget = inject('dialogPortalTarget', null);
// Keep MenuPopover's focus/dismissal behavior, but place its panel relative to
// our fixed caret portal rather than its trigger. Stay in the native dialog layer.
provide('dialogPortalTarget', portal);
const teleportTarget = computed(() => dialogTarget?.value || 'body');
const { width, height } = useWindowSize();
const GAP = 8;
const MARGIN = 16;
const MAX_HEIGHT = 320;
const MAX_WIDTH = 360;
const caret = ref({ top: 0, bottom: 0, left: 0 });
const bottomBoundary = ref(0);
let editorRange;

const updateAnchor = () => {
  if (!source.value) return;
  const selection = window.getSelection();
  if (
    selection?.rangeCount &&
    source.value?.parentElement.contains(selection.anchorNode)
  ) {
    editorRange = selection.getRangeAt(0).cloneRange();
    editorRange.collapse(false);
  }
  caret.value =
    editorRange?.getBoundingClientRect() ||
    source.value.getBoundingClientRect();
  // The form's last region owns Cancel/Create. Keep the menu inside its body.
  const footer = source.value.closest('form')?.lastElementChild;
  bottomBoundary.value = footer
    ? Math.min(height.value - MARGIN, footer.getBoundingClientRect().top)
    : height.value - MARGIN;
};
onMounted(updateAnchor);
useEventListener(document, 'selectionchange', updateAnchor);
useEventListener(window, 'scroll', updateAnchor, {
  capture: true,
  passive: true,
});
useEventListener(window, 'resize', updateAnchor);

const placement = computed(() => {
  const above = Math.max(0, caret.value.top - MARGIN - GAP);
  const below = Math.max(0, bottomBoundary.value - caret.value.bottom - GAP);
  const placeAbove = above > below;
  return {
    maxHeight: Math.min(MAX_HEIGHT, placeAbove ? above : below),
    style: {
      left: `${Math.max(MARGIN, Math.min(caret.value.left, width.value - MAX_WIDTH - MARGIN)) / 16}rem`,
      ...(placeAbove
        ? { bottom: `${(height.value - caret.value.top + GAP) / 16}rem` }
        : { top: `${(caret.value.bottom + GAP) / 16}rem` }),
    },
  };
});
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
  <span ref="source" aria-hidden="true" />
  <Teleport :to="teleportTarget">
    <div ref="portal" class="fixed z-[10050]" :style="placement.style">
      <MenuPopover
        v-model:open="open"
        align="start"
        :restore-focus-on-select="false"
        :max-height="placement.maxHeight"
        panel-class="!relative !inset-auto w-[22.5rem] max-w-[calc(100vw-2rem)]"
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
    </div>
  </Teleport>
</template>
