<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  open: {
    type: Boolean,
    required: true,
  },
  options: {
    type: Array,
    required: true,
  },
  groups: { type: Array, default: () => [] },
  searchPlaceholder: {
    type: String,
    default: '',
  },
  emptyState: {
    type: String,
    default: '',
  },
  multiple: {
    type: Boolean,
    default: false,
  },
  selectedValues: {
    type: [String, Number, Array],
    default: () => [],
  },
  searchError: { type: Boolean, default: false },
  loading: {
    type: Boolean,
    default: false,
  },
  // When true, parent positions via fixed/Teleport — drop absolute + mt-1.
  portal: {
    type: Boolean,
    default: false,
  },
  showSearch: {
    type: Boolean,
    default: true,
  },
  placement: { type: String, default: 'top-full start-0 mt-1' },
  scrollClass: { type: String, default: '' },
});

const emit = defineEmits(['select', 'search', 'close', 'retry']);

const { t } = useI18n();

const searchValue = defineModel('searchValue', {
  type: String,
  default: '',
});

const menu = ref(null);
// Body portals leave the app's direction context used by native menu utilities.
const portalDirection = computed(() =>
  props.portal
    ? document.querySelector('#app[dir]')?.getAttribute('dir')
    : undefined
);
const onKeydown = event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    event.stopPropagation();
    emit('close');
    return;
  }
  if (!['ArrowDown', 'ArrowUp'].includes(event.key)) return;
  event.preventDefault();
  const options = [...menu.value.$el.querySelectorAll('[role="option"]')];
  const index = options.indexOf(document.activeElement);
  let next = index + 1;
  if (event.key === 'ArrowUp')
    next = index < 0 ? options.length - 1 : index - 1;
  options[(next + options.length) % options.length]?.focus();
};

const isSelected = option => {
  if (Array.isArray(props.selectedValues)) {
    return props.selectedValues.includes(option.value);
  }
  return option.value === props.selectedValues;
};

const menuItems = computed(() =>
  props.options.map(option => ({
    label: option.label,
    title: option.label,
    value: option.value,
    group: option.group,
    action: 'select',
    option,
    disabled: option.disabled,
    isSelected: isSelected(option),
  }))
);
const menuSections = computed(() =>
  props.groups.length
    ? [
        { items: menuItems.value.filter(item => !item.group) },
        ...props.groups.map(group => ({
          title: group.label,
          items: menuItems.value.filter(item => item.group === group.key),
          emptyState: searchValue.value ? '' : group.emptyState,
        })),
      ].filter(section => section.items.length || section.emptyState)
    : []
);

const onInputSearch = value => {
  searchValue.value = value;
  emit('search', value);
};

defineExpose({
  focus: () => menu.value?.focus(),
});
</script>

<template>
  <DropdownMenu
    v-show="open"
    ref="menu"
    data-combobox-dropdown
    :dir="portalDirection"
    :aria-busy="loading"
    class="w-full max-sm:[&_button]:!min-h-11 max-sm:[&_input]:!min-h-11 [&_button:disabled]:h-auto [&_button:disabled]:min-h-8"
    :class="portal ? '' : placement"
    :menu-items="loading || searchError || groups.length ? [] : menuItems"
    :menu-sections="loading || searchError ? [] : menuSections"
    :show-search="showSearch"
    :search-value="searchValue"
    :search-placeholder="searchPlaceholder || t('COMBOBOX.SEARCH_PLACEHOLDER')"
    :empty-state="emptyState || t('COMBOBOX.EMPTY_STATE')"
    :portal="portal"
    :multiple="multiple"
    :auto-focus="false"
    :show-section-dividers="false"
    :scroll-class="scrollClass || (portal ? 'max-h-none' : 'max-h-60')"
    disable-local-filtering
    listbox
    @search="onInputSearch"
    @action="emit('select', $event.option)"
    @keydown="onKeydown"
    @focusout="
      if (open && !menu.$el.contains($event.relatedTarget))
        emit('close', false);
    "
  >
    <template v-if="loading || searchError" #content>
      <p v-if="loading" role="status" class="p-2 mb-0 text-sm text-n-slate-11">
        {{ t('COMBOBOX.SEARCHING') }}
      </p>
      <div v-else class="p-2 flex flex-col gap-2">
        <p
          role="alert"
          class="mb-0 text-sm text-n-ruby-11 whitespace-pre-line break-words"
        >
          {{ t('COMBOBOX.SEARCH_ERROR') }}
        </p>
        <button
          type="button"
          class="rounded-lg px-3 py-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak max-sm:!min-h-11"
          @click="emit('retry')"
        >
          {{ t('COMBOBOX.RETRY') }}
        </button>
      </div>
    </template>
    <template v-if="loading" #search-icon>
      <Spinner :size="14" class="absolute top-2 start-5 text-n-slate-11" />
    </template>
    <template #label="{ item }">
      <span
        class="min-w-0 text-sm font-420"
        :class="
          item.disabled
            ? 'whitespace-normal break-words text-start'
            : 'truncate'
        "
      >
        {{ item.label }}
      </span>
    </template>
    <template #trailing-icon="{ item }">
      <span
        v-if="item.isSelected"
        class="ms-auto flex-shrink-0 i-lucide-check size-3.5 text-n-slate-11"
      />
    </template>
    <template v-if="$slots.footer" #footer>
      <div class="px-2 pb-2">
        <slot name="footer" :close="() => emit('close')" />
      </div>
    </template>
  </DropdownMenu>
</template>
