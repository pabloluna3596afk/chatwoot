<script setup>
import { ref, computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';

const props = defineProps({
  activeSort: {
    type: String,
    default: 'last_activity_at',
  },
  activeOrdering: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:sort']);

const { t } = useI18n();

const isMenuOpen = ref(false);

const sortMenus = [
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.NAME'),
    value: 'name',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.EMAIL'),
    value: 'email',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.PHONE_NUMBER'),
    value: 'phone_number',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.DOCUMENT_NUMBER'),
    value: 'document_number',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.IDENTIFIER'),
    value: 'identifier',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.COMPANY'),
    value: 'company_name',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.COUNTRY'),
    value: 'country',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.CITY'),
    value: 'city',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.LABELS'),
    value: 'labels',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.ASSIGNED_AGENT'),
    value: 'assigned_agent',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.LAST_ACTIVITY'),
    value: 'last_activity_at',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.CREATED_AT'),
    value: 'created_at',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.OPTIONS.BLOCKED'),
    value: 'blocked',
  },
];

const orderingMenus = [
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.ORDER.OPTIONS.ASCENDING'),
    value: '',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.ORDER.OPTIONS.DESCENDING'),
    value: '-',
  },
];

// Converted the props to refs for better reactivity
const activeSort = toRef(props, 'activeSort');

const activeOrdering = toRef(props, 'activeOrdering');

const activeSortLabel = computed(() => {
  const selectedMenu = sortMenus.find(menu => menu.value === activeSort.value);
  return (
    selectedMenu?.label || t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.LABEL')
  );
});

const activeOrderingLabel = computed(() => {
  const selectedMenu = orderingMenus.find(
    menu => menu.value === activeOrdering.value
  );
  return selectedMenu?.label || t('CONTACTS_LAYOUT.HEADER.ACTIONS.ORDER.LABEL');
});

const handleSortChange = value => {
  emit('update:sort', { sort: value, order: props.activeOrdering });
};

const handleOrderChange = value => {
  emit('update:sort', { sort: props.activeSort, order: value });
};
</script>

<template>
  <MenuPopover
    v-model:open="isMenuOpen"
    :label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.LABEL')"
    panel-class="w-72 max-w-[calc(100vw-2rem)] p-4"
  >
    <template #trigger>
      <Button
        icon="i-lucide-arrow-down-up"
        color="slate"
        size="sm"
        variant="ghost"
        :class="isMenuOpen ? 'bg-n-alpha-2' : ''"
        @click="isMenuOpen = !isMenuOpen"
      />
    </template>
    <template #content>
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1.5 last:mt-4">
          <span class="text-sm text-n-slate-12">
            {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.SORT_BY.LABEL') }}
          </span>
          <SelectMenu
            class="w-full"
            sub-menu-position="bottom"
            :model-value="activeSort"
            :options="sortMenus"
            :label="activeSortLabel"
            @update:model-value="handleSortChange"
          />
        </div>
        <div class="flex flex-col gap-1.5 last:mt-4">
          <span class="text-sm text-n-slate-12">
            {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.ORDER.LABEL') }}
          </span>
          <SelectMenu
            class="w-full"
            sub-menu-position="bottom"
            :model-value="activeOrdering"
            :options="orderingMenus"
            :label="activeOrderingLabel"
            @update:model-value="handleOrderChange"
          />
        </div>
      </div>
    </template>
  </MenuPopover>
</template>
