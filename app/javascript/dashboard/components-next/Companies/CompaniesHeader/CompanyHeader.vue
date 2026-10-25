<script setup>
import SearchInput from 'dashboard/components-next/input/SearchInput.vue';
import CompanySortMenu from './components/CompanySortMenu.vue';
import CompanyMoreActions from './components/CompanyMoreActions.vue';

defineProps({
  showSearch: { type: Boolean, default: true },
  searchValue: { type: String, default: '' },
  headerTitle: { type: String, required: true },
  activeSort: { type: String, default: 'last_activity_at' },
  activeOrdering: { type: String, default: '' },
});

const emit = defineEmits(['search', 'update:sort', 'create']);
</script>

<template>
  <header class="sticky top-0 z-10 px-6">
    <div
      class="flex items-start sm:items-center justify-between w-full py-6 gap-2 mx-auto max-w-5xl"
    >
      <span class="text-xl font-medium truncate text-n-slate-12">
        {{ headerTitle }}
      </span>
      <div class="flex items-center flex-col sm:flex-row flex-shrink-0 gap-4">
        <div v-if="showSearch" class="flex items-center gap-2 w-full">
          <SearchInput
            :model-value="searchValue"
            :placeholder="$t('COMPANIES.SEARCH_PLACEHOLDER')"
            custom-input-class="h-8 [&:not(.focus)]:!border-transparent bg-n-alpha-2 dark:bg-n-solid-1 !py-1"
            class="w-full"
            size="sm"
            @input="emit('search', $event.target.value)"
          />
        </div>
        <div class="flex items-center flex-shrink-0 gap-2">
          <CompanySortMenu
            :active-sort="activeSort"
            :active-ordering="activeOrdering"
            @update:sort="emit('update:sort', $event)"
          />
          <CompanyMoreActions @create="emit('create')" />
        </div>
      </div>
    </div>
  </header>
</template>
