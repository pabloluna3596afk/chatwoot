<script setup>
import { computed, nextTick, onMounted, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTouchPreview } from 'dashboard/composables/useTouchPreview';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  touchPreview: { type: Boolean, default: false },
  focusSearch: { type: Boolean, default: true },
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
  previewLayout: {
    type: String,
    default: 'side',
    validator: value => ['side', 'stacked', 'none'].includes(value),
  },
});

const emit = defineEmits(['select', 'close']);
const { t } = useI18n();

const selectedIndex = defineModel('selectedIndex', {
  type: Number,
  default: 0,
});
const search = defineModel('search', { type: String, default: '' });

const listRef = useTemplateRef('listRef');
const searchRef = useTemplateRef('searchRef');

const listboxId = useId();
const optionId = index => `${listboxId}-${index}`;

const selectedItem = computed(() => props.items[selectedIndex.value]);

const { isTouch, onPointerDown, onPointerMove, onHover, onClick } =
  useTouchPreview({
    selectedItem,
    onPreview: item => {
      selectedIndex.value = props.items.indexOf(item);
    },
    onSelect: item => emit('select', props.items.indexOf(item)),
  });

const isStacked = computed(() => props.previewLayout === 'stacked');

const hasPreview = computed(
  () => props.previewLayout !== 'none' && props.items.length > 0
);

const listClass = computed(() => {
  if (!hasPreview.value) return 'w-full';
  return isStacked.value
    ? 'w-full flex-1'
    : 'w-2/5 flex-shrink-0 border-r rtl:border-r-0 rtl:border-l border-n-strong';
});

const previewClass = computed(() => {
  if (!isStacked.value) return 'flex-1';
  return props.touchPreview
    ? 'flex-1 min-h-0 border-t border-n-strong'
    : 'h-28 flex-shrink-0 border-t border-n-strong';
});

const groupFor = index => {
  const { group } = props.items[index];
  return group && group !== props.items[index - 1]?.group ? group : null;
};

// Scrolls the list itself. `scrollIntoView` would also scroll clipped ancestors, which
// shifts the card under a stationary cursor and leaves `mouseover` flickering between rows.
const scrollSelectedIntoView = () => {
  nextTick(() => {
    const list = listRef.value;
    const item = list?.querySelector(`[data-index="${selectedIndex.value}"]`);
    if (!item) return;

    const listRect = list.getBoundingClientRect();
    const itemRect = item.getBoundingClientRect();

    if (itemRect.top < listRect.top) {
      list.scrollTop -= listRect.top - itemRect.top;
    } else if (itemRect.bottom > listRect.bottom) {
      list.scrollTop += itemRect.bottom - listRect.bottom;
    }
  });
};

onMounted(() => {
  if (props.focusSearch) searchRef.value?.focus({ preventScroll: true });
});

defineExpose({ scrollSelectedIntoView });
</script>

<template>
  <div
    class="flex overflow-hidden border shadow-lg rounded-xl border-n-strong bg-n-alpha-3 backdrop-blur-[100px]"
    :class="{ 'flex-col': isStacked }"
  >
    <div class="flex flex-col min-h-0 min-w-0" :class="listClass">
      <div
        class="relative flex items-center flex-shrink-0 h-11 px-3 border-b border-n-strong"
        @pointerdown="!focusSearch && $event.preventDefault()"
        @mousedown="!focusSearch && $event.preventDefault()"
      >
        <Icon icon="i-lucide-search" class="size-4 text-n-slate-11" />
        <input
          v-if="focusSearch"
          ref="searchRef"
          v-model="search"
          type="text"
          role="combobox"
          aria-autocomplete="list"
          aria-expanded="true"
          :aria-controls="listboxId"
          :aria-activedescendant="items.length ? optionId(selectedIndex) : null"
          :aria-label="searchPlaceholder"
          class="min-w-0 w-full h-full px-2 text-base sm:text-sm bg-transparent outline-none text-n-slate-12 placeholder:text-n-slate-11 reset-base"
          :placeholder="searchPlaceholder"
          @keydown="
            event => {
              if (event.isComposing) event.stopPropagation();
            }
          "
        />
        <span
          v-else
          role="status"
          class="flex-1 min-w-0 px-2 text-base truncate sm:text-sm"
          :class="search ? 'text-n-slate-12' : 'text-n-slate-11'"
        >
          {{ search || t('CONVERSATION.PICKER.TYPE_TO_SEARCH') }}
        </span>
        <Button
          v-if="touchPreview"
          icon="i-lucide-x"
          intent="tertiary"
          class="min-h-11 min-w-11 shrink-0"
          :aria-label="t('CONVERSATION.PICKER.CLOSE')"
          @pointerdown.prevent
          @mousedown.prevent
          @click="emit('close')"
        />
      </div>
      <div
        v-if="$slots.filters"
        class="flex-shrink-0 min-w-0 px-1 pt-1 pb-1.5"
        @pointerdown.prevent
        @mousedown.prevent
      >
        <slot name="filters" />
      </div>
      <div
        ref="listRef"
        class="flex-1 min-h-0 p-1 overflow-y-auto overscroll-contain"
      >
        <ul :id="listboxId" role="listbox" class="m-0 list-none">
          <template v-for="(item, index) in items" :key="item.id">
            <li
              v-if="groupFor(index)"
              role="presentation"
              class="px-2 pb-1 text-xs font-medium text-n-slate-11"
              :class="index === 0 ? '' : 'pt-2'"
            >
              {{ groupFor(index) }}
            </li>
            <li
              :id="optionId(index)"
              :data-index="index"
              role="option"
              :aria-selected="index === selectedIndex"
              class="flex items-center w-full min-h-11 gap-2 px-2 py-1 overflow-hidden rounded-lg cursor-pointer text-start"
              :class="index === selectedIndex ? 'bg-n-alpha-black2' : ''"
              @mousemove="onHover(item)"
              @pointerdown.prevent="onPointerDown"
              @pointermove="onPointerMove($event, item)"
              @mousedown.prevent
              @click="touchPreview ? onClick(item) : emit('select', index)"
            >
              <slot
                name="leading"
                :item="item"
                :selected="index === selectedIndex"
              />
              <span class="flex flex-col min-w-0 gap-0.5">
                <span
                  v-dompurify-html="item.title"
                  class="max-w-full min-w-0 text-sm font-medium truncate text-n-slate-12"
                />
                <span
                  v-if="item.subtitle"
                  v-dompurify-html="item.subtitle"
                  class="max-w-full min-w-0 text-xs truncate text-n-slate-11"
                />
              </span>
            </li>
          </template>
        </ul>
        <div
          v-if="!items.length"
          role="status"
          class="flex items-center px-2 py-1.5 text-sm text-n-slate-11"
        >
          <Spinner v-if="isLoading" :size="16" />
          <template v-else>{{ emptyLabel }}</template>
        </div>
      </div>
    </div>
    <div v-if="hasPreview" class="flex flex-col min-w-0" :class="previewClass">
      <div
        v-if="!isStacked || (touchPreview && isTouch)"
        class="flex items-center flex-shrink-0 h-11 gap-2 px-4 border-b border-n-strong"
      >
        <span
          class="min-w-0 flex-1 text-xs font-medium truncate text-n-slate-11"
        >
          {{ selectedItem?.label }}
        </span>
        <Button
          v-if="touchPreview && isTouch && selectedItem"
          intent="primary"
          size="sm"
          class="shrink-0"
          :label="t('CONVERSATION.PICKER.USE')"
          @pointerdown.prevent
          @mousedown.prevent
          @click="emit('select', selectedIndex)"
        />
      </div>
      <div class="relative flex-1 min-h-0">
        <div class="absolute inset-0 overflow-y-auto">
          <slot name="preview" :item="selectedItem" />
        </div>
      </div>
    </div>
  </div>
</template>
