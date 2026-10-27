<script setup>
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import {
  STANDARD_CONTACT_COLUMNS,
  buildCustomColumns,
  resolveVisibleColumns,
} from 'dashboard/helper/contactTableColumns';

import Button from 'dashboard/components-next/button/Button.vue';
import ColumnSelector from 'dashboard/components-next/dropdown-menu/ColumnSelector.vue';

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const getAttributesByModel = useMapGetter('attributes/getAttributesByModel');

const isMenuOpen = ref(false);
const searchQuery = ref('');
const dragging = ref(false);
/** Local ordered visible keys so reorder feels instant before store round-trip */
const draftKeys = ref([]);
/** Full column order (visible + hidden) so toggles don't reshuffle the list */
const orderedAllKeys = ref([]);
/**
 * Plain ref for vuedraggable (matches PreChatFields).
 * Do NOT v-model a computed that persists mid-drag — Sortable update events
 * rewrite orderedAllKeys and remount items, which kills the drag gesture.
 */
const dragList = ref([]);

const filterText = computed(() => searchQuery.value.trim().toLowerCase());
const isFiltering = computed(() => Boolean(filterText.value));

const matchesSearch = label =>
  !filterText.value || (label || '').toLowerCase().includes(filterText.value);

const customColumns = computed(() => {
  const getter = getAttributesByModel.value;
  const defs = typeof getter === 'function' ? getter('contact_attribute') : [];
  return buildCustomColumns(defs);
});

const standardColumns = computed(() =>
  STANDARD_CONTACT_COLUMNS.map(col => ({
    ...col,
    label: t(`CONTACTS_LAYOUT.TABLE.COLUMNS.${col.labelKey}`),
  }))
);

const allColumns = computed(() => [
  ...standardColumns.value,
  ...customColumns.value,
]);

const columnByKey = computed(() =>
  Object.fromEntries(allColumns.value.map(col => [col.key, col]))
);

const availableKeys = computed(() => allColumns.value.map(col => col.key));

const resolvedKeys = computed(() =>
  resolveVisibleColumns(
    uiSettings.value?.contacts_table_columns,
    availableKeys.value,
    customColumns.value
  )
);

const ensureNameFirst = keys => {
  const withoutName = keys.filter(key => key !== 'name');
  return availableKeys.value.includes('name')
    ? ['name', ...withoutName]
    : withoutName;
};

const syncOrderedAllKeys = visibleKeys => {
  const available = availableKeys.value;
  const availableSet = new Set(available);
  const prev = orderedAllKeys.value.filter(key => availableSet.has(key));

  if (!prev.length) {
    const visible = visibleKeys.filter(key => availableSet.has(key));
    const visibleSet = new Set(visible);
    const hidden = available.filter(key => !visibleSet.has(key));
    orderedAllKeys.value = ensureNameFirst([...visible, ...hidden]);
    return;
  }

  const prevSet = new Set(prev);
  const appended = available.filter(key => !prevSet.has(key));
  orderedAllKeys.value = ensureNameFirst([...prev, ...appended]);
};

const rebuildDragList = () => {
  dragList.value = orderedAllKeys.value
    .filter(key => key !== 'name')
    .map(key => columnByKey.value[key])
    .filter(Boolean)
    .filter(col => matchesSearch(col.label));
};

// Keep draft + full order in sync with persisted settings (and when attribute defs load)
watch(
  resolvedKeys,
  keys => {
    const next = [...keys];
    const same =
      next.length === draftKeys.value.length &&
      next.every((key, i) => key === draftKeys.value[i]);
    if (!same) draftKeys.value = next;
    syncOrderedAllKeys(next);
  },
  { immediate: true }
);

watch(availableKeys, () => {
  syncOrderedAllKeys(draftKeys.value);
});

const visibleSet = computed(() => new Set(draftKeys.value));

watch(
  [orderedAllKeys, columnByKey, filterText],
  () => {
    if (!dragging.value) rebuildDragList();
  },
  { immediate: true }
);

const nameColumn = computed(() => columnByKey.value.name);

const showNameRow = computed(
  () => nameColumn.value && matchesSearch(nameColumn.value.label)
);

const visibleCount = computed(() => draftKeys.value.length);

const isRequired = key =>
  STANDARD_CONTACT_COLUMNS.find(col => col.key === key)?.required === true;

const persist = keys => {
  let next = [...keys];
  if (!next.includes('name') && availableKeys.value.includes('name')) {
    next = ['name', ...next.filter(k => k !== 'name')];
  }
  draftKeys.value = next;
  updateUISettings({ contacts_table_columns: next });
};

const persistVisibleFromOrder = () => {
  const visible = visibleSet.value;
  persist(orderedAllKeys.value.filter(key => visible.has(key)));
};

const toggleColumn = (key, checked) => {
  if (isRequired(key)) return;
  const visible = new Set(draftKeys.value);
  if (checked) {
    visible.add(key);
  } else {
    visible.delete(key);
  }
  // Preserve list order — do not rebuild from allColumns.map.filter
  persist(orderedAllKeys.value.filter(k => visible.has(k)));
};

const selectDefaults = () => {
  const defaults = resolveVisibleColumns(
    null,
    availableKeys.value,
    customColumns.value
  );
  orderedAllKeys.value = ensureNameFirst([
    ...defaults,
    ...availableKeys.value.filter(key => !defaults.includes(key)),
  ]);
  persist(defaults);
};

const selectAll = () => {
  const current = [...draftKeys.value];
  const present = new Set(current);
  orderedAllKeys.value.forEach(key => {
    if (!present.has(key)) current.push(key);
  });
  persist(current);
};

const onDragStart = () => {
  dragging.value = true;
};

const onDragEnd = () => {
  dragging.value = false;
  if (isFiltering.value) {
    rebuildDragList();
    return;
  }
  const reordered = dragList.value.map(item => item.key);
  const remaining = orderedAllKeys.value.filter(
    key => key !== 'name' && !reordered.includes(key)
  );
  orderedAllKeys.value = ensureNameFirst([...reordered, ...remaining]);
  persistVisibleFromOrder();
};

const hasListItems = computed(
  () => showNameRow.value || dragList.value.length > 0
);
</script>

<template>
  <MenuPopover
    v-model:open="isMenuOpen"
    :dismissible="!dragging"
    :label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.COLUMNS.LABEL')"
    panel-class="w-96 max-w-[calc(100vw-2rem)]"
    show-search
    :search-placeholder="t('CONTACTS_LAYOUT.HEADER.ACTIONS.COLUMNS.SEARCH')"
    @update:open="searchQuery = ''"
    @search="searchQuery = $event"
  >
    <template #trigger>
      <Button
        icon="i-lucide-columns-3"
        color="slate"
        size="sm"
        variant="ghost"
        :class="isMenuOpen ? 'bg-n-alpha-2' : ''"
        :title="t('CONTACTS_LAYOUT.HEADER.ACTIONS.COLUMNS.LABEL')"
        @click="isMenuOpen = !isMenuOpen"
      />
    </template>
    <template #content>
      <div class="flex flex-col gap-3 px-2 pb-2 overflow-y-auto min-h-0">
        <div class="flex items-start justify-between gap-2 shrink-0">
          <div class="min-w-0">
            <p class="text-sm font-medium text-n-slate-12">
              {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.COLUMNS.LABEL') }}
            </p>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{
                t('CONTACTS_LAYOUT.HEADER.ACTIONS.COLUMNS.VISIBLE_COUNT', {
                  count: visibleCount,
                })
              }}
            </p>
          </div>
          <div class="flex items-center gap-0.5 shrink-0">
            <Button
              size="xs"
              variant="ghost"
              color="slate"
              :label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.COLUMNS.DEFAULTS')"
              @click="selectDefaults"
            />
            <Button
              size="xs"
              variant="ghost"
              color="slate"
              :label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.COLUMNS.ALL')"
              @click="selectAll"
            />
          </div>
        </div>

        <p class="text-xs text-n-slate-11 -mt-1">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.COLUMNS.ORDER_HINT') }}
        </p>

        <ColumnSelector
          v-model:items="dragList"
          :visible-keys="draftKeys"
          :pinned-column="showNameRow ? nameColumn : null"
          :is-filtering="isFiltering"
          :has-items="hasListItems"
          :empty-label="
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.COLUMNS.EMPTY_SEARCH')
          "
          @toggle="toggleColumn"
          @drag-start="onDragStart"
          @drag-end="onDragEnd"
        />
      </div>
    </template>
  </MenuPopover>
</template>
