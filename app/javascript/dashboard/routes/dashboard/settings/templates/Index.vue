<script setup>
import { computed, onActivated, onDeactivated, ref, watch } from 'vue';
import { picoSearch } from '@chatwoot/pico-search';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { useWhatsAppTemplateSync } from 'dashboard/composables/useWhatsAppTemplateSync';
import InboxesAPI from 'dashboard/api/inboxes';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import DraftsAPI from 'dashboard/api/whatsappTemplateDrafts';
import { draftRow, LOCAL_STATUSES, META_STATUSES } from './templateDrafts';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import TemplatePendingIndicator from './TemplatePendingIndicator.vue';
import {
  templateDataEligible,
  templateVariables,
  hasPendingVariables,
} from './templateData';
import TemplatesTable from './TemplatesTable.vue';
import TemplatesToolbar from './TemplatesToolbar.vue';
import { templateTableColumns } from './templateTableColumns';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import TemplateRowActions from './TemplateRowActions.vue';
import TemplatePreviewDrawer from './TemplatePreviewDrawer.vue';
import TemplateFormDrawer from './TemplateFormDrawer.vue';
import PresetsPanel from './PresetsPanel.vue';
import FlowsPanel from './flows/FlowsPanel.vue';
import SyncStatus from 'dashboard/components-next/whatsapp/sync-status/SyncStatus.vue';
import { isEditable } from './templateForm';
import { presetToForm } from './presets';
import {
  formatTemplateDate,
  formatTemplateLabel,
  templateStatusClasses,
  formatTemplateLanguage,
  groupTemplates,
  templateTypeKey,
} from './templateUtils';

const FUZZY_SEARCH_KEYS = [
  { name: 'name', weight: 4 },
  'category',
  'language',
  'status',
  'inboxNames',
  'searchableContent',
];

const store = useStore();
const route = useRoute();
const { t, te } = useI18n();

const { checkPermissions } = usePolicy();
const { isSyncing, canSync, whatsappInboxes, syncTemplates } =
  useWhatsAppTemplateSync();

// Templates are managed (created, edited, deleted) only by administrators, only on WhatsApp Cloud channels.
const isAdmin = computed(() => checkPermissions(['administrator']));
const cloudInboxes = computed(() =>
  whatsappInboxes.value.filter(inbox => inbox.provider === 'whatsapp_cloud')
);
const cloudInboxFor = template =>
  cloudInboxes.value.find(inbox =>
    template.inboxes.some(owner => owner.id === inbox.id)
  );
const canManage = template =>
  isAdmin.value && (template.isLocalDraft || Boolean(cloudInboxFor(template)));
const canEdit = template =>
  isAdmin.value &&
  (template.isLocalDraft ||
    (canManage(template) && isEditable(template)) ||
    (templateDataEligible(template) && templateVariables(template).length > 0));

const templates = ref([]);
const drafts = ref([]);
const allTemplates = computed(() => [
  ...(isAdmin.value
    ? drafts.value.map(draft => draftRow(draft, cloudInboxes.value))
    : []),
  ...templates.value,
]);
const selectedStatus = ref('all');
const stateOptions = computed(() => [
  { value: 'all', label: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.ALL_STATUSES') },
  ...LOCAL_STATUSES.map(value => ({
    value,
    label: t(
      value === 'draft'
        ? 'WHATSAPP_TEMPLATE_MGMT.DRAFTS.DRAFTS_FILTER'
        : 'WHATSAPP_TEMPLATE_MGMT.DRAFTS.STATUS.' + value.toUpperCase()
    ),
  })),
  ...META_STATUSES.map(value => ({
    value,
    label: t('WHATSAPP_TEMPLATE_MGMT.STATUS.' + value),
  })),
]);
const remoteStatus = item =>
  item.isLocalDraft ? item.remoteStatus : item.status;
const remoteStatusLabel = item => {
  const status = remoteStatus(item);
  if (!status) return formatTemplateLabel(null);
  const key = 'WHATSAPP_TEMPLATE_MGMT.STATUS.' + status.toUpperCase();
  return te(key) ? t(key) : status;
};
const searchQuery = ref(route.query.q || '');
const missingOnly = ref(route.query.filter === 'missing');
const missingCount = computed(
  () => templates.value.filter(hasPendingVariables).length
);
const selectedTemplate = ref(null);
const selectedInboxId = ref('all');
const selectedLanguage = ref('all');
const selectedType = ref('all');
const selectedCategory = ref('all');
const templatePage = ref(1);
const templatePageSize = ref(10);
const categoryOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_CATEGORIES'),
    count: allTemplates.value.length,
  },
  ...['UTILITY', 'MARKETING', 'AUTHENTICATION'].map(value => ({
    value,
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.CATEGORIES.' + value),
    count: allTemplates.value.filter(
      item => item.category?.toUpperCase() === value
    ).length,
  })),
]);
const columns = computed(() => {
  const labels = {
    STATUS: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.LOCAL_STATUS'),
    UPDATED: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.LAST_EDITED'),
  };
  return templateTableColumns(t, ['LANGUAGE', 'TYPE'])
    .map(column => ({ ...column, label: labels[column.key] || column.label }))
    .flatMap(column =>
      column.key === 'STATUS'
        ? [
            column,
            {
              key: 'META_STATUS',
              label: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.META_STATUS'),
            },
          ]
        : [column]
    );
});
const actionLabels = computed(() => ({
  edit: t('WHATSAPP_TEMPLATE_MGMT.EDIT'),
  duplicate: t('WHATSAPP_TEMPLATE_MGMT.DUPLICATE'),
  delete: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DELETE_REMOTE'),
}));
const rowLabels = item =>
  item.isLocalDraft
    ? {
        edit: t('WHATSAPP_TEMPLATE_MGMT.EDIT'),
        duplicate: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DUPLICATE'),
        delete: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DELETE'),
      }
    : actionLabels.value;

const previewPanelRef = ref(null);
const flowsPanel = ref(null);
const formDrawerRef = ref(null);
const deleteDialogRef = ref(null);
const templateToDelete = ref(null);
const isDeleting = ref(false);
const templateRecordsByInboxId = new Map();
const lastSyncAttemptsByInboxId = ref({});
const {
  run: runTemplateRequest,
  abort: abortTemplateRequest,
  isPending: isLoading,
} = useAbortableRequest();

const hasTemplates = computed(() => allTemplates.value.length > 0);

const lastSyncAttemptAt = computed(() => {
  const timestamps = Object.values(lastSyncAttemptsByInboxId.value)
    .filter(Boolean)
    .map(value => new Date(value).getTime())
    .filter(Number.isFinite);

  return timestamps.length ? new Date(Math.max(...timestamps)) : null;
});

const typeLabels = computed(() => ({
  TEXT: t('WHATSAPP_TEMPLATE_MGMT.TYPES.TEXT'),
  IMAGE: t('WHATSAPP_TEMPLATE_MGMT.TYPES.IMAGE'),
  VIDEO: t('WHATSAPP_TEMPLATE_MGMT.TYPES.VIDEO'),
  DOCUMENT: t('WHATSAPP_TEMPLATE_MGMT.TYPES.DOCUMENT'),
  MEDIA: t('WHATSAPP_TEMPLATE_MGMT.TYPES.MEDIA'),
  QUICK_REPLY: t('WHATSAPP_TEMPLATE_MGMT.TYPES.QUICK_REPLY'),
  CALL_TO_ACTION: t('WHATSAPP_TEMPLATE_MGMT.TYPES.CALL_TO_ACTION'),
  CATALOG: t('WHATSAPP_TEMPLATE_MGMT.TYPES.CATALOG'),
  COPY_CODE: t('WHATSAPP_TEMPLATE_MGMT.TYPES.COPY_CODE'),
}));

const inboxOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_INBOXES'),
  },
  ...(isAdmin.value
    ? [{ value: 'none', label: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.NO_CHANNEL') }]
    : []),
  ...whatsappInboxes.value.map(inbox => ({
    value: String(inbox.id),
    label: inbox.name,
  })),
]);

const languageOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_LANGUAGES'),
  },
  ...[...new Set(allTemplates.value.map(template => template.language))]
    .filter(Boolean)
    .sort()
    .map(language => ({
      value: language,
      label: formatTemplateLanguage(language),
    })),
]);

const typeOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_TYPES'),
  },
  ...[...new Set(allTemplates.value.map(templateTypeKey))]
    .map(type => ({
      value: type,
      label: typeLabels.value[type],
    }))
    .sort((first, second) => first.label.localeCompare(second.label)),
]);

const openPreview = template => {
  if (isAdmin.value && template.isLocalDraft) {
    formDrawerRef.value?.openDraft(template);
    return;
  }
  if (canManage(template)) {
    formDrawerRef.value?.open(template);
    return;
  }
  selectedTemplate.value = template;
  previewPanelRef.value?.open();
};

const openCreate = () => formDrawerRef.value?.open();

// Templates, ready-made presets and flows are the tabs of the page. Only administrators see the tabs: the presets need
// no channel to prepare a draft; the flows are ChatHub's own.
// The builder's back arrow comes back to the Flows tab (?tab=flows).
const activeTab = ref(
  isAdmin.value && route.query.tab === 'flows' ? 'flows' : 'templates'
);
const showTabs = computed(() => isAdmin.value);
const showTemplates = computed(
  () => !showTabs.value || activeTab.value === 'templates'
);
const showPresets = computed(
  () => showTabs.value && activeTab.value === 'presets'
);
const showFlows = computed(() => showTabs.value && activeTab.value === 'flows');
const createAction = computed(() => {
  return isAdmin.value
    ? { label: t('WHATSAPP_TEMPLATE_MGMT.NEW_TEMPLATE'), run: openCreate }
    : null;
});
const tabs = computed(() => [
  { key: 'templates', label: t('WHATSAPP_TEMPLATE_MGMT.TABS.TEMPLATES') },
  { key: 'presets', label: t('WHATSAPP_TEMPLATE_MGMT.TABS.PRESETS') },
  { key: 'flows', label: t('WHATSAPP_FLOWS.TAB') },
]);
const tabIndex = computed(() =>
  tabs.value.findIndex(tab => tab.key === activeTab.value)
);
const onTabChanged = tab => {
  activeTab.value = tab.key;
};
const applyPreset = preset =>
  formDrawerRef.value?.open(null, presetToForm(preset));
const duplicateTemplate = template =>
  formDrawerRef.value?.openDuplicate(template);
const openEdit = template =>
  template.isLocalDraft
    ? formDrawerRef.value?.openDraft(template)
    : formDrawerRef.value?.openBindings(template);
const openedLinkedTemplate = ref(false);
watch(templates, records => {
  if (
    openedLinkedTemplate.value ||
    route.query.filter !== 'missing' ||
    !route.query.q
  )
    return;
  const matches = records.filter(
    template => template.name === route.query.q && canEdit(template)
  );
  if (matches.length !== 1) return;
  openedLinkedTemplate.value = true;
  openEdit(matches[0]);
});
const askDelete = template => {
  templateToDelete.value = template;
  deleteDialogRef.value?.open();
};

const filteredTemplates = computed(() => {
  let records = allTemplates.value;
  if (selectedStatus.value !== 'all') {
    records = records.filter(template =>
      LOCAL_STATUSES.includes(selectedStatus.value)
        ? template.isLocalDraft && template.status === selectedStatus.value
        : (template.isLocalDraft
            ? template.remoteStatus
            : template.status
          )?.toUpperCase() === selectedStatus.value
    );
  }
  if (missingOnly.value)
    records = records
      .filter(hasPendingVariables)
      .sort(
        (a, b) =>
          Number(b.category === 'UTILITY') - Number(a.category === 'UTILITY')
      );

  if (selectedInboxId.value !== 'all') {
    records = records.filter(template =>
      selectedInboxId.value === 'none'
        ? template.isLocalDraft && !template.waba_id
        : template.inboxes.some(
            inbox => String(inbox.id) === selectedInboxId.value
          )
    );
  }

  if (selectedLanguage.value !== 'all') {
    records = records.filter(
      template => template.language === selectedLanguage.value
    );
  }

  if (selectedType.value !== 'all') {
    records = records.filter(
      template => templateTypeKey(template) === selectedType.value
    );
  }

  if (selectedCategory.value !== 'all')
    records = records.filter(
      template => template.category?.toUpperCase() === selectedCategory.value
    );
  const query = searchQuery.value.trim();
  if (!query) return records;

  const normalizedQuery = query.toLowerCase();
  const contentMatches = records.filter(template =>
    [template.name, template.searchableContent].some(value =>
      value?.toLowerCase().includes(normalizedQuery)
    )
  );
  if (contentMatches.length) return contentMatches;

  return picoSearch(records, query, FUZZY_SEARCH_KEYS);
});

const pagedTemplates = computed(() =>
  filteredTemplates.value.slice(
    (templatePage.value - 1) * templatePageSize.value,
    templatePage.value * templatePageSize.value
  )
);
watch(
  [
    searchQuery,
    missingOnly,
    selectedInboxId,
    selectedLanguage,
    selectedType,
    selectedCategory,
    selectedStatus,
    templatePageSize,
  ],
  () => {
    templatePage.value = 1;
  }
);
watch(
  () => filteredTemplates.value.length,
  count => {
    templatePage.value = Math.min(
      templatePage.value,
      Math.max(1, Math.ceil(count / templatePageSize.value))
    );
  }
);

const fetchTemplates = async () => {
  try {
    await runTemplateRequest(async signal => {
      const didFetchInboxes = await store.dispatch('inboxes/get', {
        force: true,
      });
      if (!didFetchInboxes) throw new Error();
      if (signal.aborted) return;

      if (isAdmin.value) {
        try {
          const records = [];
          let page = 1;
          let total;
          do {
            // Pagination cursors depend on the preceding response.
            // eslint-disable-next-line no-await-in-loop
            const { data } = await DraftsAPI.get(
              { page: String(page), per_page: '100' },
              { signal }
            );
            records.push(...data.payload);
            total = data.meta.total_count;
            page += 1;
          } while (!signal.aborted && records.length < total);
          if (!signal.aborted) drafts.value = records;
        } catch {
          if (!signal.aborted)
            useAlert(t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.FETCH_ERROR'));
        }
      }
      if (signal.aborted) return;

      const inboxesToFetch = [...whatsappInboxes.value];
      const responses = await Promise.allSettled(
        inboxesToFetch.map(async inbox => {
          const { data } = await InboxesAPI.getMessageTemplates(
            inbox.id,
            {},
            { signal }
          );

          if (!Array.isArray(data.payload)) {
            throw new TypeError();
          }

          return {
            inboxId: inbox.id,
            lastSyncAttemptAt: data.meta?.last_sync_attempt_at,
            records: data.payload.map(template => ({
              template,
              inbox,
              lastUpdatedAt: data.meta?.last_sync_attempt_at,
            })),
          };
        })
      );

      if (signal.aborted) return;

      const successfulResponses = responses.filter(
        response => response.status === 'fulfilled'
      );
      const activeInboxIds = new Set(inboxesToFetch.map(inbox => inbox.id));
      const nextLastSyncAttempts = {
        ...lastSyncAttemptsByInboxId.value,
      };

      templateRecordsByInboxId.forEach((_, inboxId) => {
        if (!activeInboxIds.has(inboxId)) {
          templateRecordsByInboxId.delete(inboxId);
          delete nextLastSyncAttempts[inboxId];
        }
      });
      successfulResponses.forEach(({ value }) => {
        templateRecordsByInboxId.set(value.inboxId, value.records);
        nextLastSyncAttempts[value.inboxId] = value.lastSyncAttemptAt;
      });
      lastSyncAttemptsByInboxId.value = nextLastSyncAttempts;
      templates.value = groupTemplates(
        [...templateRecordsByInboxId.values()].flat()
      );

      if (
        !inboxOptions.value.some(({ value }) => value === selectedInboxId.value)
      )
        selectedInboxId.value = 'all';
      if (
        !languageOptions.value.some(
          ({ value }) => value === selectedLanguage.value
        )
      )
        selectedLanguage.value = 'all';
      if (!typeOptions.value.some(({ value }) => value === selectedType.value))
        selectedType.value = 'all';

      if (responses.some(response => response.status === 'rejected')) {
        const errorMessage = successfulResponses.length
          ? t('WHATSAPP_TEMPLATE_MGMT.PARTIAL_FETCH_ERROR')
          : t('WHATSAPP_TEMPLATE_MGMT.FETCH_ERROR');
        useAlert(errorMessage);
      }
    });
  } catch {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.FETCH_ERROR'));
  }
};

const confirmDelete = async () => {
  const template = templateToDelete.value;
  const inbox = template && cloudInboxFor(template);
  if (!template || (!template.isLocalDraft && !inbox)) return;

  isDeleting.value = true;
  try {
    if (template.isLocalDraft) {
      await DraftsAPI.delete(template.id, template.lock_version);
    } else {
      await WhatsappTemplatesAPI.deleteTemplate(
        inbox.id,
        template.id,
        template.name
      );
    }
    useAlert(
      t(
        template.isLocalDraft
          ? 'WHATSAPP_TEMPLATE_MGMT.DRAFTS.DELETED'
          : 'WHATSAPP_TEMPLATE_MGMT.DELETE_DIALOG.DELETED'
      )
    );
    deleteDialogRef.value?.close();
    await fetchTemplates();
  } catch (error) {
    if (error?.response?.status === 409 && template.isLocalDraft) {
      deleteDialogRef.value?.close();
      await fetchTemplates();
      useAlert(t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.CONFLICT'));
      await formDrawerRef.value?.openDraft(template);
      return;
    }
    useAlert(
      error?.response?.data?.message ||
        t('WHATSAPP_TEMPLATE_MGMT.DELETE_DIALOG.ERROR')
    );
  } finally {
    isDeleting.value = false;
  }
};

const refreshTemplates = async () => {
  if (canSync.value) await syncTemplates();
  await fetchTemplates();
};
const viewDraft = record => {
  // Only the toast action changes the list context; saving keeps every filter.
  activeTab.value = 'templates';
  selectedStatus.value = 'all';
  selectedInboxId.value = 'all';
  selectedLanguage.value = 'all';
  selectedType.value = 'all';
  selectedCategory.value = 'all';
  missingOnly.value = false;
  searchQuery.value = '';
  drafts.value = [
    record,
    ...drafts.value.filter(item => item.id !== record.id),
  ];
  templatePage.value = 1;
};
const onLibraryCreated = draft => {
  activeTab.value = 'templates';
  fetchTemplates();
  formDrawerRef.value?.openDraft(draft);
};

onActivated(fetchTemplates);
onDeactivated(abortTemplateRequest);
</script>

<template>
  <SettingsLayout
    :is-loading="showTemplates && isLoading"
    :loading-message="$t('WHATSAPP_TEMPLATE_MGMT.LOADING')"
    :no-records-found="showTemplates && !allTemplates.length"
    :no-records-message="$t('WHATSAPP_TEMPLATE_MGMT.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('WHATSAPP_TEMPLATE_MGMT.TITLE')"
        :description="$t('WHATSAPP_TEMPLATE_MGMT.DESCRIPTION')"
        :link-text="$t('WHATSAPP_TEMPLATE_MGMT.LEARN_MORE')"
        feature-name="whatsapp_templates"
      >
        <template #title>
          <div class="flex items-center gap-3">
            <ChannelIcon
              :inbox="{ channel_type: 'Channel::Whatsapp' }"
              class="size-8"
            />
            <h1 class="text-heading-1 text-n-slate-12">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.TITLE') }}
            </h1>
          </div>
        </template>
        <template #tabs>
          <div class="flex flex-wrap items-center min-w-0 gap-2">
            <TabBar
              v-if="showTabs"
              :tabs="tabs"
              :initial-active-tab="tabIndex"
              @tab-changed="onTabChanged"
            />
            <SyncStatus
              v-if="showFlows"
              label-key="WHATSAPP_TEMPLATE_MGMT.UPDATED_AT"
              :date="flowsPanel?.loadedAt"
              :is-loading="flowsPanel?.isPending"
              :button-label="$t('WHATSAPP_TEMPLATE_MGMT.SYNC_COMPACT')"
              @refresh="flowsPanel?.reload()"
            />
            <SyncStatus
              v-else-if="showTemplates"
              label-key="WHATSAPP_TEMPLATE_MGMT.LAST_SYNC_ATTEMPT"
              :date="lastSyncAttemptAt"
              :is-loading="isSyncing"
              :disabled="isLoading"
              :button-label="$t('WHATSAPP_TEMPLATE_MGMT.SYNC_TEMPLATES')"
              @refresh="refreshTemplates"
            />
          </div>
        </template>
      </BaseSettingsHeader>
    </template>

    <template #preBody>
      <TemplatesToolbar
        v-if="showTemplates || showPresets"
        v-model="searchQuery"
        :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.SEARCH_PLACEHOLDER')"
        :primary-action="createAction"
      >
        <template #filters>
          <div
            v-if="hasTemplates && showTemplates"
            class="flex flex-wrap items-center gap-2"
          >
            <button
              type="button"
              class="rounded-full border px-3 py-1 text-xs"
              :class="
                missingOnly
                  ? 'border-n-amber-8 bg-n-amber-3 text-n-amber-11'
                  : 'border-n-weak text-n-slate-11'
              "
              :aria-pressed="missingOnly"
              @click="missingOnly = !missingOnly"
            >
              {{
                t('WHATSAPP_TEMPLATE_MGMT.FILTER.MISSING', {
                  count: missingCount,
                })
              }}
            </button>
            <FilterDropdown
              v-model="selectedInboxId"
              :options="inboxOptions"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.TABLE.INBOX')"
              icon="i-lucide-inbox"
            />
            <FilterDropdown
              v-model="selectedLanguage"
              :options="languageOptions"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.TABLE.LANGUAGE')"
              icon="i-lucide-languages"
            />
            <FilterDropdown
              v-model="selectedType"
              :options="typeOptions"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.TABLE.TYPE')"
              icon="i-lucide-layout-template"
            />
            <FilterDropdown
              v-model="selectedCategory"
              :options="categoryOptions"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.TABLE.CATEGORY')"
              icon="i-lucide-folder"
            />
            <FilterDropdown
              v-model="selectedStatus"
              :options="stateOptions"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.TABLE.STATUS')"
              icon="i-lucide-list-filter"
              data-testid="status-filter"
            />
          </div>
        </template>
      </TemplatesToolbar>
    </template>
    <template #body>
      <KeepAlive>
        <FlowsPanel v-if="showFlows" ref="flowsPanel" />
      </KeepAlive>
      <PresetsPanel
        v-if="showPresets"
        :search="searchQuery"
        :inboxes="cloudInboxes"
        :templates="templates"
        @use="applyPreset"
        @created="onLibraryCreated"
      />
      <div
        v-else-if="showTemplates && !filteredTemplates.length"
        class="flex items-center justify-center p-8"
      >
        <span class="text-base text-n-slate-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.NO_RESULTS') }}
        </span>
      </div>

      <TemplatesTable
        v-else-if="showTemplates"
        v-model:page="templatePage"
        v-model:page-size="templatePageSize"
        cards-on-mobile
        :columns="columns"
        :items="pagedTemplates"
        :total="filteredTemplates.length"
        :page-size="templatePageSize"
        :per-page-options="[10, 25, 50]"
        @open="openPreview"
      >
        <template #NAME="{ item }">
          <span class="flex w-full min-w-0 items-center gap-2">
            <span
              class="block min-w-0 flex-1 truncate text-heading-3 text-n-slate-12"
              :title="
                item.name ||
                item.title ||
                $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.UNTITLED')
              "
            >
              {{
                item.name ||
                item.title ||
                $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.UNTITLED')
              }}
            </span>
            <TemplatePendingIndicator :template="item" />
          </span>
        </template>
        <template #CATEGORY="{ item }">
          <span
            v-if="item.category"
            class="px-2 py-1 text-xs rounded-md"
            :class="
              item.category?.toUpperCase() === 'MARKETING'
                ? 'bg-n-amber-3 text-n-amber-11'
                : 'bg-n-teal-3 text-n-teal-11'
            "
          >
            {{
              $t(
                'WHATSAPP_TEMPLATE_MGMT.FILTERS.CATEGORIES.' +
                  item.category?.toUpperCase()
              )
            }}
          </span>
          <span v-else>{{ formatTemplateLabel(null) }}</span>
        </template>
        <template #LANGUAGE="{ item }">
          {{
            item.language
              ? formatTemplateLanguage(item.language)
              : formatTemplateLabel(null)
          }}
        </template>
        <template #TYPE="{ item }">
          {{ typeLabels[templateTypeKey(item)] || formatTemplateLabel(null) }}
        </template>
        <template #INBOX="{ item }">
          {{
            item.inboxNames ||
            item.waba_id ||
            $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.NO_CHANNEL')
          }}
        </template>
        <template #UPDATED="{ item }">
          {{
            formatTemplateDate(
              item.isLocalDraft ? item.updated_at : item.last_updated_time
            )
          }}
        </template>
        <template #STATUS="{ item }">
          <span
            v-if="item.isLocalDraft && item.status"
            class="px-2 py-1 text-xs rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            {{
              $t(
                'WHATSAPP_TEMPLATE_MGMT.DRAFTS.STATUS.' +
                  item.status.toUpperCase()
              )
            }}
          </span>
          <span v-else class="text-n-slate-11">{{
            formatTemplateLabel(null)
          }}</span>
        </template>
        <template #META_STATUS="{ item }">
          <span
            class="px-2 py-1 text-xs rounded-full"
            :class="templateStatusClasses(remoteStatus(item))"
          >
            {{ remoteStatusLabel(item) }}
          </span>
        </template>
        <template #ACTIONS="{ item }">
          <TemplateRowActions
            v-if="isAdmin"
            :labels="rowLabels(item)"
            :can-manage="canManage(item)"
            :can-edit="canEdit(item)"
            @edit="openEdit(item)"
            @duplicate="duplicateTemplate(item)"
            @delete="askDelete(item)"
          />
        </template>
      </TemplatesTable>
    </template>

    <TemplatePreviewDrawer ref="previewPanelRef" :template="selectedTemplate" />
    <TemplateFormDrawer
      v-if="isAdmin"
      ref="formDrawerRef"
      :inboxes="whatsappInboxes"
      :templates="templates"
      @saved="fetchTemplates"
      @view-draft="viewDraft"
    />
    <Dialog
      v-if="isAdmin"
      ref="deleteDialogRef"
      type="alert"
      :title="
        templateToDelete?.isLocalDraft
          ? $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DELETE')
          : $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DELETE_REMOTE')
      "
      :confirm-button-label="
        templateToDelete?.isLocalDraft
          ? $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DELETE')
          : $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DELETE_REMOTE')
      "
      :is-loading="isDeleting"
      @confirm="confirmDelete"
    >
      <div v-if="templateToDelete" class="grid gap-3 text-sm text-n-slate-11">
        <p v-if="!templateToDelete.isLocalDraft">
          {{
            $t('WHATSAPP_TEMPLATE_MGMT.DELETE_DIALOG.DESCRIPTION', {
              name: templateToDelete.name,
              language: formatTemplateLanguage(templateToDelete.language),
            })
          }}
        </p>
        <p class="text-n-amber-11">
          {{
            templateToDelete.isLocalDraft
              ? $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DELETE_HELP')
              : $t('WHATSAPP_TEMPLATE_MGMT.DELETE_DIALOG.LOCK_NOTE')
          }}
        </p>
      </div>
    </Dialog>
  </SettingsLayout>
</template>
