<script setup>
import { computed, ref } from 'vue';
import PresetCard from './PresetCard.vue';
import SearchInput from 'dashboard/components-next/input/SearchInput.vue';

const props = defineProps({
  items: { type: Array, default: () => [] },
  groups: { type: Array, default: () => [] },
  searchable: { type: Boolean, default: false },
  columns: {
    type: Number,
    default: 2,
    validator: value => [1, 2].includes(value),
  },
  emptyText: { type: String, default: '' },
});

const emit = defineEmits(['apply']);
const search = ref('');

const visibleItems = computed(() => {
  const query = search.value.trim().toLocaleLowerCase();
  if (!query) return props.items;
  return props.items.filter(item =>
    [item.title, item.description, ...(item.tags || []).map(tag => tag.label)]
      .filter(Boolean)
      .some(value => value.toLocaleLowerCase().includes(query))
  );
});

const sections = computed(() => {
  if (!props.groups.length)
    return [{ id: null, label: '', items: visibleItems.value }];
  return props.groups
    .map(group => ({
      ...group,
      items: visibleItems.value.filter(item => item.group === group.id),
    }))
    .filter(group => group.items.length);
});

const gridColumns = computed(() =>
  props.columns === 1 ? 'grid-cols-1' : 'grid-cols-1 sm:grid-cols-2'
);

const apply = item => emit('apply', item);
</script>

<template>
  <div class="flex flex-col gap-6">
    <SearchInput
      v-if="searchable"
      v-model="search"
      :placeholder="$t('COMPONENTS.COMBOBOX.SEARCH_PLACEHOLDER')"
      :aria-label="$t('COMPONENTS.COMBOBOX.SEARCH_PLACEHOLDER')"
      clearable
    />
    <template v-if="visibleItems.length">
      <section
        v-for="section in sections"
        :key="section.id || 'all'"
        class="grid gap-3"
      >
        <h3 v-if="section.label" class="text-sm font-medium text-n-slate-12">
          {{ section.label }}
        </h3>
        <div class="grid gap-3" :class="gridColumns">
          <slot
            v-for="item in section.items"
            name="card"
            :item="item"
            :apply="() => apply(item)"
          >
            <PresetCard
              :id="item.id"
              :title="item.title"
              :description="item.description"
              :icon="item.icon"
              :tags="item.tags"
              :action-label="item.actionLabel"
              :action-icon="item.actionIcon"
              :disabled="item.disabled"
              @apply="apply(item)"
            >
              <template v-if="$slots.preview" #preview>
                <slot name="preview" :item="item" />
              </template>
              <template v-if="$slots.meta" #meta>
                <slot name="meta" :item="item" />
              </template>
            </PresetCard>
          </slot>
        </div>
      </section>
    </template>
    <p v-else class="text-body-main text-n-slate-11" role="status">
      {{ emptyText || $t('COMPONENTS.COMBOBOX.EMPTY_STATE') }}
    </p>
  </div>
</template>
