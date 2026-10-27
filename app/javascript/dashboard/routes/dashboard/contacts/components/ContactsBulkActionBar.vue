<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import BulkSelectBar from 'dashboard/components-next/captain/assistant/BulkSelectBar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BulkLabelActions from 'dashboard/components/widgets/conversation/conversationBulkActions/BulkLabelActions.vue';
import Policy from 'dashboard/components/policy.vue';

const props = defineProps({
  visibleContactIds: {
    type: Array,
    default: () => [],
  },
  selectedContactIds: {
    type: Array,
    default: () => [],
  },
  totalMatchingCount: {
    type: Number,
    default: 0,
  },
  selectAllMatching: {
    type: Boolean,
    default: false,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'clearSelection',
  'assignLabels',
  'removeLabels',
  'toggleAll',
  'selectAllMatching',
  'deleteSelected',
]);

const { t } = useI18n();

const normalizeId = id => Number(id);

const selectedCount = computed(() =>
  props.selectAllMatching
    ? props.totalMatchingCount
    : props.selectedContactIds.length
);
const totalVisibleContacts = computed(() => props.visibleContactIds.length);

const showSelectAllMatching = computed(
  () =>
    props.totalMatchingCount > totalVisibleContacts.value &&
    !props.selectAllMatching
);

const selectAllLabel = computed(() => {
  if (!totalVisibleContacts.value) {
    return '';
  }

  return t('CONTACTS_BULK_ACTIONS.SELECT_ALL', {
    count: totalVisibleContacts.value,
  });
});

const selectedCountLabel = computed(() =>
  t('CONTACTS_BULK_ACTIONS.SELECTED_COUNT', {
    count: selectedCount.value,
  })
);

const allItems = computed(() =>
  props.visibleContactIds.map(id => ({
    id: normalizeId(id),
  }))
);

const selectionModel = computed({
  get: () => new Set(props.selectedContactIds.map(normalizeId)),
  set: newSet => {
    if (!props.visibleContactIds.length) {
      emit('toggleAll', false);
      return;
    }

    const shouldSelectAll = props.visibleContactIds.every(id =>
      newSet.has(normalizeId(id))
    );
    emit('toggleAll', shouldSelectAll);
  },
});

const handleAssignLabels = labels => {
  emit('assignLabels', labels);
};

const handleRemoveLabels = labels => {
  emit('removeLabels', labels);
};
</script>

<template>
  <div
    class="z-30 pt-1 pb-2 md:sticky md:top-0 md:z-10 md:bg-gradient-to-b md:from-n-surface-1 md:from-90% md:to-transparent"
  >
    <BulkSelectBar
      v-model="selectionModel"
      :all-items="allItems"
      compact-selection
      :select-all-label="selectAllLabel"
      :selected-count-label="selectedCountLabel"
      class="py-2 ltr:!pr-3 rtl:!pl-3 justify-between border border-n-weak shadow-lg md:shadow-sm max-md:fixed max-md:inset-x-3 max-md:bottom-[calc(env(safe-area-inset-bottom)+5.75rem)] max-md:z-50 max-md:!m-0 max-md:rounded-xl max-md:bg-n-solid-2 max-md:backdrop-blur-md"
    >
      <template #primaryActions>
        <Button
          sm
          ghost
          slate
          icon="i-lucide-x"
          :label="t('CONTACTS_BULK_ACTIONS.CLEAR_SELECTION')"
          :aria-label="t('CONTACTS_BULK_ACTIONS.CLEAR_SELECTION')"
          class="!px-1 [&>span:nth-child(2)]:hidden md:[&>span:nth-child(2)]:inline-flex"
          @click="emit('clearSelection')"
        />
        <Button
          v-if="showSelectAllMatching"
          sm
          ghost
          blue
          :label="
            t('CONTACTS_BULK_ACTIONS.SELECT_ALL_MATCHING', {
              count: totalMatchingCount,
            })
          "
          class="!px-1"
          @click="emit('selectAllMatching')"
        />
      </template>
      <template #actions>
        <div class="flex items-center gap-2 ml-auto">
          <BulkLabelActions
            type="contact"
            placement="bottom"
            :is-loading="isLoading"
            :disabled="!selectedCount"
            @assign="handleAssignLabels"
          />
          <BulkLabelActions
            type="contact"
            placement="bottom"
            action="remove"
            :is-loading="isLoading"
            :disabled="!selectedCount"
            @remove="handleRemoveLabels"
          />
          <div class="w-px h-3 bg-n-weak rounded-lg" />
          <Policy :permissions="['administrator']">
            <Button
              v-tooltip.bottom="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              sm
              ghost
              ruby
              icon="i-lucide-trash"
              :label="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              :aria-label="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              :disabled="!selectedCount || isLoading || selectAllMatching"
              :is-loading="isLoading"
              class="!px-2 [&>span:nth-child(2)]:hidden md:[&>span:nth-child(2)]:inline-flex"
              @click="emit('deleteSelected')"
            />
          </Policy>
        </div>
      </template>
    </BulkSelectBar>
  </div>
</template>
