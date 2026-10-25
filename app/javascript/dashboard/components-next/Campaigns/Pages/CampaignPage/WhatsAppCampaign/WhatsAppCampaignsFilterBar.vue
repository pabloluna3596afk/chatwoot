<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import SearchInput from 'dashboard/components-next/input/SearchInput.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const props = defineProps({
  campaigns: {
    type: Array,
    default: () => [],
  },
  inboxes: {
    type: Array,
    default: () => [],
  },
  filteredCount: {
    type: Number,
    default: 0,
  },
  hasActiveFilters: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['clearFilters']);

const STATUS_FILTERS = ['all', 'draft', 'active', 'processing', 'completed'];

const STATUS_LABEL_KEYS = {
  all: 'CAMPAIGN.WHATSAPP.LIST.FILTERS.ALL',
  draft: 'CAMPAIGN.WHATSAPP.LIST.STATUS.DRAFT',
  active: 'CAMPAIGN.WHATSAPP.LIST.STATUS.ACTIVE',
  processing: 'CAMPAIGN.WHATSAPP.LIST.STATUS.PROCESSING',
  completed: 'CAMPAIGN.WHATSAPP.LIST.STATUS.COMPLETED',
};

const searchQuery = defineModel('searchQuery', { type: String, default: '' });
const statusFilter = defineModel('statusFilter', {
  type: String,
  default: 'all',
});
const inboxId = defineModel('inboxId', { type: Number, default: null });

const { t } = useI18n();

const inboxMenuOpen = ref(false);

const showInboxFilter = computed(() => props.inboxes.length > 1);

const statusCounts = computed(() => {
  const counts = { all: props.campaigns.length };
  STATUS_FILTERS.slice(1).forEach(status => {
    counts[status] = props.campaigns.filter(
      c => c.campaign_status === status
    ).length;
  });
  return counts;
});

const statusTabs = computed(() =>
  STATUS_FILTERS.map(status => ({
    status,
    label: t(STATUS_LABEL_KEYS[status]),
    count: statusCounts.value[status],
  }))
);

const activeStatusTabIndex = computed(() =>
  Math.max(0, STATUS_FILTERS.indexOf(statusFilter.value || 'all'))
);

const countLabel = computed(() => {
  if (props.hasActiveFilters) {
    return t('CAMPAIGN.WHATSAPP.LIST.COUNT_FILTERED', props.filteredCount, {
      count: props.filteredCount,
    });
  }
  return t('CAMPAIGN.WHATSAPP.LIST.COUNT', props.campaigns.length, {
    count: props.campaigns.length,
  });
});

const selectedInboxLabel = computed(() => {
  if (!inboxId.value) return t('CAMPAIGN.WHATSAPP.LIST.FILTERS.INBOX_ALL');
  return (
    props.inboxes.find(inbox => inbox.id === inboxId.value)?.name ||
    t('CAMPAIGN.WHATSAPP.LIST.FILTERS.INBOX_ALL')
  );
});

const inboxMenuItems = computed(() => [
  {
    label: t('CAMPAIGN.WHATSAPP.LIST.FILTERS.INBOX_ALL'),
    value: null,
    action: 'inbox',
    isSelected: !inboxId.value,
  },
  ...props.inboxes.map(inbox => ({
    label: inbox.name,
    value: inbox.id,
    action: 'inbox',
    isSelected: inboxId.value === inbox.id,
  })),
]);

const handleStatusTabChange = tab => {
  statusFilter.value = tab.status;
};

const handleInboxSelect = ({ value }) => {
  inboxId.value = value;
  inboxMenuOpen.value = false;
};
</script>

<template>
  <div class="flex flex-col gap-4 pb-4 border-b border-n-weak">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <span class="text-sm font-medium text-n-slate-12">{{ countLabel }}</span>
      <div class="flex flex-wrap items-center gap-2">
        <SearchInput
          v-model="searchQuery"
          :placeholder="t('CAMPAIGN.WHATSAPP.LIST.FILTERS.SEARCH_PLACEHOLDER')"
          class="w-56 min-w-0"
          size="sm"
        />
        <MenuPopover
          v-if="showInboxFilter"
          v-model:open="inboxMenuOpen"
          :menu-items="inboxMenuItems"
          panel-class="min-w-48 max-w-[calc(100vw-2rem)]"
          align="start"
          @action="handleInboxSelect"
        >
          <template #trigger>
            <Button
              variant="outline"
              color="slate"
              size="sm"
              icon="i-lucide-inbox"
              class="!h-8"
              :class="inboxId ? 'text-n-slate-12' : 'text-n-slate-11'"
              @click="inboxMenuOpen = !inboxMenuOpen"
            >
              {{ selectedInboxLabel }}
            </Button>
          </template>
        </MenuPopover>
        <Button
          v-if="hasActiveFilters"
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-x"
          :label="t('CAMPAIGN.WHATSAPP.LIST.FILTERS.CLEAR')"
          @click="emit('clearFilters')"
        />
      </div>
    </div>
    <div class="overflow-x-auto no-scrollbar">
      <TabBar
        :tabs="statusTabs"
        :initial-active-tab="activeStatusTabIndex"
        @tab-changed="handleStatusTabChange"
      />
    </div>
  </div>
</template>
