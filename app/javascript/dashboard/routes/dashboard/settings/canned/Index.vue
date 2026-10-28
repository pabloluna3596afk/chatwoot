<script setup>
import { useAlert } from 'dashboard/composables';
import AddCanned from './AddCanned.vue';
import EditCanned from './EditCanned.vue';
import ToolList from 'dashboard/components-next/ToolList/ToolList.vue';
import ToolChip from 'dashboard/components-next/ToolList/ToolChip.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsFilterDropdown from '../components/SettingsFilterDropdown.vue';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useStoreGetters,
  useStore,
  useMapGetter,
} from 'dashboard/composables/store';
import { picoSearch } from '@chatwoot/pico-search';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

import Button from 'dashboard/components-next/button/Button.vue';

defineOptions({
  name: 'CannedResponseSettings',
});

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();
const { getPlainText } = useMessageFormatter();
const { isAdmin } = useAdmin();
const currentUser = useMapGetter('getCurrentUser');

const showAddPopup = ref(false);
const loading = ref({});
const showEditPopup = ref(false);
const showDeleteConfirmationPopup = ref(false);
const showRejectPopup = ref(false);
const rejectionReason = ref('');
const responseToReject = ref(null);
const activeResponse = ref({});
const cannedResponseAPI = ref({ message: '' });

const sortOrder = ref('asc');
const searchQuery = ref('');
const selectedCategory = ref('all');
const visibilityFilter = ref('all');

const records = computed(() =>
  getters.getSortedCannedResponses.value(sortOrder.value)
);

const normalizeCategory = value =>
  value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .replace(/\s+/g, ' ')
    .toLocaleLowerCase();

const categories = computed(() => {
  const unique = new Map();
  records.value.forEach(item => {
    if (!item.category) return;
    const category = item.category.trim().replace(/\s+/g, ' ');
    const key = normalizeCategory(category);
    if (!unique.has(key)) unique.set(key, category);
  });
  return [...unique.values()].sort((a, b) => a.localeCompare(b));
});

const hasUncategorized = computed(() =>
  records.value.some(item => !item.category)
);

const visibilityOptions = computed(() => {
  const filters = [
    { value: 'all', label: t('CANNED_MGMT.FILTER_VISIBILITY.ALL') },
    { value: 'mine', label: t('CANNED_MGMT.FILTER_VISIBILITY.MINE') },
    { value: 'account', label: t('CANNED_MGMT.FILTER_VISIBILITY.ACCOUNT') },
  ];
  if (isAdmin.value) {
    filters.splice(1, 0, {
      value: 'pending',
      label: t('CANNED_MGMT.FILTER_VISIBILITY.PENDING'),
    });
    filters.push(
      {
        value: 'approved',
        label: t('CANNED_MGMT.FILTER_VISIBILITY.APPROVED'),
      },
      {
        value: 'rejected',
        label: t('CANNED_MGMT.FILTER_VISIBILITY.REJECTED'),
      }
    );
  }
  return filters;
});

const categoryOptions = computed(() => {
  const options = [
    { value: 'all', label: t('CANNED_MGMT.ALL_CATEGORIES') },
    ...categories.value.map(category => ({
      value: category,
      label: category,
    })),
  ];
  if (hasUncategorized.value) {
    options.push({
      value: '',
      label: t('CANNED_MGMT.UNCATEGORIZED'),
    });
  }
  return options;
});

const visibilityFilteredRecords = computed(() => {
  const userId = currentUser.value?.id;
  if (visibilityFilter.value === 'mine') {
    return records.value.filter(item => item.created_by_id === userId);
  }
  if (visibilityFilter.value === 'account') {
    return records.value.filter(item => item.visibility === 'global');
  }
  if (visibilityFilter.value === 'pending') {
    return records.value.filter(item => item.approval_status === 'pending');
  }
  if (['approved', 'rejected'].includes(visibilityFilter.value)) {
    return records.value.filter(
      item => item.approval_status === visibilityFilter.value
    );
  }
  return records.value;
});

const categoryFilteredRecords = computed(() => {
  if (selectedCategory.value === 'all') return visibilityFilteredRecords.value;
  if (selectedCategory.value === '') {
    return visibilityFilteredRecords.value.filter(item => !item.category);
  }
  return visibilityFilteredRecords.value.filter(
    item =>
      normalizeCategory(item.category || '') ===
      normalizeCategory(selectedCategory.value)
  );
});

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return categoryFilteredRecords.value;
  return picoSearch(categoryFilteredRecords.value, query, [
    { name: 'short_code', weight: 4 },
    { name: 'category', weight: 2 },
    'content',
  ]);
});
const listColumns = computed(() => [
  { key: 'title', label: t('CANNED_MGMT.ADD.FORM.SHORT_CODE.LABEL') },
  { key: 'category', label: t('CANNED_MGMT.ADD.FORM.CATEGORY.LABEL') },
  { key: 'approval_status', label: t('CANNED_MGMT.TRACE.STATUS') },
  { key: 'visibility', label: t('CANNED_MGMT.TRACE.VISIBILITY') },
  { key: 'created_at', label: t('CANNED_MGMT.TRACE.CREATED') },
]);
const listActions = computed(() => [
  {
    key: 'edit',
    label: t('CANNED_MGMT.EDIT.BUTTON_TEXT'),
    visible: item =>
      isAdmin.value ||
      (item.visibility !== 'global' &&
        item.created_by_id === currentUser.value?.id),
  },
  { key: 'duplicate', label: t('CANNED_MGMT.DUPLICATE.TOOLTIP') },
  {
    key: 'approve-global',
    label: t('CANNED_MGMT.APPROVE.BUTTON'),
    variant: 'success',
    visible: item => isAdmin.value && item.approval_status === 'pending',
  },
  {
    key: 'approve-personal',
    label: t('CANNED_MGMT.APPROVE.PERSONAL'),
    variant: 'success',
    visible: item => isAdmin.value && item.approval_status === 'pending',
  },
  {
    key: 'reject',
    label: t('CANNED_MGMT.REJECT.BUTTON'),
    variant: 'danger',
    visible: item => isAdmin.value && item.approval_status === 'pending',
  },
  {
    key: 'delete',
    label: t('CANNED_MGMT.DELETE.BUTTON_TEXT'),
    variant: 'danger',
    visible: item =>
      isAdmin.value ||
      (item.visibility !== 'global' &&
        item.created_by_id === currentUser.value?.id),
  },
]);

const statusTone = status =>
  ({ pending: 'amber', approved: 'teal', rejected: 'ruby' })[status] ||
  'neutral';
const uiFlags = computed(() => getters.getUIFlags.value);

const deleteConfirmText = computed(
  () =>
    `${t('CANNED_MGMT.DELETE.CONFIRM.YES')} ${activeResponse.value.short_code}`
);

const deleteRejectText = computed(
  () =>
    `${t('CANNED_MGMT.DELETE.CONFIRM.NO')} ${activeResponse.value.short_code}`
);

const deleteMessage = computed(() => {
  return ` ${activeResponse.value.short_code} ? `;
});

const emptyListMessage = computed(() =>
  isAdmin.value ? t('CANNED_MGMT.LIST.404') : t('CANNED_MGMT.LIST.404_AGENT')
);

const fetchCannedResponses = async () => {
  try {
    await store.dispatch('getCannedResponse');
  } catch (error) {
    // Ignore Error
  }
};

onMounted(() => {
  fetchCannedResponses();
});

const showAlertMessage = message => {
  loading.value[activeResponse.value.id] = false;
  activeResponse.value = {};
  cannedResponseAPI.value.message = message;
  useAlert(message);
};

const openAddPopup = () => {
  showAddPopup.value = true;
};
const hideAddPopup = () => {
  showAddPopup.value = false;
};

const openEditPopup = response => {
  showEditPopup.value = true;
  activeResponse.value = response;
};
const hideEditPopup = () => {
  showEditPopup.value = false;
};

const openDeletePopup = response => {
  showDeleteConfirmationPopup.value = true;
  activeResponse.value = response;
};

const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const deleteCannedResponse = async id => {
  try {
    await store.dispatch('deleteCannedResponse', id);
    showAlertMessage(t('CANNED_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.message || t('CANNED_MGMT.DELETE.API.ERROR_MESSAGE');
    showAlertMessage(errorMessage);
  }
};

const confirmDeletion = () => {
  loading.value[activeResponse.value.id] = true;
  closeDeletePopup();
  deleteCannedResponse(activeResponse.value.id);
};

const approveResponse = async (item, visibility) => {
  loading.value[item.id] = true;
  try {
    await store.dispatch('approveCannedResponse', {
      id: item.id,
      visibility,
    });
    useAlert(t('CANNED_MGMT.APPROVE.SUCCESS'));
  } catch (error) {
    useAlert(error?.message || t('CANNED_MGMT.APPROVE.ERROR'));
  } finally {
    loading.value[item.id] = false;
  }
};

const rejectResponse = async item => {
  loading.value[item.id] = true;
  try {
    await store.dispatch('rejectCannedResponse', item.id);
    useAlert(t('CANNED_MGMT.REJECT.SUCCESS'));
  } catch (error) {
    useAlert(error?.message || t('CANNED_MGMT.REJECT.ERROR'));
  } finally {
    loading.value[item.id] = false;
  }
};

const openRejectPopup = item => {
  responseToReject.value = item;
  rejectionReason.value = '';
  showRejectPopup.value = true;
};

const confirmRejection = async () => {
  const item = responseToReject.value;
  showRejectPopup.value = false;
  await rejectResponse(item);
  responseToReject.value = null;
};

const formatDate = value =>
  value
    ? new Date(value).toLocaleDateString()
    : t('CANNED_MGMT.TRACE.NOT_AVAILABLE');

const personName = person => person?.available_name || person?.email || '';

const uniqueShortCode = baseCode => {
  const taken = new Set(records.value.map(item => item.short_code));
  let candidate = `${baseCode}_copy`;
  let n = 2;
  while (taken.has(candidate)) {
    candidate = `${baseCode}_copy_${n}`;
    n += 1;
  }
  return candidate;
};

const duplicateCanned = async item => {
  loading.value[item.id] = true;
  try {
    const visibility =
      item.visibility === 'global' && !isAdmin.value
        ? 'personal'
        : item.visibility || 'personal';

    await store.dispatch('createCannedResponse', {
      short_code: uniqueShortCode(item.short_code),
      content: item.content,
      category: item.category || null,
      visibility,
    });
    useAlert(
      isAdmin.value
        ? t('CANNED_MGMT.DUPLICATE.API.SUCCESS_MESSAGE')
        : t('CANNED_MGMT.DUPLICATE.API.SUCCESS_MESSAGE_PENDING')
    );
  } catch (error) {
    useAlert(error?.message || t('CANNED_MGMT.DUPLICATE.API.ERROR_MESSAGE'));
  } finally {
    loading.value[item.id] = false;
  }
};

const handleListAction = ({ action, item }) => {
  if (action === 'edit') openEditPopup(item);
  if (action === 'duplicate') duplicateCanned(item);
  if (action === 'approve-global') approveResponse(item, 'global');
  if (action === 'approve-personal') approveResponse(item, 'personal');
  if (action === 'reject') openRejectPopup(item);
  if (action === 'delete') openDeletePopup(item);
};
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.fetchingList"
    :loading-message="$t('CANNED_MGMT.LOADING')"
    :no-records-found="!records.length"
    :no-records-message="emptyListMessage"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('CANNED_MGMT.HEADER')"
        :description="$t('CANNED_MGMT.DESCRIPTION')"
        :link-text="$t('CANNED_MGMT.LEARN_MORE')"
        :search-placeholder="$t('CANNED_MGMT.SEARCH_PLACEHOLDER')"
        feature-name="canned_responses"
      >
        <template v-if="records.length" #tabs>
          <div class="flex items-center gap-2">
            <SettingsFilterDropdown
              v-model="visibilityFilter"
              :options="visibilityOptions"
              icon="i-lucide-eye"
              action-key="visibility"
            />
            <SettingsFilterDropdown
              v-if="categories.length || hasUncategorized"
              v-model="selectedCategory"
              :options="categoryOptions"
              icon="i-lucide-tags"
              action-key="category"
            />
          </div>
        </template>
        <template v-if="filteredRecords.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('CANNED_MGMT.COUNT', { n: filteredRecords.length }) }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="$t('CANNED_MGMT.HEADER_BTN_TXT')"
            size="sm"
            @click="openAddPopup"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div
        v-if="!filteredRecords.length && !uiFlags.fetchingList"
        class="flex items-center justify-center p-8"
      >
        <span class="text-base text-n-slate-11">
          {{
            !records.length
              ? emptyListMessage
              : searchQuery ||
                  selectedCategory !== 'all' ||
                  visibilityFilter !== 'all'
                ? $t('CANNED_MGMT.NO_RESULTS')
                : emptyListMessage
          }}
        </span>
      </div>
      <div v-else class="border-t border-n-weak">
        <ToolList
          :items="filteredRecords"
          :columns="listColumns"
          :actions="listActions"
          :loading="uiFlags.fetchingList"
          :empty-message="$t('CANNED_MGMT.NO_RESULTS')"
          :more-options-label="$t('CANNED_MGMT.MORE_OPTIONS')"
          @action="handleListAction"
        >
          <template #lead="{ item }">
            <div class="flex min-w-0 items-center gap-3">
              <Avatar
                :name="personName(item.created_by)"
                :src="item.created_by?.avatar_url"
                :size="32"
                rounded-full
              />
              <div class="min-w-0">
                <div class="truncate font-medium text-n-slate-12">
                  {{ item.short_code }}
                </div>
                <div class="truncate text-xs text-n-slate-10">
                  {{ getPlainText(item.content) }}
                </div>
              </div>
            </div>
          </template>
          <template #cell-category="{ item }">
            <span
              v-if="item.category"
              class="inline-flex rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
            >
              {{ item.category }}
            </span>
            <span v-else class="text-n-slate-10">
              {{ $t('CANNED_MGMT.TRACE.NOT_AVAILABLE') }}
            </span>
          </template>
          <template #cell-approval_status="{ item }">
            <ToolChip :tone="statusTone(item.approval_status)">
              {{ $t(`CANNED_MGMT.STATUS_LABEL.${item.approval_status}`) }}
            </ToolChip>
          </template>
          <template #cell-visibility="{ item }">
            <ToolChip>
              {{ $t(`CANNED_MGMT.VISIBILITY_LABEL.${item.visibility}`) }}
            </ToolChip>
          </template>
          <template #cell-created_at="{ item }">
            <div>{{ formatDate(item.created_at) }}</div>
            <div class="text-xs text-n-slate-10">
              {{ personName(item.created_by) }}
            </div>
            <div v-if="item.reviewed_at" class="mt-1 text-xs text-n-slate-10">
              {{ $t('CANNED_MGMT.TRACE.REVIEWED') }}
              {{ personName(item.reviewed_by) }}
            </div>
            <div v-if="item.reviewed_at" class="text-xs text-n-slate-10">
              {{ formatDate(item.reviewed_at) }}
            </div>
          </template>
        </ToolList>
      </div>
    </template>
    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddCanned :categories="categories" :on-close="hideAddPopup" />
    </woot-modal>

    <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
      <EditCanned
        v-if="showEditPopup"
        :id="activeResponse.id"
        :edshort-code="activeResponse.short_code"
        :edcontent="activeResponse.content"
        :edcategory="activeResponse.category"
        :edvisibility="activeResponse.visibility"
        :categories="categories"
        :on-close="hideEditPopup"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('CANNED_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('CANNED_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
    />
    <woot-modal v-model:show="showRejectPopup">
      <div class="flex flex-col gap-4 p-6">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ $t('CANNED_MGMT.REJECT.TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ $t('CANNED_MGMT.REJECT.REASON_NOT_SAVED') }}
        </p>
        <label class="flex flex-col gap-2 text-sm text-n-slate-12">
          {{ $t('CANNED_MGMT.REJECT.REASON_LABEL') }}
          <textarea v-model="rejectionReason" class="min-h-20" />
        </label>
        <div class="flex justify-end gap-2">
          <Button
            :label="$t('CANNED_MGMT.ADD.CANCEL_BUTTON_TEXT')"
            intent="secondary"
            @click="showRejectPopup = false"
          />
          <Button
            :label="$t('CANNED_MGMT.REJECT.BUTTON')"
            intent="destructive"
            @click="confirmRejection"
          />
        </div>
      </div>
    </woot-modal>
  </SettingsLayout>
</template>
