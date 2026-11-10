<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';

const props = defineProps({
  isFlow: { type: Boolean, default: false },
  categoryOptions: { type: Array, required: true },
  statusOptions: { type: Array, required: true },
  categoryGroups: { type: Array, required: true },
  statusGroups: { type: Array, required: true },
});
const query = defineModel('query', { type: String, required: true });
const category = defineModel('category', { type: String, required: true });
const status = defineModel('status', { type: String, required: true });
const { t } = useI18n();
const prefix = 'WHATSAPP_TEMPLATES.SEND_CENTER';
const id = useId();
const open = ref(false);
const toggle = ref(null);
const search = ref(null);
const searchLabel = computed(() =>
  t(`${prefix}.${props.isFlow ? 'SEARCH_FLOWS' : 'SEARCH'}`)
);
const chips = computed(() =>
  [
    { key: 'category', value: category.value, options: props.categoryOptions },
    { key: 'status', value: status.value, options: props.statusOptions },
  ]
    .filter(item => item.value !== 'ALL')
    .map(item => ({
      ...item,
      label: item.options.find(option => option.value === item.value)?.label,
    }))
);
const remove = key => {
  if (key === 'category') category.value = 'ALL';
  else status.value = 'ALL';
};
const clearFilters = () => {
  category.value = 'ALL';
  status.value = 'ALL';
};
const clearSearch = () => {
  query.value = '';
  search.value.focus();
};
const escape = async event => {
  if (event.target === search.value && query.value) {
    event.preventDefault();
    event.stopPropagation();
    clearSearch();
  } else if (open.value) {
    event.preventDefault();
    event.stopPropagation();
    open.value = false;
    await nextTick();
    toggle.value.focus();
  }
};
</script>

<template>
  <div
    role="search"
    :aria-label="searchLabel"
    class="flex min-w-0 flex-col gap-2"
    @keydown.esc="escape"
  >
    <div class="flex min-w-0 items-center gap-2">
      <div class="relative min-w-0 flex-1" data-testid="center-search">
        <label :for="`${id}-search`" class="sr-only">{{ searchLabel }}</label>
        <Icon
          icon="i-lucide-search"
          class="pointer-events-none absolute start-3 top-2.5 size-4 text-n-slate-11"
        />
        <input
          :id="`${id}-search`"
          ref="search"
          v-model="query"
          type="search"
          :placeholder="searchLabel"
          class="m-0 h-9 w-full min-w-0 rounded-lg border border-n-weak bg-n-alpha-2 py-0 ps-9 pe-9 text-sm text-n-slate-12 placeholder:text-n-slate-11 focus:outline focus:outline-2 focus:outline-n-brand"
        />
        <button
          v-if="query"
          type="button"
          class="absolute end-1 top-1 flex size-7 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-label="t(`${prefix}.CLEAR_SEARCH`)"
          @click="clearSearch"
        >
          <Icon icon="i-lucide-x" class="size-4" />
        </button>
      </div>
      <button
        ref="toggle"
        type="button"
        class="flex h-9 shrink-0 items-center gap-2 rounded-lg border border-n-weak px-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="open ? 'bg-n-alpha-2' : 'bg-n-solid-1'"
        :aria-label="t(`${prefix}.FILTERS`)"
        :title="t(`${prefix}.FILTERS`)"
        :aria-expanded="open"
        :aria-controls="`${id}-filters`"
        data-testid="center-filter-toggle"
        @click="open = !open"
      >
        <Icon icon="i-lucide-filter" class="size-4" />
        <span class="hidden min-[1025px]:inline">{{
          t(`${prefix}.FILTERS`)
        }}</span>
        <span
          v-if="chips.length"
          class="flex size-5 items-center justify-center rounded-full bg-n-brand text-xs text-white"
          data-testid="center-filter-count"
          >{{ chips.length }}</span
        >
      </button>
    </div>
    <div
      v-show="open"
      :id="`${id}-filters`"
      class="grid grid-cols-2 gap-2"
      data-testid="center-filters"
    >
      <FilterDropdown
        v-model="category"
        class="min-w-0 [&_button]:!h-9 [&_button]:!w-full [&_button]:!rounded-lg [&_button]:!border [&_button]:!border-n-weak [&_button]:!bg-n-alpha-2 [&_button]:focus-visible:!outline-n-brand [&_.i-lucide-folder]:hidden"
        :class="
          category === 'ALL'
            ? '[&_button]:!text-n-slate-11'
            : '[&_button]:!text-n-slate-12'
        "
        icon="i-lucide-folder"
        :label="t(`${prefix}.FILTER_CATEGORY`)"
        :options="categoryOptions"
        :groups="categoryGroups"
        data-testid="center-category"
      />
      <FilterDropdown
        v-model="status"
        class="min-w-0 [&_button]:!h-9 [&_button]:!w-full [&_button]:!rounded-lg [&_button]:!border [&_button]:!border-n-weak [&_button]:!bg-n-alpha-2 [&_button]:focus-visible:!outline-n-brand [&_.i-lucide-circle-check]:hidden"
        :class="
          status === 'ALL'
            ? '[&_button]:!text-n-slate-11'
            : '[&_button]:!text-n-slate-12'
        "
        icon="i-lucide-circle-check"
        :label="t(`${prefix}.FILTER_STATUS`)"
        :options="statusOptions"
        :groups="statusGroups"
        data-testid="center-status"
      />
      <div v-if="chips.length" class="col-span-2 flex justify-end">
        <button
          type="button"
          class="rounded text-xs text-n-brand underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-testid="center-clear-filters"
          @click="clearFilters"
        >
          {{ t(`${prefix}.CLEAR_FILTERS`) }}
        </button>
      </div>
    </div>
    <div
      v-if="!open && chips.length"
      class="flex min-w-0 gap-2 overflow-x-auto"
      data-testid="center-filter-chips"
    >
      <button
        v-for="chip in chips"
        :key="chip.key"
        type="button"
        class="flex h-6 shrink-0 items-center gap-1 rounded-full bg-n-alpha-2 px-2 text-xs text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-label="t(`${prefix}.REMOVE_FILTER`, { filter: chip.label })"
        @click="remove(chip.key)"
      >
        {{ chip.label }}<Icon icon="i-lucide-x" class="size-3" />
      </button>
    </div>
  </div>
</template>
