<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

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
});

const emit = defineEmits(['select', 'search', 'close']);

const { t } = useI18n();

const searchValue = defineModel('searchValue', {
  type: String,
  default: '',
});

const searchInput = ref(null);
const menu = ref(null);
const sections = computed(() =>
  props.groups.length
    ? [
        { key: '', options: props.options.filter(option => !option.group) },
        ...props.groups.map(group => ({
          ...group,
          options: props.options.filter(option => option.group === group.key),
        })),
      ]
    : [{ key: '', options: props.options }]
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
  const options = [...menu.value.querySelectorAll('[role="option"]')];
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

const onInputSearch = event => {
  searchValue.value = event.target.value;
  emit('search', event.target.value);
};

defineExpose({
  focus: () => (searchInput.value || menu.value)?.focus(),
});
</script>

<template>
  <div
    v-show="open"
    ref="menu"
    tabindex="-1"
    data-combobox-dropdown
    class="z-50 w-full transition-opacity duration-200 border rounded-md shadow-lg bg-n-solid-1 border-n-strong flex flex-col overflow-hidden"
    :class="portal ? 'fixed' : ['absolute', placement]"
    @keydown="onKeydown"
  >
    <div v-if="showSearch" class="relative border-b border-n-strong shrink-0">
      <Spinner
        v-if="loading"
        :size="16"
        class="absolute top-2.5 start-3 text-n-slate-11"
      />
      <Icon
        v-else
        icon="i-lucide-search"
        class="absolute top-2.5 size-4 start-3"
      />
      <input
        ref="searchInput"
        :value="searchValue"
        type="search"
        :placeholder="searchPlaceholder || t('COMBOBOX.SEARCH_PLACEHOLDER')"
        class="reset-base w-full py-2 !ps-10 !pe-2 text-sm focus:outline-none border-none rounded-t-md bg-n-solid-1 text-n-slate-12"
        @input="onInputSearch"
      />
    </div>
    <ul
      class="py-1 mb-0 overflow-auto min-h-0"
      :class="portal ? 'max-h-none' : 'max-h-60'"
      role="listbox"
      :aria-multiselectable="multiple"
    >
      <template v-for="section in sections" :key="section.key">
        <li
          v-if="
            section.label &&
            (section.options.length || (!searchValue && section.emptyState))
          "
          role="presentation"
          class="px-3 pt-2 pb-1 text-xs font-medium text-n-slate-11"
        >
          {{ section.label }}
        </li>
        <li
          v-for="(option, index) in section.options"
          :key="`${option.value}-${index}`"
          class="flex items-center justify-between w-full gap-2 px-3 py-2 text-sm transition-colors duration-150 cursor-pointer hover:bg-n-alpha-2 focus:bg-n-alpha-2 focus:outline-none"
          :class="{ 'bg-n-alpha-2': isSelected(option) }"
          role="option"
          tabindex="0"
          :aria-selected="isSelected(option)"
          @click.stop="emit('select', option)"
          @keydown.enter.prevent="emit('select', option)"
          @keydown.space.prevent="emit('select', option)"
        >
          <span
            :class="{ 'font-medium': isSelected(option) }"
            class="text-n-slate-12"
            >{{ option.label }}</span
          >
          <span
            v-if="isSelected(option)"
            class="flex-shrink-0 i-lucide-check size-4 text-n-slate-11"
          />
        </li>
        <li
          v-if="!section.options.length && section.emptyState && !searchValue"
          role="presentation"
          class="px-3 py-2 text-xs text-n-slate-11"
        >
          {{ section.emptyState }}
        </li>
      </template>
      <li
        v-if="options.length === 0 && (!groups.length || searchValue)"
        class="px-3 py-2 text-sm text-n-slate-11"
      >
        {{ emptyState || t('COMBOBOX.EMPTY_STATE') }}
      </li>
    </ul>
    <div v-if="$slots.footer" class="p-2 border-t border-n-weak shrink-0">
      <slot name="footer" :close="() => emit('close')" />
    </div>
  </div>
</template>
