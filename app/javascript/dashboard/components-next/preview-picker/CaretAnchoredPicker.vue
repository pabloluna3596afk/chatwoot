<script setup>
import {
  computed,
  ref,
  watch,
  useSlots,
  useTemplateRef,
  onUnmounted,
} from 'vue';
import {
  useElementBounding,
  useEventListener,
  useResizeObserver,
  useWindowSize,
} from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useMapGetter } from 'dashboard/composables/store';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useKeyboardNavigableList } from 'dashboard/composables/useKeyboardNavigableList';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import PreviewPicker from './PreviewPicker.vue';

const props = defineProps({
  touchPreview: { type: Boolean, default: false },
  focusSearch: { type: Boolean, default: true },
  caretPosition: {
    type: Object,
    default: null,
  },
  items: {
    type: Array,
    required: true,
  },
  searchPlaceholder: {
    type: String,
    default: '',
  },
  emptyLabel: {
    type: String,
    default: '',
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select', 'close', 'removeTrigger']);

const search = defineModel('search', { type: String, default: '' });

const MIN_HEIGHT = 200;
const MAX_HEIGHT = 360;
const MAX_WIDTH = 768;
const LIST_ONLY_MAX_WIDTH = 420;
const VIEWPORT_MARGIN = 16;
const GAP = 8;
const SIDE_PREVIEW_MIN_WIDTH = 480;
const STACKED_PREVIEW_MIN_HEIGHT = 280;
const MOBILE_BREAKPOINT = 768;

const slots = useSlots();

const hasPreview = computed(() => Boolean(slots.preview));

const caretAnchorRef = useTemplateRef('caretAnchorRef');
const pickerRef = useTemplateRef('pickerRef');
const selectedIndex = ref(0);

const caretAnchor = useElementBounding(caretAnchorRef);
const { width: windowWidth, height: windowHeight } = useWindowSize();
const isRTL = useMapGetter('accounts/isRTL');
const visualViewport = window.visualViewport;
const viewportBounds = ref(null);
const updateViewport = () => {
  if (!visualViewport) return;
  viewportBounds.value = {
    top: visualViewport.offsetTop,
    left: visualViewport.offsetLeft,
    width: visualViewport.width,
    height: visualViewport.height,
  };
};
updateViewport();
let viewportFrame = null;
const scheduleViewportUpdate = () => {
  if (viewportFrame !== null) return;
  viewportFrame = requestAnimationFrame(() => {
    viewportFrame = null;
    updateViewport();
    caretAnchor.update();
  });
};
useEventListener(visualViewport, ['resize', 'scroll'], scheduleViewportUpdate);
onUnmounted(() => {
  if (viewportFrame !== null) cancelAnimationFrame(viewportFrame);
});
const viewport = computed(
  () =>
    viewportBounds.value || {
      top: 0,
      left: 0,
      width: windowWidth.value,
      height: windowHeight.value,
    }
);

const items = computed(() => props.items);

const caretAnchorStyle = computed(() => {
  // On mobile, keep the picker at the editor edge as the caret and keyboard move.
  const atEditorEdge =
    props.touchPreview && windowWidth.value < MOBILE_BREAKPOINT;
  return {
    top: `${atEditorEdge ? 0 : (props.caretPosition?.top ?? 0)}px`,
    height: `${atEditorEdge ? 0 : (props.caretPosition?.height ?? 0)}px`,
  };
});

useResizeObserver(
  () => caretAnchorRef.value?.parentElement,
  caretAnchor.update
);

const placement = computed(() => {
  const top = viewport.value.top + VIEWPORT_MARGIN;
  const bottom = viewport.value.top + viewport.value.height - VIEWPORT_MARGIN;
  const aboveEnd = Math.max(top, Math.min(caretAnchor.top.value - GAP, bottom));
  const belowStart = Math.min(
    bottom,
    Math.max(caretAnchor.bottom.value + GAP, top)
  );
  const above = aboveEnd - top;
  const below = bottom - belowStart;
  const placeAbove = above > below;

  return {
    placeAbove,
    aboveEnd,
    belowStart,
    height: Math.min(MAX_HEIGHT, Math.max(placeAbove ? above : below, 0)),
  };
});

const width = computed(() =>
  Math.min(
    caretAnchor.width.value,
    hasPreview.value ? MAX_WIDTH : LIST_ONLY_MAX_WIDTH,
    viewport.value.width - VIEWPORT_MARGIN * 2
  )
);

const previewLayout = computed(() => {
  if (!hasPreview.value) return 'none';
  if (width.value >= SIDE_PREVIEW_MIN_WIDTH) return 'side';
  if (
    props.touchPreview ||
    placement.value.height >= STACKED_PREVIEW_MIN_HEIGHT
  )
    return 'stacked';
  return 'none';
});

// Measured from the editor's inline start, which is its right edge in RTL. The teleported
// card carries `dir`, so `inset-inline-start` resolves to the matching physical side.
const inlineStart = computed(() =>
  isRTL.value
    ? windowWidth.value - caretAnchor.right.value
    : caretAnchor.left.value
);

const pickerStyle = computed(() => {
  const { placeAbove, height, aboveEnd, belowStart } = placement.value;
  const showsPreview = previewLayout.value !== 'none';
  const viewportStart = isRTL.value
    ? windowWidth.value - viewport.value.left - viewport.value.width
    : viewport.value.left;
  const start = Math.min(
    inlineStart.value,
    viewportStart + viewport.value.width - width.value - VIEWPORT_MARGIN
  );

  return {
    insetInlineStart: `${Math.max(viewportStart + VIEWPORT_MARGIN, start)}px`,
    width: `${width.value}px`,
    height:
      props.touchPreview && previewLayout.value === 'stacked'
        ? `${height}px`
        : null,
    maxHeight: `${height}px`,
    minHeight: showsPreview ? `${Math.min(MIN_HEIGHT, height)}px` : null,
    ...(placeAbove
      ? { bottom: `${windowHeight.value - aboveEnd}px` }
      : { top: `${belowStart}px` }),
  };
});

const adjustScroll = () => pickerRef.value?.scrollSelectedIntoView();

const onSelect = () => {
  const item = items.value[selectedIndex.value];
  if (item) emit('select', item);
};

const { moveSelectionUp, moveSelectionDown } = useKeyboardNavigableList({
  items,
  onSelect,
  adjustScroll,
  selectedIndex,
});

// Consume suggestion keys before ProseMirror moves the caret or inserts a newline.
// Escape must also bypass the document shortcuts that blur editable elements.
const editorElement = document.activeElement;
useEventListener(
  document,
  'keydown',
  event => {
    if (props.focusSearch || event.target !== editorElement) return;
    if (event.isComposing || event.keyCode === 229) {
      event.stopPropagation();
      return;
    }
    const actions = {
      ArrowUp: moveSelectionUp,
      ArrowDown: moveSelectionDown,
      Tab: event.shiftKey ? moveSelectionUp : moveSelectionDown,
      Enter: onSelect,
      Escape: () => emit('close'),
    };
    const action = actions[event.key];
    if (!action || event.ctrlKey || event.metaKey || event.altKey) return;
    event.preventDefault();
    event.stopPropagation();
    action();
  },
  { capture: true }
);

const withPicker = action => ({
  action: event => {
    event.preventDefault();
    action();
  },
  allowOnFocusedInput: true,
});

useKeyboardEvents({
  Tab: withPicker(moveSelectionDown),
  'Shift+Tab': withPicker(moveSelectionUp),
  Escape: withPicker(() => emit('close')),
  Backspace: {
    action: event => {
      if (!props.focusSearch || search.value) return;
      event.preventDefault();
      emit('removeTrigger');
    },
    allowOnFocusedInput: true,
  },
});

const onListItemSelection = index => {
  selectedIndex.value = index;
  onSelect();
};

watch(
  () => items.value.map(item => item.id).join(),
  () => {
    selectedIndex.value = 0;
    adjustScroll();
  }
);
</script>

<template>
  <div
    ref="caretAnchorRef"
    class="absolute inset-x-0 pointer-events-none"
    :style="caretAnchorStyle"
  />
  <TeleportWithDirection to="body">
    <PreviewPicker
      ref="pickerRef"
      v-model:selected-index="selectedIndex"
      v-model:search="search"
      v-on-click-outside="() => emit('close')"
      :focus-search="focusSearch"
      :touch-preview="touchPreview"
      :items="items"
      :search-placeholder="searchPlaceholder"
      :empty-label="emptyLabel"
      :is-loading="isLoading"
      :preview-layout="previewLayout"
      data-popover-content
      class="fixed z-[9999]"
      :style="pickerStyle"
      @select="onListItemSelection"
      @close="emit('close')"
      @keydown.esc.stop.prevent="emit('close')"
    >
      <template v-if="$slots.leading" #leading="slotProps">
        <slot name="leading" v-bind="slotProps" />
      </template>
      <template v-if="$slots.filters" #filters>
        <slot name="filters" />
      </template>
      <template v-if="hasPreview" #preview="slotProps">
        <slot name="preview" v-bind="slotProps" />
      </template>
    </PreviewPicker>
  </TeleportWithDirection>
</template>
