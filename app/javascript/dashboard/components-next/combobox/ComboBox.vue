<script setup>
import { ref, computed, watch, nextTick, inject } from 'vue';
import {
  onClickOutside,
  useElementBounding,
  useElementSize,
} from '@vueuse/core';
import { useDropdownPosition } from 'dashboard/composables/useDropdownPosition';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBoxDropdown from 'dashboard/components-next/combobox/ComboBoxDropdown.vue';

const props = defineProps({
  options: {
    type: Array,
    required: true,
    validator: value =>
      value.every(option => 'value' in option && 'label' in option),
  },
  placeholder: { type: String, default: '' },
  ariaLabel: { type: String, default: '' },
  // Fallback label shown when the selected value is not in `options` yet
  // (e.g. API-backed lists that load lazily on open).
  displayLabel: { type: String, default: '' },
  modelValue: { type: [String, Number, Array], default: '' },
  multiple: { type: Boolean, default: false },
  allowDeselect: { type: Boolean, default: true },
  groups: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
  searchPlaceholder: { type: String, default: '' },
  emptyState: { type: String, default: '' },
  message: { type: String, default: '' },
  hasError: { type: Boolean, default: false },
  useApiResults: { type: Boolean, default: false },
  // Render menu outside overflow parents (modals). Prefers dialog portal target.
  teleport: { type: Boolean, default: false },
  // undefined = auto (hide search when few options)
  showSearch: { type: Boolean, default: undefined },
  dropdownMaxHeight: { type: String, default: '' },
  // The list is as wide as its trigger; a small trigger (a compact button) can ask for a wider list, e.g. '17rem'.
  menuMinWidth: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue', 'search', 'open']);
const SEARCH_OPTION_THRESHOLD = 6;
const MENU_MAX_HEIGHT = 320;
const MENU_GAP = 8;

const { t } = useI18n();

const dialogPortalTarget = inject('dialogPortalTarget', null);
// A drawer can constrain all its pickers, including nested VariablePickers.
const dropdownBoundary = inject('comboboxBoundary', null);
const boundaryBounds = useElementBounding(dropdownBoundary);

const selectedValue = ref(props.modelValue);
const open = ref(false);
const search = ref('');
const dropdownRef = ref(null);
const comboboxRef = ref(null);
const triggerRef = ref(null);
const menuElement = computed(() => dropdownRef.value?.$el);
const { width: triggerWidth } = useElementSize(triggerRef);
const { position, fixedPosition, updatePosition } = useDropdownPosition(
  triggerRef,
  menuElement,
  open,
  { align: 'start' }
);
const dropdownStyle = computed(() => {
  const style = {
    ...fixedPosition.value.style,
    position: 'fixed',
    width: `${triggerWidth.value}px`,
    minWidth: props.menuMinWidth || undefined,
    zIndex: 10050,
  };
  if (!dropdownBoundary?.value || !open.value) return style;

  const trigger = triggerRef.value.getBoundingClientRect();
  const spaceAbove = trigger.top - boundaryBounds.top.value - MENU_GAP;
  const spaceBelow = boundaryBounds.bottom.value - trigger.bottom - MENU_GAP;
  // Use a stable height cap so resizing the list cannot oscillate its placement.
  const placeAbove = spaceBelow < MENU_MAX_HEIGHT && spaceAbove > spaceBelow;
  delete style.top;
  delete style.bottom;
  style.top = placeAbove ? undefined : `${trigger.bottom + MENU_GAP}px`;
  style.bottom = placeAbove
    ? `calc(100vh - ${trigger.top - MENU_GAP}px)`
    : undefined;
  style.maxHeight = `${Math.max(0, Math.min(MENU_MAX_HEIGHT, placeAbove ? spaceAbove : spaceBelow))}px`;
  return style;
});

const teleportTarget = computed(() => {
  if (!props.teleport) return 'body';
  if (dropdownBoundary) return 'body';
  return dialogPortalTarget?.value || 'body';
});

const showSearchField = computed(() => {
  if (typeof props.showSearch === 'boolean') return props.showSearch;
  return props.options.length > SEARCH_OPTION_THRESHOLD;
});

const filteredOptions = computed(() => {
  if (props.useApiResults && search.value) {
    return props.options;
  }

  const searchTerm = search.value.toLowerCase();
  return props.options.filter(option =>
    option.label.toLowerCase().includes(searchTerm)
  );
});
const selectPlaceholder = computed(() => {
  return props.placeholder || t('COMBOBOX.PLACEHOLDER');
});
const selectedLabel = computed(() => {
  if (props.multiple) {
    const labels = props.options
      .filter(option => selectedValue.value.includes(option.value))
      .map(option => option.label);
    return labels.length
      ? `${labels[0]}${labels.length > 1 ? ` +${labels.length - 1}` : ''}`
      : selectPlaceholder.value;
  }
  const selected = props.options.find(
    option => option.value === selectedValue.value
  );
  return selected?.label ?? (props.displayLabel || selectPlaceholder.value);
});

const selectOption = option => {
  if (props.multiple) {
    selectedValue.value = selectedValue.value.includes(option.value)
      ? selectedValue.value.filter(value => value !== option.value)
      : [...selectedValue.value, option.value];
    emit('update:modelValue', selectedValue.value);
    return;
  }
  if (selectedValue.value === option.value && !props.allowDeselect) {
    open.value = false;
    search.value = '';
    return;
  }
  if (selectedValue.value === option.value) {
    selectedValue.value = '';
    emit('update:modelValue', '');
  } else {
    selectedValue.value = option.value;
    emit('update:modelValue', option.value);
  }
  open.value = false;
  search.value = '';
};

const toggleDropdown = async () => {
  if (props.disabled) return;
  open.value = !open.value;
  if (!open.value) return;
  search.value = '';
  emit('open');
  await nextTick();
  updatePosition();
  dropdownRef.value?.focus();
};

watch(
  () => props.modelValue,
  newValue => {
    selectedValue.value = newValue;
  }
);

onClickOutside(
  comboboxRef,
  () => {
    open.value = false;
  },
  { ignore: [dropdownRef] }
);
</script>

<template>
  <div
    ref="comboboxRef"
    class="relative w-full min-w-0"
    :class="{
      'cursor-not-allowed': disabled,
      'group/combobox': !disabled,
    }"
    @click.prevent
  >
    <div ref="triggerRef" class="w-full">
      <Button
        variant="outline"
        :color="hasError && !open ? 'ruby' : open ? 'blue' : 'slate'"
        :label="selectedLabel"
        trailing-icon
        :disabled="disabled"
        aria-haspopup="listbox"
        :aria-label="ariaLabel || undefined"
        :aria-expanded="open"
        no-animation
        class="justify-between w-full !px-3 !py-2.5 text-n-slate-12 font-normal group-hover/combobox:border-n-slate-6 focus:outline-n-brand"
        :class="{
          focused: open,
          '[&:not(.focused)]:dark:outline-n-weak [&:not(.focused)]:hover:enabled:outline-n-slate-6 [&:not(.focused)]:dark:hover:enabled:outline-n-slate-6':
            !hasError,
        }"
        :icon="open ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        @click="toggleDropdown"
      />
    </div>

    <Teleport :to="teleportTarget" :disabled="!teleport">
      <ComboBoxDropdown
        ref="dropdownRef"
        v-model:search-value="search"
        class="text-n-slate-12"
        :open="open"
        :options="filteredOptions"
        :groups="groups"
        :multiple="multiple"
        :search-placeholder="searchPlaceholder"
        :empty-state="emptyState"
        :selected-values="selectedValue"
        :portal="teleport"
        :show-search="showSearchField"
        :scroll-class="dropdownMaxHeight"
        :placement="position.class"
        :style="teleport ? dropdownStyle : position.style"
        @search="emit('search', $event)"
        @select="selectOption"
        @close="
          open = false;
          triggerRef?.querySelector('button')?.focus({ preventScroll: true });
        "
      >
        <template v-if="$slots.footer" #footer="{ close }">
          <slot name="footer" :close="close" />
        </template>
      </ComboBoxDropdown>
    </Teleport>

    <p
      v-if="message"
      class="mt-2 mb-0 text-xs truncate transition-all duration-500 ease-in-out"
      :class="{
        'text-n-ruby-9': hasError,
        'text-n-slate-11': !hasError,
      }"
    >
      {{ message }}
    </p>
  </div>
</template>
