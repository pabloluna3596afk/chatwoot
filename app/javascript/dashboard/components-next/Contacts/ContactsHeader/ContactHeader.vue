<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import SearchInput from 'dashboard/components-next/input/SearchInput.vue';
import ContactSortMenu from './components/ContactSortMenu.vue';
import ContactColumnMenu from './components/ContactColumnMenu.vue';
import ContactMoreActions from './components/ContactMoreActions.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';

defineProps({
  showSearch: { type: Boolean, default: true },
  searchValue: { type: String, default: '' },
  headerTitle: { type: String, required: true },
  buttonLabel: { type: String, default: '' },
  activeSort: { type: String, default: 'last_activity_at' },
  activeOrdering: { type: String, default: '' },
  isSegmentsView: { type: Boolean, default: false },
  hasActiveFilters: { type: Boolean, default: false },
  isLabelView: { type: Boolean, default: false },
  isActiveView: { type: Boolean, default: false },
});

const emit = defineEmits([
  'search',
  'filter',
  'update:sort',
  'add',
  'import',
  'export',
  'createSegment',
  'deleteSegment',
]);
</script>

<template>
  <header class="relative z-30 shrink-0 bg-n-surface-1 px-4 sm:px-6">
    <div
      class="flex flex-col sm:flex-row sm:items-center sm:justify-between w-full py-3 sm:py-4 gap-3 sm:gap-2 mx-auto max-w-full"
    >
      <span class="text-xl font-medium text-n-slate-12 leading-tight">
        {{ headerTitle }}
      </span>
      <div
        class="flex items-center flex-col sm:flex-row flex-shrink-0 gap-2 sm:gap-4 min-w-0"
      >
        <div
          v-if="showSearch"
          class="flex items-center gap-2 w-full sm:w-56 min-w-0"
        >
          <SearchInput
            :model-value="searchValue"
            :placeholder="$t('CONTACTS_LAYOUT.HEADER.SEARCH_PLACEHOLDER')"
            custom-input-class="h-8 [&:not(.focus)]:!border-transparent bg-n-alpha-2 dark:bg-n-solid-1 !py-1"
            class="w-full"
            size="sm"
            @input="emit('search', $event.target.value)"
          />
        </div>
        <div
          class="flex items-center flex-shrink-0 justify-between w-full sm:w-auto gap-2 sm:gap-4"
        >
          <div class="flex items-center gap-1 sm:gap-2">
            <div v-if="!isLabelView && !isActiveView" class="relative">
              <Button
                id="toggleContactsFilterButton"
                :icon="
                  isSegmentsView ? 'i-lucide-pen-line' : 'i-lucide-list-filter'
                "
                color="slate"
                size="sm"
                class="relative w-8"
                variant="ghost"
                @click="emit('filter')"
              >
                <div
                  v-if="hasActiveFilters && !isSegmentsView"
                  class="absolute top-0 right-0 w-2 h-2 rounded-full bg-n-brand"
                />
              </Button>
              <slot name="filter" />
            </div>
            <Button
              v-if="
                hasActiveFilters &&
                !isSegmentsView &&
                !isLabelView &&
                !isActiveView
              "
              icon="i-lucide-save"
              color="slate"
              size="sm"
              variant="ghost"
              @click="emit('createSegment')"
            />
            <Button
              v-if="isSegmentsView && !isLabelView && !isActiveView"
              icon="i-lucide-trash"
              color="slate"
              size="sm"
              variant="ghost"
              @click="emit('deleteSegment')"
            />
            <ContactSortMenu
              :active-sort="activeSort"
              :active-ordering="activeOrdering"
              @update:sort="emit('update:sort', $event)"
            />
            <ContactColumnMenu />
            <ContactMoreActions
              @add="emit('add')"
              @import="emit('import')"
              @export="emit('export')"
            />
          </div>
          <div class="hidden sm:block w-px h-4 bg-n-strong" />
          <ComposeConversation>
            <template #trigger>
              <Button :label="buttonLabel" size="sm" class="max-sm:min-h-11" />
            </template>
          </ComposeConversation>
        </div>
      </div>
    </div>
  </header>
</template>
