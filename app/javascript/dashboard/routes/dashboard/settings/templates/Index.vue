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
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import TemplatesTable from './TemplatesTable.vue';
import TemplatesToolbar from './TemplatesToolbar.vue';
import { templateTableColumns } from './templateTableColumns';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import TemplateRowActions from './TemplateRowActions.vue';
import TemplatePreviewDrawer from './TemplatePreviewDrawer.vue';
import TemplateFormDrawer from './TemplateFormDrawer.vue';
import PresetsPanel from './PresetsPanel.vue';
import FlowsPanel from './flows/FlowsPanel.vue';
import { isEditable, formFromTemplate } from './templateForm';
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
const { t } = useI18n();

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
const canManage = template => isAdmin.value && Boolean(cloudInboxFor(template));
const canEdit = template => canManage(template) && isEditable(template);

const templates = ref([]);
const searchQuery = ref('');
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
    count: templates.value.length,
  },
  ...['UTILITY', 'MARKETING', 'AUTHENTICATION'].map(value => ({
    value,
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.CATEGORIES.' + value),
    count: templates.value.filter(
      item => item.category?.toUpperCase() === value
    ).length,
  })),
]);
const columns = computed(() => templateTableColumns(t, ['LANGUAGE', 'TYPE']));
const actionLabels = computed(() => ({
  edit: t('WHATSAPP_TEMPLATE_MGMT.EDIT'),
  duplicate: t('WHATSAPP_TEMPLATE_MGMT.DUPLICATE'),
  delete: t('WHATSAPP_TEMPLATE_MGMT.DELETE'),
}));
const selectedTemplate = ref(null);
const previewPanelRef = ref(null);
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

const hasTemplates = computed(() => templates.value.length > 0);

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
  ...[...new Set(templates.value.map(template => template.language))]
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
  ...[...new Set(templates.value.map(templateTypeKey))]
    .map(type => ({
      value: type,
      label: typeLabels.value[type],
    }))
    .sort((first, second) => first.label.localeCompare(second.label)),
]);

const openPreview = template => {
  selectedTemplate.value = template;
  previewPanelRef.value?.open();
};

const openCreate = () => formDrawerRef.value?.open();

// Templates, ready-made presets and flows are the tabs of the page. Only administrators see the tabs: the presets need
// a WhatsApp Cloud channel (they create templates); the flows are ChatHub's own and do not.
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
  return isAdmin.value && cloudInboxes.value.length
    ? { label: t('WHATSAPP_TEMPLATE_MGMT.NEW_TEMPLATE'), run: openCreate }
    : null;
});
const tabs = computed(() => [
  { key: 'templates', label: t('WHATSAPP_TEMPLATE_MGMT.TABS.TEMPLATES') },
  ...(cloudInboxes.value.length
    ? [{ key: 'presets', label: t('WHATSAPP_TEMPLATE_MGMT.TABS.PRESETS') }]
    : []),
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
const duplicateTemplate = template => {
  const prefill = formFromTemplate(template, cloudInboxFor(template)?.id);
  prefill.name = template.name.slice(0, 506) + '_copia';
  formDrawerRef.value?.open(null, prefill);
};
const openEdit = template => formDrawerRef.value?.open(template);
const askDelete = template => {
  templateToDelete.value = template;
  deleteDialogRef.value?.open();
};

const filteredTemplates = computed(() => {
  let records = templates.value;

  if (selectedInboxId.value !== 'all') {
    records = records.filter(template =>
      template.inboxes.some(inbox => String(inbox.id) === selectedInboxId.value)
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
    selectedInboxId,
    selectedLanguage,
    selectedType,
    selectedCategory,
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
      const didFetchInboxes = await store.dispatch('inboxes/get');
      if (!didFetchInboxes) throw new Error();
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
  if (!inbox) return;

  isDeleting.value = true;
  try {
    await WhatsappTemplatesAPI.deleteTemplate(
      inbox.id,
      template.id,
      template.name
    );
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.DELETE_DIALOG.DELETED'));
    deleteDialogRef.value?.close();
    await fetchTemplates();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('WHATSAPP_TEMPLATE_MGMT.DELETE_DIALOG.ERROR')
    );
  } finally {
    isDeleting.value = false;
  }
};

const onLibraryCreated = () => {
  activeTab.value = 'templates';
  fetchTemplates();
};

onActivated(fetchTemplates);
onDeactivated(abortTemplateRequest);
</script>

<template>
  <SettingsLayout
    :is-loading="showTemplates && isLoading"
    :loading-message="$t('WHATSAPP_TEMPLATE_MGMT.LOADING')"
    :no-records-found="showTemplates && !templates.length"
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
        <template v-if="lastSyncAttemptAt && !showFlows" #meta>
          <span class="text-xs text-n-slate-10">
            {{
              $t('WHATSAPP_TEMPLATE_MGMT.LAST_SYNC_ATTEMPT', {
                date: formatTemplateDate(lastSyncAttemptAt),
              })
            }}
          </span>
        </template>
        <template #tabs>
          <div class="flex flex-wrap items-center min-w-0 gap-2">
            <TabBar
              v-if="showTabs"
              :tabs="tabs"
              :initial-active-tab="tabIndex"
              @tab-changed="onTabChanged"
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
          </div>
        </template>
        <template #actions>
          <Button
            :label="$t('WHATSAPP_TEMPLATE_MGMT.SYNC_COMPACT')"
            icon="i-lucide-refresh-cw"
            color="slate"
            size="sm"
            :is-loading="isSyncing"
            :disabled="!canSync || isSyncing"
            @click="syncTemplates"
          />
        </template>
      </TemplatesToolbar>
    </template>
    <template #body>
      <KeepAlive>
        <FlowsPanel v-if="showFlows" />
      </KeepAlive>
      <PresetsPanel
        v-if="showPresets"
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
        :columns="columns"
        :items="pagedTemplates"
        :total="filteredTemplates.length"
        :page-size="templatePageSize"
        :per-page-options="[10, 25, 50]"
        @open="openPreview"
      >
        <template #NAME="{ item }">
          <span class="text-heading-3 text-n-slate-12">{{ item.name }}</span>
        </template>
        <template #CATEGORY="{ item }">
          <span
            class="px-2 py-1 text-xs rounded-md"
            :class="
              item.category?.toUpperCase() === 'MARKETING'
                ? 'bg-n-amber-3 text-n-amber-11'
                : 'bg-n-teal-3 text-n-teal-11'
            "
            >{{
              $t(
                'WHATSAPP_TEMPLATE_MGMT.FILTERS.CATEGORIES.' +
                  item.category?.toUpperCase()
              )
            }}</span
          >
        </template>
        <template #LANGUAGE="{ item }">
          {{ formatTemplateLanguage(item.language) }}
        </template>
        <template #TYPE="{ item }">
          {{ typeLabels[templateTypeKey(item)] }}
        </template>
        <template #INBOX="{ item }">{{ item.inboxNames }}</template>
        <template #UPDATED="{ item }">
          {{
            item.lastUpdatedAt
              ? formatTemplateDate(item.lastUpdatedAt)
              : formatTemplateLabel(null)
          }}
        </template>
        <template #STATUS="{ item }">
          <span
            class="px-2.5 py-1 text-xs rounded-full whitespace-nowrap"
            :class="templateStatusClasses(item.status)"
            >{{
              $te('WHATSAPP_TEMPLATE_MGMT.STATUS.' + item.status?.toUpperCase())
                ? $t(
                    'WHATSAPP_TEMPLATE_MGMT.STATUS.' +
                      item.status?.toUpperCase()
                  )
                : formatTemplateLabel(item.status)
            }}</span
          >
        </template>
        <template #ACTIONS="{ item }">
          <TemplateRowActions
            :labels="actionLabels"
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
      :inboxes="cloudInboxes"
      :templates="templates"
      @saved="fetchTemplates"
    />
    <Dialog
      v-if="isAdmin"
      ref="deleteDialogRef"
      type="alert"
      :title="$t('WHATSAPP_TEMPLATE_MGMT.DELETE_DIALOG.TITLE')"
      :confirm-button-label="$t('WHATSAPP_TEMPLATE_MGMT.DELETE_DIALOG.CONFIRM')"
      :is-loading="isDeleting"
      @confirm="confirmDelete"
    >
      <div v-if="templateToDelete" class="grid gap-3 text-sm text-n-slate-11">
        <p>
          {{
            $t('WHATSAPP_TEMPLATE_MGMT.DELETE_DIALOG.DESCRIPTION', {
              name: templateToDelete.name,
              language: formatTemplateLanguage(templateToDelete.language),
            })
          }}
        </p>
        <p class="text-n-amber-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.DELETE_DIALOG.LOCK_NOTE') }}
        </p>
      </div>
    </Dialog>
  </SettingsLayout>
</template>
