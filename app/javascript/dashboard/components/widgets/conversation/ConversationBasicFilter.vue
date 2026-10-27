<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter, useStore } from 'dashboard/composables/store.js';
import { useStatusLabel } from 'dashboard/composables/useStatusLabel';
import wootConstants from 'dashboard/constants/globals';
import { buildConversationSortOptions } from 'dashboard/helper/conversationSortOptions';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';

defineProps({
  isOnExpandedLayout: {
    type: Boolean,
    required: true,
  },
  showStatusFilter: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['changeFilter']);

const store = useStore();
const { t } = useI18n();
const { getStatusLabel } = useStatusLabel();

const { updateUISettings } = useUISettings();

const chatStatusFilter = useMapGetter('getChatStatusFilter');
const chatSortFilter = useMapGetter('getChatSortFilter');
const getAttributesByModel = useMapGetter('attributes/getAttributesByModel');

const showActionsDropdown = ref(false);

const currentStatusFilter = computed(() => {
  return chatStatusFilter.value || wootConstants.STATUS_TYPE.OPEN;
});

const currentSortBy = computed(() => {
  return (
    chatSortFilter.value || wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC
  );
});

const chatStatusOptions = computed(() => [
  {
    label: getStatusLabel('open'),
    value: 'open',
  },
  {
    label: getStatusLabel('resolved'),
    value: 'resolved',
  },
  {
    label: getStatusLabel('pending'),
    value: 'pending',
  },
  {
    label: getStatusLabel('snoozed'),
    value: 'snoozed',
  },
  {
    label: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.all.TEXT'),
    value: 'all',
  },
]);

const conversationAttributeDefs = computed(() => {
  const getter = getAttributesByModel.value;
  return typeof getter === 'function'
    ? getter('conversation_attribute') || []
    : [];
});

const chatSortOptions = computed(() =>
  buildConversationSortOptions(t, conversationAttributeDefs.value)
);

const activeChatStatusLabel = computed(
  () =>
    chatStatusOptions.value.find(m => m.value === chatStatusFilter.value)
      ?.label || ''
);

const activeChatSortLabel = computed(
  () =>
    chatSortOptions.value.find(m => m.value === chatSortFilter.value)?.label ||
    ''
);

const saveSelectedFilter = (type, value) => {
  updateUISettings({
    conversations_filter_by: {
      status: type === 'status' ? value : currentStatusFilter.value,
      order_by: type === 'sort' ? value : currentSortBy.value,
    },
  });
};

const handleStatusChange = value => {
  emit('changeFilter', value, 'status');
  store.dispatch('setChatStatusFilter', value);
  saveSelectedFilter('status', value);
};

const handleSortChange = value => {
  emit('changeFilter', value, 'sort');
  store.dispatch('setChatSortFilter', value);
  saveSelectedFilter('sort', value);
};
</script>

<template>
  <MenuPopover
    v-model:open="showActionsDropdown"
    :label="$t('CHAT_LIST.SORT_TOOLTIP_LABEL')"
    :align="isOnExpandedLayout ? 'end' : 'start'"
    panel-class="w-72 max-w-[calc(100vw-2rem)] p-4"
  >
    <template #trigger>
      <NextButton
        v-tooltip.right="$t('CHAT_LIST.SORT_TOOLTIP_LABEL')"
        icon="i-lucide-arrow-up-down"
        slate
        faded
        xs
        @click="showActionsDropdown = !showActionsDropdown"
      />
    </template>
    <template #content>
      <div class="flex flex-col gap-4">
        <div v-if="showStatusFilter" class="flex flex-col gap-1.5 last:mt-4">
          <span class="text-sm text-n-slate-12">
            {{ $t('CHAT_LIST.CHAT_SORT.STATUS') }}
          </span>
          <SelectMenu
            class="w-full"
            :model-value="chatStatusFilter"
            :options="chatStatusOptions"
            :label="activeChatStatusLabel"
            sub-menu-position="bottom"
            @update:model-value="handleStatusChange"
          />
        </div>
        <div class="flex flex-col gap-1.5 last:mt-4">
          <span class="text-sm text-n-slate-12">
            {{ $t('CHAT_LIST.CHAT_SORT.ORDER_BY') }}
          </span>
          <SelectMenu
            class="w-full"
            :model-value="chatSortFilter"
            :options="chatSortOptions"
            :label="activeChatSortLabel"
            sub-menu-position="bottom"
            @update:model-value="handleSortChange"
          />
        </div>
      </div>
    </template>
  </MenuPopover>
</template>
