<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import AssistantAPI from 'dashboard/api/captain/assistant';
import InboxesAPI from 'dashboard/api/inboxes';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import FlowPreviewDrawer from 'dashboard/routes/dashboard/settings/templates/flows/FlowPreviewDrawer.vue';
import CaptainTemplatePreview from './CaptainTemplatePreview.vue';
import CaptainResourceRow from './CaptainResourceRow.vue';
import { useTemplateVariables } from './useTemplateVariables';

const props = defineProps({ assistant: { type: Object, default: () => ({}) } });
const emit = defineEmits(['submit']);
const { t } = useI18n();
const route = useRoute();
const store = useStore();
const { accountScopedRoute } = useAccount();
const { variableOptions, previewValues } = useTemplateVariables({
  appointment: false,
});
const bindingOptions = computed(() =>
  variableOptions.value.map(option => ({
    value: option.key,
    label: option.label,
    description: option.description,
  }))
);
const linkedInboxes = useMapGetter('captainInboxes/getRecords');
const allInboxes = useMapGetter('inboxes/getInboxes');

const inboxesLoading = ref(true);
const loadingFailed = ref(false);
const selectedInboxId = ref(null);
const flows = ref([]);
const messagingRevision = ref(0);
const resourceGroups = reactive({});
const reviewing = reactive({});
const capValue = ref(50);
const capUsed = ref(0);
const expanded = reactive({});
const templatePreview = ref(null);
const assignDialog = ref(null);
const previewDrawer = ref(null);
const selectedRow = ref(null);
const bindingsDraft = reactive({});
const paidTemplates = ref(false);
const permissionEntries = reactive({});

// The list endpoint omits the per-inbox state (`envios`): read it from the single-assistant endpoint.
const serverEnvios = ref(null);
const envios = computed(
  () => serverEnvios.value || props.assistant?.envios || {}
);
const loadEnvios = async () => {
  try {
    const { data } = await AssistantAPI.show(route.params.assistantId);
    serverEnvios.value = data?.envios || null;
  } catch {
    serverEnvios.value = null;
  }
};

const connectedInboxes = computed(() => {
  const ids = (linkedInboxes.value || []).map(item => item.id);
  return ids
    .map(id => (allInboxes.value || []).find(item => item.id === id))
    .filter(Boolean);
});
const orderedInboxes = computed(() => [...connectedInboxes.value]);
const whatsappInboxes = computed(() =>
  orderedInboxes.value.filter(
    inbox => inbox.channel_type === 'Channel::Whatsapp'
  )
);
const selectedInbox = computed(() =>
  orderedInboxes.value.find(item => item.id === selectedInboxId.value)
);
const serverInbox = computed(() =>
  (envios.value?.inboxes || []).find(
    item => item.inbox_id === selectedInboxId.value
  )
);
const savedMessaging = computed(() => props.assistant?.config?.messaging || {});
const currentEntry = computed(
  () =>
    permissionEntries[selectedInboxId.value] || {
      inbox_id: selectedInboxId.value,
      enabled: false,
      mode: 'auto',
      excluded: { templates: [], flows: [] },
      included_marketing: [],
      reviewed: { templates: {}, flows: {} },
      notes: {},
    }
);
const resources = computed(() => serverInbox.value?.resources || []);
const localState = (item, kind, key) => {
  if (!['available', 'excluded'].includes(item.state)) return item.state;
  if (currentEntry.value.mode === 'list') {
    const listed =
      kind === 'templates'
        ? (currentEntry.value.templates || []).some(
            template =>
              `${template.name}|${template.language}` ===
              `${item.resource.name}|${item.resource.language}`
          )
        : (currentEntry.value.flows || []).some(
            flow => flow.flow_id === item.resource.id
          );
    return listed ? 'available' : 'excluded';
  }
  const exclusions = currentEntry.value.excluded?.[kind] || [];
  return exclusions.includes(key) ? 'excluded' : 'available';
};
const templateRows = computed(() => {
  const templates = selectedInbox.value?.message_templates || [];
  return resources.value
    .filter(item => item.resource?.language)
    .map(item => ({
      ...item,
      template: templates.find(
        candidate =>
          candidate.name === item.resource.name &&
          candidate.language === item.resource.language
      ),
      kind: 'template',
      key: `${serverInbox.value?.waba_id}:${item.resource.name}|${item.resource.language}`,
      state: localState(
        item,
        'templates',
        `${serverInbox.value?.waba_id}:${item.resource.name}|${item.resource.language}`
      ),
    }));
});
const flowRows = computed(() =>
  resources.value
    .filter(item => item.resource && Number.isInteger(item.resource.id))
    .map(item => ({
      ...item,
      flow: flows.value.find(flow => flow.id === item.resource.id),
      kind: 'flow',
      key: `${serverInbox.value?.waba_id}:${item.resource.id}`,
      state: localState(
        item,
        'flows',
        `${serverInbox.value?.waba_id}:${item.resource.id}`
      ),
    }))
);
const pendingCount = inbox => {
  const data = (envios.value?.inboxes || []).find(
    item => item.inbox_id === inbox.id
  );
  const resourcePending = (data?.resources || []).filter(item =>
    [
      'needs_data',
      'new',
      'changed',
      'needs_review',
      'not_published_here',
    ].includes(item.state)
  ).length;
  return resourcePending;
};
const inboxTabs = computed(() =>
  orderedInboxes.value.map(inbox => ({
    label: inbox.name,
    count: pendingCount(inbox),
    inboxId: inbox.id,
  }))
);
const activeTabIndex = computed(() =>
  Math.max(
    0,
    orderedInboxes.value.findIndex(item => item.id === selectedInboxId.value)
  )
);
function channelLabel(inbox) {
  const channel = inbox.channel_type?.split('::').pop()?.toLowerCase();
  const names = {
    whatsapp:
      inbox.provider === 'whatsapp_cloud' ? 'WhatsApp Cloud' : 'WhatsApp',
    webwidget: 'Chat web',
    email: 'Correo',
  };
  return names[channel] || inbox.channel_type?.split('::').pop() || '';
}
const inboxOptions = computed(() =>
  orderedInboxes.value.map(inbox => ({
    value: inbox.id,
    label: `${inbox.name} · ${channelLabel(inbox)}${
      pendingCount(inbox)
        ? ` · ${t('CAPTAIN.ASSISTANTS.ENVIOS.PENDING_COUNT', pendingCount(inbox), { count: pendingCount(inbox) })}`
        : ''
    }`,
  }))
);
const stateLabels = {
  available: 'AVAILABLE',
  excluded: 'EXCLUDED',
  marketing_off: 'MARKETING_OFF',
  needs_data: 'NEEDS_DATA',
  pending: 'PENDING',
  rejected: 'REJECTED',
  unsupported: 'UNSUPPORTED',
  authentication: 'AUTHENTICATION',
  not_published_here: 'NOT_PUBLISHED_HERE',
  new: 'NEW',
  changed: 'CHANGED',
  needs_review: 'NEEDS_REVIEW',
  disabled: 'DISABLED',
  unavailable: 'UNAVAILABLE',
};
const stateLabel = state =>
  ['available', 'excluded', 'unavailable'].includes(state)
    ? ''
    : t(
        `CAPTAIN.ASSISTANTS.ENVIOS.STATES.${stateLabels[state] || 'UNAVAILABLE'}`
      );
const GROUPS = ['READY', 'PERMISSION', 'UNUSABLE'];
const groupFor = state => {
  if (['available', 'excluded'].includes(state)) return 'READY';
  if (
    ['marketing_off', 'new', 'changed', 'needs_review', 'needs_data'].includes(
      state
    )
  )
    return 'PERMISSION';
  return 'UNUSABLE';
};
// Capture membership on load, independently of the editable switches and review responses.
watch(
  envios,
  value => {
    (value.inboxes || []).forEach(inbox => {
      (inbox.resources || []).forEach(item => {
        const resource = item.resource;
        if (!resource) return;
        const key = `${inbox.inbox_id}:${resource.language ? `${resource.name}|${resource.language}` : resource.id}`;
        resourceGroups[key] ??= groupFor(item.state);
      });
    });
  },
  { immediate: true }
);
const activeResourceIndex = ref(0);
const resourceSections = computed(() =>
  [
    {
      kind: 'flow',
      title: 'FLOWS',
      rows: flowRows.value,
      createRoute: { name: 'settings_flow_new' },
    },
    {
      kind: 'template',
      title: 'TEMPLATES',
      rows: templateRows.value,
      createRoute: accountScopedRoute('settings_templates'),
    },
  ].map(section => ({
    ...section,
    groups: GROUPS.map(id => ({
      id,
      key: `${selectedInboxId.value}:${section.kind}:${id}`,
      rows: section.rows.filter(row => {
        if (
          row.resource.category?.toUpperCase() === 'AUTHENTICATION' ||
          row.state === 'authentication'
        )
          return false;
        const identity =
          row.kind === 'template'
            ? `${row.resource.name}|${row.resource.language}`
            : row.resource.id;
        return resourceGroups[`${selectedInboxId.value}:${identity}`] === id;
      }),
    })),
  }))
);
const resourceTabs = computed(() =>
  resourceSections.value.map((section, index) => ({
    label: `${t(`CAPTAIN.ASSISTANTS.ENVIOS.${section.title}.TITLE`)} (${section.groups.reduce((count, group) => count + group.rows.length, 0)})`,
    index,
  }))
);
const visibleResourceSections = computed(() => [
  resourceSections.value[activeResourceIndex.value],
]);
const rowUsages = row => {
  if (row.kind !== 'template') return [];
  const matches = template =>
    template?.name === row.resource.name &&
    template?.language === row.resource.language;
  const usages = [];
  if (matches(props.assistant?.config?.appointments?.template_reminder))
    usages.push(t('CAPTAIN.ASSISTANTS.ENVIOS.USED_BY_APPOINTMENTS'));
  if (matches(props.assistant?.config?.followup?.reengagement_template))
    usages.push(t('CAPTAIN.ASSISTANTS.ENVIOS.USED_BY_FOLLOWUP'));
  return usages;
};
const setResourceExcluded = row => {
  if (currentEntry.value.mode === 'list') {
    const field = row.kind === 'template' ? 'templates' : 'flows';
    const list = currentEntry.value[field] || [];
    const saved = (savedMessaging.value.inboxes || [])
      .find(entry => entry.inbox_id === selectedInboxId.value)
      ?.[
        field
      ]?.find(entry => (row.kind === 'template' ? entry.name === row.resource.name && entry.language === row.resource.language : entry.flow_id === row.resource.id));
    currentEntry.value[field] =
      row.state === 'available'
        ? list.filter(entry =>
            row.kind === 'template'
              ? entry.name !== row.resource.name ||
                entry.language !== row.resource.language
              : entry.flow_id !== row.resource.id
          )
        : [
            ...list,
            saved ||
              (row.kind === 'template'
                ? {
                    name: row.resource.name,
                    language: row.resource.language,
                    processed_params: {},
                  }
                : { flow_id: row.resource.id }),
          ];
    return;
  }
  const listKey = row.kind === 'template' ? 'templates' : 'flows';
  const exclusions = currentEntry.value.excluded[listKey] || [];
  const isExcluded = row.state === 'excluded';
  currentEntry.value.excluded[listKey] = isExcluded
    ? exclusions.filter(item => item !== row.key)
    : [...new Set([...exclusions, row.key])];
};
const reviewResource = async row => {
  try {
    reviewing[row.key] = true;
    const { data } = await AssistantAPI.allowResource({
      assistantId: props.assistant.id,
      inboxId: selectedInboxId.value,
      kind: row.kind,
      key: row.key,
    });
    const messaging = data.config.messaging;
    const entry = messaging.inboxes.find(
      item => item.inbox_id === selectedInboxId.value
    );
    currentEntry.value.reviewed = entry.reviewed;
    currentEntry.value.included_marketing = entry.included_marketing;
    messagingRevision.value = messaging.revision;
    serverEnvios.value = data.envios;
  } catch (error) {
    if (error.response?.status === 409) {
      useAlert(t('CAPTAIN.ASSISTANTS.ENVIOS.CONFLICT'));
      return;
    }
    useAlert(
      error.response?.data?.error || t('CAPTAIN.ASSISTANTS.EDIT.ERROR_MESSAGE')
    );
  } finally {
    reviewing[row.key] = false;
  }
};
const toggleResource = row => {
  if (['available', 'excluded'].includes(row.state)) setResourceExcluded(row);
  else reviewResource(row);
};
const openAssignment = row => {
  selectedRow.value = row;
  Object.keys(bindingsDraft).forEach(key => delete bindingsDraft[key]);
  const currentBindings = row.template?.variable_bindings || {};
  (row.missing || []).forEach(variable => {
    bindingsDraft[variable] = currentBindings[variable] || '';
  });
  assignDialog.value?.open();
};
const saveAssignment = async () => {
  const bindings = Object.fromEntries(
    Object.entries(bindingsDraft).filter(([, value]) => value.trim())
  );
  await InboxesAPI.updateWhatsappTemplateVariableBindings(
    selectedInboxId.value,
    {
      name: selectedRow.value.resource.name,
      variable_bindings: bindings,
    }
  );
  await store.dispatch('inboxes/get', { force: true });
  await loadEnvios();
  assignDialog.value?.close();
};
const openPreview = row => {
  if (row.kind === 'flow' && row.flow) {
    previewDrawer.value?.open({
      ...row.flow,
      notice:
        row.state === 'not_published_here'
          ? t('CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_FLOW_UNPUBLISHED')
          : '',
    });
    return;
  }
  selectedRow.value = row;
  templatePreview.value?.open();
};
const capValid = computed(
  () =>
    Number.isInteger(Number(capValue.value)) &&
    Number(capValue.value) >= 0 &&
    Number(capValue.value) <= 10000
);
const save = async () => {
  if (!capValid.value) return;
  const entries = Object.values(permissionEntries)
    .filter(entry =>
      whatsappInboxes.value.some(inbox => inbox.id === entry.inbox_id)
    )
    .map(entry => ({
      ...entry,
      inbox_id: Number(entry.inbox_id),
    }));
  const payload = {
    config: {
      ...props.assistant.config,
      allow_paid_templates: paidTemplates.value,
      messaging: {
        ...savedMessaging.value,
        version: 2,
        revision: messagingRevision.value,
        inboxes: entries,
      },
    },
  };
  emit('submit', {
    assistantPayload: payload,
    dailyCap: Number(capValue.value),
  });
};
const hydrate = () => {
  messagingRevision.value = savedMessaging.value.revision || 0;
  paidTemplates.value = props.assistant?.config?.allow_paid_templates === true;
  capValue.value = envios.value?.template_cap?.cap ?? 50;
  capUsed.value = envios.value?.template_cap?.used ?? 0;
  Object.keys(permissionEntries).forEach(key => delete permissionEntries[key]);
  (savedMessaging.value.inboxes || []).forEach(entry => {
    permissionEntries[entry.inbox_id] = JSON.parse(JSON.stringify(entry));
  });
};
watch(() => props.assistant, hydrate, { immediate: true });
watch(() => props.assistant?.updated_at, loadEnvios);
watch(
  () => envios.value.template_cap,
  cap => {
    capValue.value = cap?.cap ?? 50;
    capUsed.value = cap?.used ?? 0;
  }
);
watch(
  orderedInboxes,
  list => {
    list.forEach(inbox => {
      if (!permissionEntries[inbox.id]) {
        const saved = (savedMessaging.value.inboxes || []).find(
          item => item.inbox_id === inbox.id
        );
        permissionEntries[inbox.id] = saved
          ? JSON.parse(JSON.stringify(saved))
          : {
              inbox_id: inbox.id,
              enabled: false,
              mode: 'auto',
              excluded: { templates: [], flows: [] },
              included_marketing: [],
              reviewed: { templates: {}, flows: {} },
              notes: {},
            };
      }
    });
    if (!list.some(item => item.id === selectedInboxId.value))
      selectedInboxId.value = list[0]?.id ?? null;
  },
  { immediate: true }
);
const selectTab = tab => {
  selectedInboxId.value = tab.inboxId ?? null;
};
const flowEditRoute = row => ({
  name: 'settings_flow_edit',
  params: { flowId: row.resource.id },
});

onMounted(async () => {
  try {
    await loadEnvios();
    await store.dispatch('captainInboxes/get', {
      assistantId: route.params.assistantId,
    });
    await store.dispatch('inboxes/get');
    const flowResponse = await WhatsappFlowsAPI.list({ per_page: 100 });
    flows.value = flowResponse.data.payload || [];
  } catch {
    loadingFailed.value = true;
  } finally {
    inboxesLoading.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col gap-5" data-testid="messaging-form">
    <SettingsToggleSection
      v-if="whatsappInboxes.length"
      v-model="paidTemplates"
      :header="t('CAPTAIN.ASSISTANTS.ENVIOS.PAID.TITLE')"
      :description="t('CAPTAIN.ASSISTANTS.ENVIOS.PAID.SCOPE')"
    >
      <p
        class="mb-0 mt-3 w-full border-t border-n-weak px-4 pt-3 text-body-main text-n-slate-11"
        data-testid="paid-explanation"
      >
        {{
          t(
            paidTemplates
              ? 'CAPTAIN.ASSISTANTS.ENVIOS.PAID.ON'
              : 'CAPTAIN.ASSISTANTS.ENVIOS.PAID.OFF'
          )
        }}
      </p>
    </SettingsToggleSection>

    <div
      v-if="whatsappInboxes.length"
      class="flex flex-wrap items-center gap-3"
    >
      <label
        class="text-sm font-medium text-n-slate-12"
        for="captain-daily-cap"
      >
        {{ t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.LABEL') }}
      </label>
      <Input
        id="captain-daily-cap"
        v-model.number="capValue"
        class="w-20"
        type="number"
        min="0"
        max="10000"
      />
      <p v-if="!capValid" class="mb-0 text-xs text-n-ruby-9" role="alert">
        {{ t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.INVALID') }}
      </p>
      <p class="mb-0 text-xs text-n-slate-11">
        {{
          t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.TODAY', {
            used: capUsed,
            cap: capValue,
          })
        }}
      </p>
      <span
        v-tooltip="t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.HELP')"
        tabindex="0"
        :aria-label="t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.HELP')"
        class="i-lucide-info size-4 text-n-slate-11"
      />
      <p v-if="capUsed >= capValue" class="mb-0 text-xs text-n-amber-11">
        {{
          t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.REACHED', {
            used: capUsed,
            cap: capValue,
          })
        }}
      </p>
    </div>

    <Banner
      v-for="notice in props.assistant?.activation_notices || []"
      :key="notice.inbox_id"
      color="blue"
    >
      {{ notice.message }}
    </Banner>

    <Banner
      v-if="!inboxesLoading && !loadingFailed && !orderedInboxes.length"
      color="blue"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <span>{{ t('CAPTAIN.ASSISTANTS.ENVIOS.NO_INBOXES') }}</span>
        <RouterLink
          :to="accountScopedRoute('settings_inboxes')"
          class="text-n-brand underline"
        >
          {{ t('CAPTAIN.ASSISTANTS.ENVIOS.CONNECT_INBOX') }}
        </RouterLink>
      </div>
    </Banner>
    <p
      v-else-if="inboxesLoading"
      class="mb-0 text-sm text-n-slate-11"
      role="status"
    >
      {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.LOADING') }}
    </p>
    <p
      v-else-if="loadingFailed"
      class="mb-0 text-sm text-n-ruby-9"
      role="alert"
    >
      {{ t('CAPTAIN.ASSISTANTS.ENVIOS.LOAD_ERROR') }}
    </p>

    <template v-if="!inboxesLoading && selectedInbox">
      <TabBar
        v-if="orderedInboxes.length >= 2 && orderedInboxes.length <= 5"
        :tabs="inboxTabs"
        :initial-active-tab="activeTabIndex"
        :tab-list-label="t('CAPTAIN.ASSISTANTS.ENVIOS.INBOX_LABEL')"
        @tab-changed="selectTab"
      />
      <ComboBox
        v-else-if="orderedInboxes.length > 5"
        v-model="selectedInboxId"
        :label="t('CAPTAIN.ASSISTANTS.ENVIOS.INBOX_LABEL')"
        :options="inboxOptions"
      />

      <article class="flex flex-col gap-5 rounded-xl border border-n-weak p-4">
        <header class="flex flex-col gap-1">
          <h2
            class="m-0 flex flex-wrap items-center gap-2 text-base font-medium text-n-slate-12"
          >
            {{ selectedInbox.name }}
            <span
              class="rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-11"
              >{{ channelLabel(selectedInbox) }}</span
            >
            <span
              v-if="selectedInbox.channel_type === 'Channel::Whatsapp'"
              class="rounded-md px-2 py-0.5 text-xs"
              :class="
                serverInbox?.channel?.needs_reauthorization
                  ? 'bg-n-amber-3 text-n-amber-11'
                  : 'bg-n-teal-3 text-n-teal-11'
              "
            >
              {{
                t(
                  serverInbox?.channel?.needs_reauthorization
                    ? 'CAPTAIN.ASSISTANTS.ENVIOS.CONNECTION.NEEDS_REVIEW'
                    : 'CAPTAIN.ASSISTANTS.ENVIOS.CONNECTION.CONNECTED'
                )
              }}
            </span>
          </h2>
          <p
            v-if="
              selectedInbox.phone_number ||
              selectedInbox.provider_config?.business_account_id
            "
            class="mb-0 text-xs text-n-slate-11"
          >
            <span v-if="selectedInbox.phone_number">{{
              selectedInbox.phone_number
            }}</span>
            <span v-if="selectedInbox.provider_config?.business_account_id">
              <span
                v-if="selectedInbox.phone_number"
                aria-hidden="true"
                class="mx-1 inline-block size-1 rounded-full bg-n-slate-7"
              />
              {{
                t('CAPTAIN.ASSISTANTS.ENVIOS.ACCOUNT', {
                  name:
                    serverInbox?.channel?.business_account_name ||
                    selectedInbox.provider_config.business_account_id,
                })
              }}</span
            >
            <span v-if="serverInbox?.channel?.business_portfolio_name">
              <span
                aria-hidden="true"
                class="mx-1 inline-block size-1 rounded-full bg-n-slate-7"
              />
              {{
                t('CAPTAIN.ASSISTANTS.ENVIOS.PORTFOLIO', {
                  name: serverInbox.channel.business_portfolio_name,
                })
              }}
            </span>
          </p>
          <p
            v-if="
              serverInbox?.waba_id &&
              whatsappInboxes.filter(
                item =>
                  item.provider_config?.business_account_id ===
                  serverInbox.waba_id
              ).length > 1
            "
            class="mb-0 text-xs text-n-slate-11"
          >
            {{
              t('CAPTAIN.ASSISTANTS.ENVIOS.SHARES_WITH_MANY', {
                count:
                  whatsappInboxes.filter(
                    item =>
                      item.provider_config?.business_account_id ===
                      serverInbox.waba_id
                  ).length - 1,
              })
            }}
          </p>
        </header>

        <Banner
          v-if="serverInbox?.channel?.quality_rating === 'RED'"
          color="amber"
        >
          {{ t('CAPTAIN.ASSISTANTS.ENVIOS.QUALITY_RED') }}
        </Banner>
        <Banner
          v-else-if="serverInbox?.channel?.quality_rating === 'YELLOW'"
          color="amber"
        >
          {{ t('CAPTAIN.ASSISTANTS.ENVIOS.QUALITY_YELLOW') }}
        </Banner>
        <p
          v-if="serverInbox?.channel?.templates_stale"
          class="mb-0 text-xs text-n-amber-11"
        >
          {{
            t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES_STALE', {
              date: serverInbox.channel.templates_last_updated_at || '',
            })
          }}
        </p>

        <template v-if="selectedInbox.channel_type === 'Channel::Whatsapp'">
          <SettingsToggleSection
            :model-value="currentEntry.enabled === true"
            :header="t('CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.TOGGLE')"
            :description="t('CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.HELP')"
            @update:model-value="currentEntry.enabled = $event"
          />
          <template v-if="currentEntry.enabled">
            <TabBar
              :tabs="resourceTabs"
              :initial-active-tab="activeResourceIndex"
              :tab-list-label="t('CAPTAIN.ASSISTANTS.ENVIOS.RESOURCE_TABS')"
              data-testid="resource-tabs"
              @tab-changed="activeResourceIndex = $event.index"
            />
            <section
              v-for="section in visibleResourceSections"
              :key="section.kind"
              class="flex flex-col gap-2"
            >
              <h3
                class="m-0 flex items-center justify-between text-heading-3 text-n-slate-12"
              >
                {{ t(`CAPTAIN.ASSISTANTS.ENVIOS.${section.title}.TITLE`) }}
                <RouterLink
                  :to="section.createRoute"
                  class="text-sm text-n-brand underline"
                >
                  {{ t(`CAPTAIN.ASSISTANTS.ENVIOS.${section.title}.CREATE`) }}
                </RouterLink>
              </h3>
              <p
                v-if="section.kind === 'template' && !paidTemplates"
                class="mb-0 rounded-lg bg-n-amber-3 px-3 py-2 text-body-main text-n-amber-11"
                data-testid="templates-paid-off"
              >
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.PAID.ROWS_OFF') }}
              </p>
              <template v-for="group in section.groups" :key="group.id">
                <template v-if="group.rows.length">
                  <div
                    class="mt-2 flex items-center justify-between text-label-small text-n-slate-11"
                  >
                    <span
                      >{{ t(`CAPTAIN.ASSISTANTS.ENVIOS.GROUPS.${group.id}`) }} ·
                      {{ group.rows.length }}</span
                    >
                    <Button
                      v-if="group.id === 'UNUSABLE'"
                      intent="tertiary"
                      sm
                      :aria-expanded="expanded[group.key] === true"
                      :label="
                        t(
                          expanded[group.key]
                            ? 'CAPTAIN.ASSISTANTS.ENVIOS.GROUPS.HIDE'
                            : 'CAPTAIN.ASSISTANTS.ENVIOS.GROUPS.SHOW'
                        )
                      "
                      @click="expanded[group.key] = !expanded[group.key]"
                    />
                  </div>
                  <ul
                    v-if="group.id !== 'UNUSABLE' || expanded[group.key]"
                    class="m-0 list-none divide-y divide-n-weak overflow-hidden rounded-lg border border-n-weak p-0"
                    :data-testid="`${section.kind}-${group.id}`"
                  >
                    <CaptainResourceRow
                      v-for="row in group.rows"
                      :key="row.key"
                      :data-testid="`messaging-${row.kind}-row`"
                      :name="
                        row.kind === 'flow'
                          ? row.flow?.name || String(row.resource.id)
                          : row.resource.name
                      "
                      :language="row.resource.language || ''"
                      :category="
                        row.kind === 'template'
                          ? t(
                              `CAPTAIN.ASSISTANTS.ENVIOS.CATEGORY.${row.resource.category?.toUpperCase() || 'UTILITY'}`
                            )
                          : ''
                      "
                      :state="row.state"
                      :state-label="stateLabel(row.state)"
                      :usages="rowUsages(row)"
                      :disabled="
                        (row.kind === 'template' &&
                          (!paidTemplates ||
                            serverInbox?.channel?.quality_rating === 'RED')) ||
                        reviewing[row.key] === true
                      "
                      :dimmed="
                        (row.kind === 'template' && !paidTemplates) ||
                        group.id === 'UNUSABLE'
                      "
                      :publish-route="
                        row.state === 'not_published_here'
                          ? flowEditRoute(row)
                          : null
                      "
                      @toggle="toggleResource(row)"
                      @preview="openPreview(row)"
                      @assign="openAssignment(row)"
                    />
                  </ul>
                </template>
              </template>
            </section>
          </template>
        </template>
        <p v-else class="mb-0 text-body-main text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANTS.ENVIOS.ONLY_WHATSAPP') }}
        </p>
      </article>
    </template>

    <div>
      <Button
        intent="primary"
        data-testid="messaging-save"
        :disabled="!capValid"
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="save"
      />
    </div>

    <Dialog
      ref="assignDialog"
      :title="
        t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.ASSIGN_TITLE', {
          name: selectedRow?.flow?.name || selectedRow?.resource?.name || '',
        })
      "
      :confirm-button-label="t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.SAVE')"
      @confirm="saveAssignment"
    >
      <div class="flex flex-col gap-3">
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.ASSIGN_HELP') }}
        </p>
        <ComboBox
          v-for="variable in selectedRow?.missing || []"
          :key="variable"
          :model-value="bindingsDraft[variable]"
          :label="variable"
          :options="bindingOptions"
          @update:model-value="bindingsDraft[variable] = $event"
        />
      </div>
    </Dialog>
    <CaptainTemplatePreview
      ref="templatePreview"
      :template="selectedRow?.template"
      :params="selectedRow?.processed_params"
      :sources="selectedRow?.sources"
      :complete="selectedRow?.state !== 'needs_data'"
      :available="selectedRow?.template?.status?.toUpperCase() === 'APPROVED'"
      :inbox-name="selectedInbox?.name || ''"
      :variable-options="variableOptions"
      :preview-values="previewValues"
    />
    <FlowPreviewDrawer ref="previewDrawer" />
  </div>
</template>
