<script setup>
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import {
  STANDARD_CONTACT_CONVERSATION_COLUMNS,
  buildConversationHistoryColumns,
  resolveHistoryVisibleColumns,
  HISTORY_COLUMNS_UI_SETTING,
} from 'dashboard/helper/contactConversationTableColumns';

import Draggable from 'vuedraggable';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const getAttributesByModel = useMapGetter('attributes/getAttributesByModel');

const isMenuOpen = ref(false);
const searchQuery = ref('');
const dragging = ref(false);
const draftKeys = ref([]);
const orderedAllKeys = ref([]);
const dragList = ref([]);
const filterText = computed(() => searchQuery.value.trim().toLowerCase());
const isFiltering = computed(() => Boolean(filterText.value));

const matchesSearch = label =>
  !filterText.value || (label || '').toLowerCase().includes(filterText.value);

const conversationAttributeDefs = computed(() => {
  const getter = getAttributesByModel.value;
  return typeof getter === 'function'
    ? getter('conversation_attribute') || []
    : [];
});

const allColumns = computed(() => {
  const defs = buildConversationHistoryColumns(conversationAttributeDefs.value);
  return defs.map(col => ({
    ...col,
    label:
      col.label || t(`CONTACTS_LAYOUT.SIDEBAR.HISTORY.COLUMNS.${col.labelKey}`),
  }));
});

const columnByKey = computed(() =>
  Object.fromEntries(allColumns.value.map(col => [col.key, col]))
);

const availableKeys = computed(() => allColumns.value.map(col => col.key));

const resolvedKeys = computed(() =>
  resolveHistoryVisibleColumns(
    uiSettings.value?.[HISTORY_COLUMNS_UI_SETTING],
    availableKeys.value
  )
);

const ensureIdFirst = keys => {
  const withoutId = keys.filter(key => key !== 'id');
  return availableKeys.value.includes('id') ? ['id', ...withoutId] : withoutId;
};

const syncOrderedAllKeys = visibleKeys => {
  const available = availableKeys.value;
  const availableSet = new Set(available);
  const prev = orderedAllKeys.value.filter(key => availableSet.has(key));

  if (!prev.length) {
    const visible = visibleKeys.filter(key => availableSet.has(key));
    const visibleSet = new Set(visible);
    const hidden = available.filter(key => !visibleSet.has(key));
    orderedAllKeys.value = ensureIdFirst([...visible, ...hidden]);
    return;
  }

  const prevSet = new Set(prev);
  const appended = available.filter(key => !prevSet.has(key));
  orderedAllKeys.value = ensureIdFirst([...prev, ...appended]);
};

const rebuildDragList = () => {
  dragList.value = orderedAllKeys.value
    .filter(key => key !== 'id')
    .map(key => columnByKey.value[key])
    .filter(Boolean)
    .filter(col => matchesSearch(col.label));
};

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

const idColumn = computed(() => columnByKey.value.id);

const showIdRow = computed(
  () => idColumn.value && matchesSearch(idColumn.value.label)
);

const visibleCount = computed(() => draftKeys.value.length);

const isChecked = key => visibleSet.value.has(key);

const isRequired = key =>
  STANDARD_CONTACT_CONVERSATION_COLUMNS.find(col => col.key === key)
    ?.required === true;

const persist = keys => {
  let next = [...keys];
  if (!next.includes('id') && availableKeys.value.includes('id')) {
    next = ['id', ...next.filter(k => k !== 'id')];
  }
  draftKeys.value = next;
  updateUISettings({ [HISTORY_COLUMNS_UI_SETTING]: next });
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
  persist(orderedAllKeys.value.filter(k => visible.has(k)));
};

const selectDefaults = () => {
  const defaults = resolveHistoryVisibleColumns(null, availableKeys.value);
  orderedAllKeys.value = ensureIdFirst([
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
    key => key !== 'id' && !reordered.includes(key)
  );
  orderedAllKeys.value = ensureIdFirst([...reordered, ...remaining]);
  persistVisibleFromOrder();
};

const hasListItems = computed(
  () => showIdRow.value || dragList.value.length > 0
);
</script>

<template>
  <MenuPopover
    v-model:open="isMenuOpen"
    :dismissible="!dragging"
    :label="t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.COLUMNS_MENU.LABEL')"
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
        :title="t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.COLUMNS_MENU.LABEL')"
        @click="isMenuOpen = !isMenuOpen"
      />
    </template>
    <template #content>
      <div class="flex flex-col gap-3 px-2 pb-2 overflow-y-auto min-h-0">
        <div class="flex items-start justify-between gap-2 shrink-0">
          <div class="min-w-0">
            <p class="text-sm font-medium text-n-slate-12">
              {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.COLUMNS_MENU.LABEL') }}
            </p>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{
                t(
                  'CONTACTS_LAYOUT.SIDEBAR.HISTORY.COLUMNS_MENU.VISIBLE_COUNT',
                  {
                    count: visibleCount,
                  }
                )
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

        <p class="text-xs text-n-slate-11 -mt-1 shrink-0">
          {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.COLUMNS_MENU.ORDER_HINT') }}
        </p>

        <div
          class="flex flex-col gap-0.5 overflow-y-auto min-h-0 flex-1 pr-0.5 -mr-0.5 p-1"
        >
          <label
            v-if="showIdRow"
            class="flex items-center gap-2 rounded-lg px-1.5 py-1.5 opacity-60 cursor-not-allowed"
          >
            <span
              class="inline-flex size-5 shrink-0 items-center justify-center text-n-slate-10"
              aria-hidden="true"
            >
              <span class="i-lucide-pin size-3.5" />
            </span>
            <Checkbox model-value disabled />
            <span class="truncate text-sm text-n-slate-12">
              {{ idColumn.label }}
            </span>
          </label>

          <Draggable
            v-model="dragList"
            item-key="key"
            :disabled="isFiltering"
            :animation="200"
            force-fallback
            filter=".column-no-drag"
            :prevent-on-filter="false"
            ghost-class="opacity-50"
            class="flex flex-col gap-0.5"
            @start="onDragStart"
            @end="onDragEnd"
          >
            <template #item="{ element: column }">
              <div
                class="flex items-center gap-2 rounded-lg px-1.5 py-1.5 hover:bg-n-alpha-2 select-none"
                :class="
                  isFiltering
                    ? 'cursor-default'
                    : 'cursor-grab active:cursor-grabbing'
                "
              >
                <span
                  class="inline-flex size-5 shrink-0 items-center justify-center text-n-slate-11"
                  :class="isFiltering ? 'opacity-40' : ''"
                  aria-hidden="true"
                >
                  <span class="i-lucide-grip-vertical size-3.5" />
                </span>
                <label
                  class="column-no-drag flex min-w-0 flex-1 items-center gap-2.5 text-sm text-n-slate-12 cursor-pointer"
                >
                  <Checkbox
                    :model-value="isChecked(column.key)"
                    @change="
                      event => toggleColumn(column.key, event.target.checked)
                    "
                  />
                  <span class="truncate">{{ column.label }}</span>
                </label>
              </div>
            </template>
          </Draggable>

          <p
            v-if="!hasListItems"
            class="text-sm text-n-slate-11 text-center py-6"
          >
            {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.COLUMNS.EMPTY_SEARCH') }}
          </p>
        </div>
      </div>
    </template>
  </MenuPopover>
</template>
