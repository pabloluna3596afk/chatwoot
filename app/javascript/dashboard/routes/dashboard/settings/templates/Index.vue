<script setup>
import { computed, onActivated, onDeactivated, ref } from 'vue';
import { picoSearch } from '@chatwoot/pico-search';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

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
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import TemplateCard from './TemplateCard.vue';
import TemplatePreviewDrawer from './TemplatePreviewDrawer.vue';
import TemplateFormDrawer from './TemplateFormDrawer.vue';
import PresetsPanel from './PresetsPanel.vue';
import FlowsPanel from './flows/FlowsPanel.vue';
import { isEditable } from './templateForm';
import { presetToForm } from './presets';
import {
  formatTemplateDate,
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
const selectedTemplate = ref(null);
const openFilterMenu = ref(null);
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

const filterMenus = computed(() =>
  [
    {
      key: 'inbox',
      icon: 'i-lucide-inbox',
      options: inboxOptions.value,
      active: selectedInboxId.value,
    },
    {
      key: 'language',
      icon: 'i-lucide-languages',
      options: languageOptions.value,
      active: selectedLanguage.value,
    },
    {
      key: 'type',
      icon: 'i-lucide-layout-template',
      options: typeOptions.value,
      active: selectedType.value,
    },
  ].map(menu => {
    const items = menu.options.map(option => ({
      ...option,
      action: menu.key,
      isSelected: option.value === menu.active,
    }));

    return {
      ...menu,
      items,
      selected: items.find(item => item.isSelected) || items[0],
    };
  })
);

const closeFilterMenu = () => {
  openFilterMenu.value = null;
};

const toggleFilterMenu = key => {
  openFilterMenu.value = openFilterMenu.value === key ? null : key;
};

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
const openEdit = template => formDrawerRef.value?.open(template);
const askDelete = template => {
  templateToDelete.value = template;
  deleteDialogRef.value?.open();
};

const handleFilterAction = ({ action, value }) => {
  closeFilterMenu();
  if (action === 'inbox') selectedInboxId.value = value;
  else if (action === 'language') selectedLanguage.value = value;
  else selectedType.value = value;
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

const showSearch = computed(() =>
  Boolean(filteredTemplates.value.length || searchQuery.value)
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
        v-model:search-query="searchQuery"
        :title="$t('WHATSAPP_TEMPLATE_MGMT.TITLE')"
        :description="$t('WHATSAPP_TEMPLATE_MGMT.DESCRIPTION')"
        :link-text="$t('WHATSAPP_TEMPLATE_MGMT.LEARN_MORE')"
        feature-name="whatsapp_templates"
        :search-placeholder="
          showSearch ? $t('WHATSAPP_TEMPLATE_MGMT.SEARCH_PLACEHOLDER') : ''
        "
      >
        <template v-if="lastSyncAttemptAt" #meta>
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
            <div
              v-if="hasTemplates && showTemplates"
              v-on-click-outside="closeFilterMenu"
              class="flex flex-wrap items-center min-w-0 gap-2"
            >
              <div v-for="menu in filterMenus" :key="menu.key" class="relative">
                <Button
                  :icon="menu.icon"
                  color="slate"
                  size="sm"
                  class="max-w-44"
                  :class="{ 'bg-n-slate-9/10': openFilterMenu === menu.key }"
                  @click="toggleFilterMenu(menu.key)"
                >
                  <span class="min-w-0 truncate">{{
                    menu.selected.label
                  }}</span>
                  <Icon icon="i-lucide-chevron-down" class="shrink-0 size-4" />
                </Button>
                <DropdownMenu
                  v-if="openFilterMenu === menu.key"
                  :menu-items="menu.items"
                  class="mt-2 min-w-52 top-full ltr:left-0 rtl:right-0"
                  @action="handleFilterAction"
                />
              </div>
            </div>
          </div>
        </template>
        <template v-if="filteredTemplates.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{
              $t('WHATSAPP_TEMPLATE_MGMT.COUNT', {
                n: filteredTemplates.length,
              })
            }}
          </span>
        </template>
        <template v-if="!showFlows" #actions>
          <Button
            v-if="isAdmin && cloudInboxes.length"
            :label="$t('WHATSAPP_TEMPLATE_MGMT.NEW_TEMPLATE')"
            icon="i-lucide-plus"
            size="sm"
            data-testid="template-new"
            @click="openCreate"
          />
          <Button
            :label="$t('WHATSAPP_TEMPLATE_MGMT.SYNC_TEMPLATES')"
            icon="i-lucide-refresh-cw"
            color="slate"
            size="sm"
            :is-loading="isSyncing"
            :disabled="!canSync || isSyncing"
            @click="syncTemplates"
          />
        </template>
      </BaseSettingsHeader>
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

      <div
        v-else-if="showTemplates"
        class="border-t divide-y divide-n-weak border-n-weak"
      >
        <TemplateCard
          v-for="template in filteredTemplates"
          :key="template.key"
          :template="template"
          :can-manage="canManage(template)"
          :can-edit="canEdit(template)"
          @preview="openPreview(template)"
          @edit="openEdit(template)"
          @delete="askDelete(template)"
        />
      </div>
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
