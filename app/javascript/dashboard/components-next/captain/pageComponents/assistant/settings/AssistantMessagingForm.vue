<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import AccountAPI from 'dashboard/api/account';
import Switch from 'dashboard/components-next/switch/Switch.vue';
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
const { isAdmin } = useAdmin();
const saving = ref(false);
const conflict = ref(false);
const pendingAllows = reactive({});
const baseline = ref('');
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
const capValue = ref(50);
const capUsed = ref(0);
const expanded = reactive({});
const templatePreview = ref(null);
const assignDialog = ref(null);
const previewDrawer = ref(null);
const selectedRow = ref(null);
const bindingsDraft = reactive({});
const paidTemplates = ref(false);
const paidExplanation = computed(() =>
  t(
    paidTemplates.value
      ? 'CAPTAIN.ASSISTANTS.ENVIOS.PAID.ON_LINE'
      : 'CAPTAIN.ASSISTANTS.ENVIOS.PAID.OFF_LINE'
  )
);
const permissionEntries = reactive({});
const draftSnapshot = () =>
  JSON.stringify([
    paidTemplates.value,
    Number(capValue.value),
    permissionEntries,
    pendingAllows,
  ]);
const dirty = computed(() => baseline.value !== draftSnapshot());

// The list endpoint omits the per-inbox state (`envios`): read it from the single-assistant endpoint.
const serverEnvios = ref(null);
const envios = computed(
  () => serverEnvios.value || props.assistant?.envios || {}
);
const loadEnvios = async () => {
  try {
    const { data } = await AssistantAPI.show(route.params.assistantId);
    serverEnvios.value = data.envios;
    return data;
  } catch (error) {
    loadingFailed.value = true;
    throw error;
  }
};

const connectedInboxes = computed(() => {
  const ids = (linkedInboxes.value || []).map(item => item.id);
  return ids
    .map(id => (allInboxes.value || []).find(item => item.id === id))
    .filter(Boolean);
});
const whatsappInboxes = computed(() =>
  connectedInboxes.value.filter(
    inbox => inbox.channel_type === 'Channel::Whatsapp'
  )
);
const orderedInboxes = whatsappInboxes;
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
  if (pendingAllows[`${selectedInboxId.value}:${key}`]) return 'available';
  if (!['available', 'excluded', 'unavailable'].includes(item.state))
    return item.state;
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
  needs_data: 'CHIPS.NEEDS_DATA',
  pending: 'STATES.PENDING',
  rejected: 'STATES.REJECTED',
  unsupported: 'CHIPS.UNSUPPORTED',
  not_published_here: 'CHIPS.NOT_PUBLISHED',
  new: 'CHIPS.NEW',
  changed: 'CHIPS.CHANGED',
  needs_review: 'CHIPS.LINK',
};
const stateLabel = row => {
  if (
    row.kind === 'template' &&
    serverInbox.value?.channel?.quality_rating === 'RED'
  )
    return t('CAPTAIN.ASSISTANTS.ENVIOS.CHIPS.QUALITY');
  return stateLabels[row.state]
    ? t(`CAPTAIN.ASSISTANTS.ENVIOS.${stateLabels[row.state]}`)
    : '';
};
const GROUPS = ['READY', 'PERMISSION', 'BLOCKED'];
const groupFor = state => {
  if (['available', 'excluded', 'unavailable'].includes(state)) return 'READY';
  if (
    ['marketing_off', 'new', 'changed', 'needs_review', 'needs_data'].includes(
      state
    )
  )
    return 'PERMISSION';
  return 'BLOCKED';
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
        resourceGroups[key] = groupFor(item.state);
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
    label: t(`CAPTAIN.ASSISTANTS.ENVIOS.TABS.${section.title}`),
    showZero: true,
    attentionLabel: t('CAPTAIN.ASSISTANTS.ENVIOS.GROUPS.PERMISSION'),
    count: section.groups.reduce(
      (count, group) => count + group.rows.length,
      0
    ),
    attention: section.groups.some(
      group => group.id === 'PERMISSION' && group.rows.length > 0
    ),
    index,
  }))
);
watch([selectedInboxId, serverEnvios], () => {
  activeResourceIndex.value = resourceTabs.value[1]?.attention ? 1 : 0;
});
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
    usages.push(t('CAPTAIN.ASSISTANTS.ENVIOS.CHIPS.USED_BY_APPOINTMENTS'));
  if (matches(props.assistant?.config?.followup?.reengagement_template))
    usages.push(t('CAPTAIN.ASSISTANTS.ENVIOS.CHIPS.USED_BY_FOLLOWUP'));
  return usages;
};
const setResourceExcluded = row => {
  if (currentEntry.value.mode === 'list') {
    const field = row.kind === 'template' ? 'templates' : 'flows';
    const list = currentEntry.value[field] || [];
    const savedEntry = (savedMessaging.value.inboxes || []).find(
      entry => entry.inbox_id === selectedInboxId.value
    );
    const saved = savedEntry?.[field]?.find(entry =>
      row.kind === 'template'
        ? entry.name === row.resource.name &&
          entry.language === row.resource.language
        : entry.flow_id === row.resource.id
    );
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
const toggleResource = row => {
  const key = `${selectedInboxId.value}:${row.key}`;
  if (pendingAllows[key]) delete pendingAllows[key];
  else if (['available', 'excluded'].includes(row.state))
    setResourceExcluded(row);
  else
    pendingAllows[key] = {
      assistantId: props.assistant.id,
      inboxId: selectedInboxId.value,
      kind: row.kind,
      key: row.key,
    };
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
    Number.isInteger(capValue.value) &&
    Number(capValue.value) >= 0 &&
    Number(capValue.value) <= 10000
);
const hydrate = (assistant = props.assistant) => {
  const messaging = assistant.config?.messaging || {};
  messagingRevision.value = messaging.revision || 0;
  paidTemplates.value = assistant.config?.allow_paid_templates === true;
  capValue.value = envios.value?.template_cap?.cap ?? 50;
  capUsed.value = envios.value?.template_cap?.used ?? 0;
  Object.keys(permissionEntries).forEach(key => delete permissionEntries[key]);
  (messaging.inboxes || []).forEach(entry => {
    permissionEntries[entry.inbox_id] = JSON.parse(JSON.stringify(entry));
  });
};
const reload = async () => {
  const data = await store.dispatch(
    'captainAssistants/show',
    props.assistant.id
  );
  serverEnvios.value = data.envios;
  Object.keys(pendingAllows).forEach(key => delete pendingAllows[key]);
  hydrate(data);
  baseline.value = draftSnapshot();
  conflict.value = false;
};
const save = async () => {
  if (!capValid.value || !isAdmin.value || saving.value) return;
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
  saving.value = true;
  conflict.value = false;
  try {
    const { data } = await AssistantAPI.update(props.assistant.id, payload);
    messagingRevision.value = data.config.messaging.revision;
    await AccountAPI.update('', {
      captain_template_daily_cap: Number(capValue.value),
    });
    // Reviews update the same revision: serialize them after the config PATCH.
    await Object.values(pendingAllows).reduce(async (previous, request) => {
      await previous;
      const response = await AssistantAPI.allowResource(request);
      messagingRevision.value = response.data.config.messaging.revision;
    }, Promise.resolve());
    await reload();
    useAlert(t('CAPTAIN.ASSISTANTS.EDIT.SUCCESS_MESSAGE'));
  } catch (error) {
    conflict.value = error.response?.status === 409;
    if (!conflict.value)
      useAlert(
        error.response?.data?.error ||
          t('CAPTAIN.ASSISTANTS.EDIT.ERROR_MESSAGE')
      );
  } finally {
    saving.value = false;
  }
};
watch(
  () => props.assistant,
  assistant => {
    if (!baseline.value || (!dirty.value && !saving.value)) {
      hydrate(assistant);
      baseline.value = draftSnapshot();
    }
  },
  { immediate: true }
);
watch(
  () => envios.value.template_cap,
  cap => {
    if (!dirty.value || inboxesLoading.value) capValue.value = cap?.cap ?? 50;
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
    if (inboxesLoading.value) baseline.value = draftSnapshot();
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
    baseline.value = draftSnapshot();
    inboxesLoading.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col gap-5" data-testid="messaging-form">
    <SettingsToggleSection
      v-if="!inboxesLoading && !loadingFailed && whatsappInboxes.length"
      :model-value="paidTemplates"
      hide-toggle
      :header="t('CAPTAIN.ASSISTANTS.ENVIOS.PAID.TITLE')"
      :description="t('CAPTAIN.ASSISTANTS.ENVIOS.PAID.SCOPE')"
      @update:model-value="paidTemplates = $event"
    >
      <template #hiddenToggle>
        <Switch
          v-model="paidTemplates"
          :disabled="!isAdmin || saving"
          :aria-label="t('CAPTAIN.ASSISTANTS.ENVIOS.PAID.TITLE')"
          class="disabled:cursor-not-allowed disabled:opacity-50"
        />
      </template>
      <p
        class="mb-0 mt-3 flex w-full items-start gap-2 border-t border-n-weak px-4 pt-3 text-body-main text-n-slate-11"
        data-testid="paid-explanation"
        aria-live="polite"
      >
        <span
          aria-hidden="true"
          class="mt-1.5 size-2 shrink-0 rounded-full"
          :class="paidTemplates ? 'bg-n-teal-9' : 'bg-n-amber-9'"
        />
        <span>{{ paidExplanation }}</span>
      </p>
    </SettingsToggleSection>

    <div
      v-if="!inboxesLoading && !loadingFailed && whatsappInboxes.length"
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
        class="w-[4.5rem]"
        :disabled="!isAdmin || saving"
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
        v-tooltip="t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.SHARED')"
        tabindex="0"
        :aria-label="t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.SHARED')"
        class="i-lucide-info size-4 text-n-slate-11"
      />
      <p v-if="capUsed >= capValue" class="mb-0 w-full text-xs text-n-amber-11">
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
      v-if="!inboxesLoading && !loadingFailed && !whatsappInboxes.length"
      color="blue"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <span>{{
          t(
            connectedInboxes.length
              ? 'CAPTAIN.ASSISTANTS.ENVIOS.NO_WHATSAPP'
              : 'CAPTAIN.ASSISTANTS.ENVIOS.NO_INBOXES'
          )
        }}</span>
        <RouterLink
          :to="accountScopedRoute('settings_inboxes')"
          class="text-n-brand underline"
        >
          {{ t('CAPTAIN.ASSISTANTS.ENVIOS.CONNECT_INBOX') }}
        </RouterLink>
      </div>
    </Banner>
    <div
      v-else-if="inboxesLoading"
      class="flex flex-col gap-3"
      role="status"
      :aria-label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.LOADING')"
    >
      <div
        v-for="bar in 3"
        :key="bar"
        class="h-3 animate-pulse rounded bg-n-alpha-2"
      />
    </div>
    <Banner v-else-if="loadingFailed" color="ruby" role="alert">
      {{ t('CAPTAIN.ASSISTANTS.ENVIOS.LOAD_ERROR') }}
    </Banner>
    <Banner v-if="!isAdmin" color="blue">
      {{ t('CAPTAIN.ASSISTANTS.ENVIOS.READ_ONLY') }}
    </Banner>
    <Banner v-if="conflict" color="amber" role="alert">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <span>{{ t('CAPTAIN.ASSISTANTS.ENVIOS.CONFLICT') }}</span>
        <Button
          intent="secondary"
          :label="t('CAPTAIN.ASSISTANTS.ENVIOS.RELOAD')"
          @click="reload"
        />
      </div>
    </Banner>

    <template v-if="!inboxesLoading && !loadingFailed && selectedInbox">
      <div
        v-if="orderedInboxes.length >= 2 && orderedInboxes.length <= 5"
        class="max-w-full overflow-x-auto"
      >
        <TabBar
          :tabs="inboxTabs"
          :initial-active-tab="activeTabIndex"
          :tab-list-label="t('CAPTAIN.ASSISTANTS.ENVIOS.INBOX_LABEL')"
          @tab-changed="selectTab"
        />
      </div>
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
            :description="
              t(
                currentEntry.enabled
                  ? 'CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.HELP'
                  : 'CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.OFF'
              )
            "
            hide-toggle
            @update:model-value="currentEntry.enabled = $event"
          >
            <template #hiddenToggle>
              <Switch
                v-model="currentEntry.enabled"
                :disabled="!isAdmin || saving"
                :aria-label="t('CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.TOGGLE')"
                class="disabled:cursor-not-allowed disabled:opacity-50"
              />
            </template>
          </SettingsToggleSection>
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
                class="m-0 flex items-center justify-end text-heading-3 text-n-slate-12"
              >
                <RouterLink
                  :to="section.createRoute"
                  class="text-sm text-n-brand underline"
                  :aria-disabled="!isAdmin"
                  @click="!isAdmin && $event.preventDefault()"
                >
                  {{ t(`CAPTAIN.ASSISTANTS.ENVIOS.${section.title}.CREATE`) }}
                </RouterLink>
              </h3>
              <p
                v-if="section.kind === 'template' && !paidTemplates"
                class="mb-0 rounded-lg bg-n-amber-3 px-3 py-2 text-body-main text-n-amber-11"
                data-testid="templates-paid-off"
              >
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.PAID.TEMPLATES_OFF') }}
              </p>
              <p
                v-if="!section.groups.some(group => group.rows.length)"
                class="mb-0 rounded-lg border border-dashed border-n-weak p-3 text-center text-body-main text-n-slate-11"
              >
                {{ t(`CAPTAIN.ASSISTANTS.ENVIOS.EMPTY.${section.title}`) }}
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
                      v-if="group.id === 'BLOCKED'"
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
                    v-if="group.id !== 'BLOCKED' || expanded[group.key]"
                    class="m-0 list-none divide-y divide-n-weak overflow-hidden rounded-xl border border-n-weak p-0"
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
                              `CAPTAIN.ASSISTANTS.ENVIOS.CHIPS.${row.resource.category?.toUpperCase() || 'UTILITY'}`
                            )
                          : ''
                      "
                      :state="row.state"
                      :state-label="stateLabel(row)"
                      :model-value="row.state === 'available'"
                      :used-by="rowUsages(row)"
                      :disabled="
                        (row.kind === 'template' &&
                          (!paidTemplates ||
                            serverInbox?.channel?.quality_rating === 'RED')) ||
                        !isAdmin ||
                        saving
                      "
                      :dimmed="row.kind === 'template' && !paidTemplates"
                      :blocked="group.id === 'BLOCKED'"
                      :disabled-reason="
                        !isAdmin
                          ? t('CAPTAIN.ASSISTANTS.ENVIOS.READ_ONLY')
                          : row.kind === 'template' && !paidTemplates
                            ? t('CAPTAIN.ASSISTANTS.ENVIOS.PAID.TEMPLATES_OFF')
                            : stateLabel(row)
                      "
                      @update:model-value="toggleResource(row)"
                      @publish="$router.push(flowEditRoute(row))"
                      @preview="openPreview(row)"
                      @assign="openAssignment(row)"
                    />
                  </ul>
                </template>
              </template>
            </section>
          </template>
        </template>
      </article>
    </template>

    <div
      v-if="!inboxesLoading && !loadingFailed && whatsappInboxes.length"
      class="flex items-center gap-3"
    >
      <Button
        intent="primary"
        data-testid="messaging-save"
        :disabled="!capValid || !isAdmin || saving"
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="save"
      />
      <span
        v-if="dirty"
        class="text-body-main text-n-amber-11"
        data-testid="unsaved"
        >{{ t('CAPTAIN.ASSISTANTS.ENVIOS.UNSAVED') }}</span
      >
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
