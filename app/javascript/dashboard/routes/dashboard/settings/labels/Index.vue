<script setup>
import { useAlert } from 'dashboard/composables';
import { computed, onBeforeMount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { picoSearch } from '@chatwoot/pico-search';

import AddLabel from './AddLabel.vue';
import EditLabel from './EditLabel.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ListCard from 'dashboard/components-next/ListCard/ListCard.vue';
import InfoChip from 'dashboard/components-next/ListCard/InfoChip.vue';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();

const loading = ref({});
const showAddPopup = ref(false);
const showEditPopup = ref(false);
const showDeleteConfirmationPopup = ref(false);
const selectedLabel = ref({});
const searchQuery = ref('');

const records = computed(() => getters['labels/getLabels'].value);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;
  return picoSearch(records.value, query, [
    { name: 'title', weight: 4 },
    'description',
  ]);
});
const uiFlags = computed(() => getters['labels/getUIFlags'].value);

const deleteMessage = computed(() => ` ${selectedLabel.value.title}?`);

const openAddPopup = () => {
  showAddPopup.value = true;
};
const hideAddPopup = () => {
  showAddPopup.value = false;
};

const openEditPopup = response => {
  showEditPopup.value = true;
  selectedLabel.value = response;
};
const hideEditPopup = () => {
  showEditPopup.value = false;
};

const openDeletePopup = response => {
  showDeleteConfirmationPopup.value = true;
  selectedLabel.value = response;
};
const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const deleteLabel = async id => {
  try {
    await store.dispatch('labels/delete', id);
    useAlert(t('LABEL_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.message || t('LABEL_MGMT.DELETE.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  } finally {
    loading.value[selectedLabel.value.id] = false;
  }
};

const confirmDeletion = () => {
  loading.value[selectedLabel.value.id] = true;
  closeDeletePopup();
  deleteLabel(selectedLabel.value.id);
};

const getLabelMenuItems = label => [
  {
    action: 'edit',
    label: t('LABEL_MGMT.FORM.EDIT'),
    icon: 'i-lucide-pencil',
    disabled: !!loading.value[label.id],
  },
  {
    action: 'delete',
    label: t('LABEL_MGMT.FORM.DELETE'),
    icon: 'i-lucide-trash',
    disabled: !!loading.value[label.id],
  },
];

const handleLabelAction = (label, { action }) => {
  if (action === 'edit') openEditPopup(label);
  if (action === 'delete') openDeletePopup(label);
};

onBeforeMount(() => {
  store.dispatch('labels/get');
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('LABEL_MGMT.LOADING')"
    :no-records-found="!records.length"
    :no-records-message="$t('LABEL_MGMT.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('LABEL_MGMT.HEADER')"
        :description="$t('LABEL_MGMT.DESCRIPTION')"
        :link-text="$t('LABEL_MGMT.LEARN_MORE')"
        :search-placeholder="$t('LABEL_MGMT.SEARCH_PLACEHOLDER')"
        feature-name="labels"
      >
        <template v-if="records?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('LABEL_MGMT.COUNT', { n: records.length }) }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="$t('LABEL_MGMT.HEADER_BTN_TXT')"
            size="sm"
            @click="openAddPopup"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <p
        v-if="records.length && searchQuery && !filteredRecords.length"
        class="py-20 text-center text-body-main text-n-slate-11"
      >
        {{ $t('LABEL_MGMT.NO_RESULTS') }}
      </p>
      <div class="flex min-w-0 flex-col gap-3">
        <ListCard
          v-for="label in filteredRecords"
          :key="label.id"
          :title="label.title"
          :subtitle="label.description"
          :menu-items="getLabelMenuItems(label)"
          @action="handleLabelAction(label, $event)"
        >
          <template #avatar>
            <span
              :title="label.color"
              class="block size-10 shrink-0 rounded-full border border-n-weak"
              :style="{ backgroundColor: label.color }"
              aria-hidden="true"
            />
          </template>
          <template #chips>
            <InfoChip>
              <span
                class="me-1 size-2.5 shrink-0 rounded-full border border-n-weak"
                :style="{ backgroundColor: label.color }"
              />
              <span class="truncate">{{ label.color }}</span>
            </InfoChip>
            <InfoChip v-if="label.show_on_sidebar">
              {{ $t('LABEL_MGMT.FORM.SHOW_ON_SIDEBAR.LABEL') }}
            </InfoChip>
          </template>
        </ListCard>
      </div>
    </template>

    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddLabel @close="hideAddPopup" />
    </woot-modal>

    <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
      <EditLabel :selected-response="selectedLabel" @close="hideEditPopup" />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('LABEL_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('LABEL_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="$t('LABEL_MGMT.DELETE.CONFIRM.YES')"
      :reject-text="$t('LABEL_MGMT.DELETE.CONFIRM.NO')"
    />
  </SettingsLayout>
</template>
