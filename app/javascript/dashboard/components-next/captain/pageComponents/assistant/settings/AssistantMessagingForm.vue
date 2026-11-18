<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import AssistantAPI from 'dashboard/api/captain/assistant';
import CaptainInboxesAPI from 'dashboard/api/captain/inboxes';
import InboxesAPI from 'dashboard/api/inboxes';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import Button from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import FlowPreviewDrawer from 'dashboard/routes/dashboard/settings/templates/flows/FlowPreviewDrawer.vue';
import CaptainTemplatePreview from './CaptainTemplatePreview.vue';
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
const calendarConnections = ref([]);
const capValue = ref(50);
const capUsed = ref(0);
const expanded = reactive({});
const noteDialog = ref(null);
const templatePreview = ref(null);
const assignDialog = ref(null);
const previewDrawer = ref(null);
const selectedRow = ref(null);
const noteDraft = ref('');
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
function reminderStatus(inbox) {
  const reminder = props.assistant?.config?.appointments?.template_reminder;
  if (!reminder?.name) return 'PICK';
  const exists = (inbox.message_templates || []).some(
    item =>
      item.name === reminder.name &&
      item.language === reminder.language &&
      String(item.status).toUpperCase() === 'APPROVED'
  );
  return exists ? 'APPROVED_HERE' : 'MISSING_HERE';
}
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
  const reminderPending =
    inbox.channel_type === 'Channel::Whatsapp' &&
    reminderStatus(inbox) === 'MISSING_HERE'
      ? 1
      : 0;
  return resourcePending + reminderPending;
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
const stateClass = state => {
  if (state === 'available') return 'bg-n-teal-3 text-n-teal-11';
  if (
    [
      'needs_data',
      'pending',
      'new',
      'changed',
      'needs_review',
      'not_published_here',
    ].includes(state)
  )
    return 'bg-n-amber-3 text-n-amber-11';
  if (state === 'rejected') return 'bg-n-ruby-3 text-n-ruby-11';
  return 'bg-n-alpha-2 text-n-slate-11';
};
const stateLabel = state =>
  t(`CAPTAIN.ASSISTANTS.ENVIOS.STATES.${stateLabels[state] || 'UNAVAILABLE'}`);
const rowReason = row => {
  if (row.reason) return row.reason;
  if (row.state === 'needs_data')
    return t('CAPTAIN.ASSISTANTS.ENVIOS.REASONS.NEEDS_DATA', {
      variables: (row.missing || []).join(', '),
    });
  if (row.state === 'unsupported')
    return t('CAPTAIN.ASSISTANTS.ENVIOS.REASONS.UNSUPPORTED');
  if (row.state === 'needs_review')
    return t('CAPTAIN.ASSISTANTS.ENVIOS.REASONS.NEEDS_REVIEW');
  if (row.state === 'not_published_here')
    return t('CAPTAIN.ASSISTANTS.ENVIOS.REASONS.NOT_PUBLISHED_HERE');
  return '';
};
const setResourceExcluded = row => {
  if (currentEntry.value.mode === 'list') {
    const field = row.kind === 'template' ? 'templates' : 'flows';
    const list = currentEntry.value[field] || [];
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
            row.kind === 'template'
              ? {
                  name: row.resource.name,
                  language: row.resource.language,
                  purpose: '',
                  processed_params: {},
                }
              : { flow_id: row.resource.id, purpose: '' },
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
const isResourceToggle = row => ['available', 'excluded'].includes(row.state);
const reviewResource = async row => {
  try {
    await AssistantAPI.allowResource({
      assistantId: props.assistant.id,
      inboxId: selectedInboxId.value,
      kind: row.kind,
      key: row.key,
    });
    await store.dispatch('captainAssistants/show', props.assistant.id);
  } catch (error) {
    if (error.response?.status === 409) {
      useAlert(t('CAPTAIN.ASSISTANTS.ENVIOS.CONFLICT'));
      return;
    }
    useAlert(
      error.response?.data?.error || t('CAPTAIN.ASSISTANTS.EDIT.ERROR_MESSAGE')
    );
  }
};
const getNote = row =>
  currentEntry.value.notes?.[
    row.kind === 'template' ? `template:${row.key}` : `flow:${row.key}`
  ] ||
  row.note ||
  '';
const openNote = row => {
  selectedRow.value = row;
  noteDraft.value = getNote(row);
  noteDialog.value?.open();
};
const saveNote = () => {
  if (currentEntry.value.mode === 'list') {
    if (selectedRow.value.kind === 'template') {
      const entry = currentEntry.value.templates.find(
        template =>
          template.name === selectedRow.value.resource.name &&
          template.language === selectedRow.value.resource.language
      );
      if (entry) entry.purpose = noteDraft.value.trim();
    } else {
      const entry = currentEntry.value.flows.find(
        flow => flow.flow_id === selectedRow.value.resource.id
      );
      if (entry) entry.purpose = noteDraft.value.trim();
    }
    noteDialog.value?.close();
    return;
  }
  const key =
    selectedRow.value.kind === 'template'
      ? `template:${selectedRow.value.key}`
      : `flow:${selectedRow.value.key}`;
  currentEntry.value.notes[key] = noteDraft.value.trim();
  noteDialog.value?.close();
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
  await store.dispatch('captainAssistants/show', props.assistant.id);
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
const updateAppointment = async value => {
  await CaptainInboxesAPI.updateAppointments({
    assistantId: props.assistant.id,
    inboxId: selectedInboxId.value,
    appointmentsEnabled: value,
  });
  const linked = (linkedInboxes.value || []).find(
    item => item.id === selectedInboxId.value
  );
  if (linked) linked.appointments_enabled = value;
};
const calendarName = computed(() => {
  const settings = props.assistant?.config?.appointments || {};
  const connection = calendarConnections.value.find(
    item => item.id === settings.calendar_connection_id
  );
  return connection?.name || connection?.email || '';
});
const calendarConnected = computed(() => Boolean(calendarName.value));
const assistantAppointmentsEnabled = computed(
  () => props.assistant?.config?.appointments?.enabled !== false
);
const followupName = computed(
  () => props.assistant?.config?.followup?.reengagement_template?.name || ''
);
const followupEnabled = computed(
  () => props.assistant?.config?.followup?.reengagement_enabled === true
);
const followupExists = inbox => {
  const reminder = props.assistant?.config?.followup?.reengagement_template;
  return (
    reminder?.name &&
    (inbox.message_templates || []).some(
      item =>
        item.name === reminder.name &&
        item.language === reminder.language &&
        String(item.status).toUpperCase() === 'APPROVED'
    )
  );
};
const flowFields = row => {
  const fields =
    row.flow?.definition?.screens?.flatMap(screen =>
      (screen.layout?.children || [])
        .filter(item => item.label)
        .map(item => item.label)
    ) || [];
  return fields.length
    ? t('CAPTAIN.ASSISTANTS.ENVIOS.FLOWS.FIELDS', { fields: fields.join(', ') })
    : '';
};
const templatePurpose = row => {
  if (row.note) return row.note;
  const body =
    row.template?.components?.find(item => item.type === 'BODY')?.text || '';
  return body;
};
const capValid = computed(
  () =>
    Number.isInteger(Number(capValue.value)) &&
    Number(capValue.value) >= 0 &&
    Number(capValue.value) <= 10000
);
const messagingCounts = computed(() => {
  const rows = [...templateRows.value, ...flowRows.value];
  const available = rows.filter(row => row.state === 'available').length;
  const excluded = rows.filter(row =>
    ['excluded', 'marketing_off'].includes(row.state)
  ).length;
  return {
    available,
    excluded,
    unavailable: rows.length - available - excluded,
  };
});
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
        revision: savedMessaging.value.revision || 0,
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
const openSettings = name => ({
  name,
  params: { accountId: route.params.accountId },
});
const flowEditRoute = row => ({
  name: 'settings_flow_edit',
  params: { flowId: row.resource.id },
});

onMounted(async () => {
  loadEnvios();
  try {
    await store.dispatch('captainInboxes/get', {
      assistantId: route.params.assistantId,
    });
    await store.dispatch('inboxes/get');
    const [flowResponse, calendarResponse] = await Promise.all([
      WhatsappFlowsAPI.list({ per_page: 100 }),
      CalendarAPI.getConnections(),
    ]);
    flows.value = flowResponse.data.payload || [];
    calendarConnections.value = calendarResponse.data.payload || [];
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
      :description="t('CAPTAIN.ASSISTANTS.ENVIOS.PAID.HELP')"
    >
      <span class="px-4 text-xs text-n-slate-11">
        {{ t('CAPTAIN.ASSISTANTS.ENVIOS.PAID.SCOPE') }}
      </span>
    </SettingsToggleSection>

    <div v-if="whatsappInboxes.length" class="flex flex-col gap-2">
      <label
        class="text-sm font-medium text-n-slate-12"
        for="captain-daily-cap"
      >
        {{ t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.LABEL') }}
      </label>
      <Input
        id="captain-daily-cap"
        v-model.number="capValue"
        type="number"
        min="0"
        max="10000"
      />
      <p v-if="!capValid" class="mb-0 text-xs text-n-ruby-9" role="alert">
        {{ t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.INVALID') }}
      </p>
      <p class="mb-0 text-xs text-n-slate-11">
        {{
          t('CAPTAIN.ASSISTANTS.ENVIOS.CAP.HELP', {
            used: capUsed,
            cap: capValue,
          })
        }}
      </p>
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

        <section class="flex flex-col gap-2">
          <h3 class="m-0 text-sm font-medium text-n-slate-12">
            {{ t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.TITLE') }}
          </h3>
          <SettingsToggleSection
            v-if="assistantAppointmentsEnabled"
            :model-value="selectedInbox.appointments_enabled !== false"
            :header="t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.TOGGLE')"
            @update:model-value="updateAppointment"
          />
          <SettingsToggleSection
            v-else
            :model-value="false"
            :header="t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.TOGGLE')"
            hide-toggle
          >
            <template #hiddenToggle>
              <span
                role="switch"
                aria-checked="false"
                aria-disabled="true"
                class="pointer-events-none rounded-full bg-n-slate-6 px-2 py-1 text-xs text-n-slate-11 opacity-60"
              >
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.DISABLED') }}
              </span>
            </template>
          </SettingsToggleSection>
          <template v-if="selectedInbox.appointments_enabled !== false">
            <p
              v-if="!assistantAppointmentsEnabled"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.ASSISTANT_OFF') }}
              <RouterLink
                :to="
                  openSettings('captain_assistants_settings_appointments_index')
                "
                class="text-n-brand underline"
              >
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.LINK') }}
              </RouterLink>
            </p>
            <p v-else class="mb-0 text-sm text-n-slate-11">
              <template v-if="calendarConnected">
                {{
                  t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.CALENDAR', {
                    name: calendarName,
                  })
                }}
                <span
                  aria-hidden="true"
                  class="mx-1 inline-block size-1 rounded-full bg-n-slate-7"
                />
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.CONNECTED') }}
              </template>
              <template v-else>
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.NO_CALENDAR') }}
                <RouterLink
                  :to="accountScopedRoute('settings_integrations_calendars')"
                  class="text-n-brand underline"
                >
                  {{ t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.CONNECT') }}
                </RouterLink>
              </template>
            </p>
            <p
              v-if="assistantAppointmentsEnabled"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.INSIDE') }}
              <template
                v-if="selectedInbox.channel_type === 'Channel::Whatsapp'"
              >
                <span
                  aria-hidden="true"
                  class="mx-1 inline-block size-1 rounded-full bg-n-slate-7"
                />
                {{
                  t(
                    `CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.${reminderStatus(selectedInbox)}`,
                    {
                      name:
                        props.assistant?.config?.appointments?.template_reminder
                          ?.name || '',
                    }
                  )
                }}
              </template>
              <template v-else>
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.OUTSIDE_NONE') }}
              </template>
            </p>
          </template>
          <p v-else class="mb-0 text-sm text-n-slate-11">
            {{ t('CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.OFF') }}
          </p>
        </section>

        <template v-if="selectedInbox.channel_type === 'Channel::Whatsapp'">
          <SettingsToggleSection
            :model-value="currentEntry.enabled === true"
            :header="t('CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.TOGGLE')"
            :description="t('CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.HELP')"
            @update:model-value="currentEntry.enabled = $event"
          />
          <button
            v-if="currentEntry.enabled"
            type="button"
            class="flex w-full flex-wrap items-center justify-between gap-2 rounded-xl border border-n-weak px-3 py-3 text-start text-sm text-n-slate-12"
            :aria-expanded="expanded[selectedInboxId] === true"
            @click="expanded[selectedInboxId] = !expanded[selectedInboxId]"
          >
            <span>{{
              t('CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.COUNTS', messagingCounts)
            }}</span>
            <span class="text-n-brand underline">{{
              t(
                expanded[selectedInboxId]
                  ? 'CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.HIDE'
                  : 'CAPTAIN.ASSISTANTS.ENVIOS.MESSAGING.SHOW'
              )
            }}</span>
          </button>
          <template v-if="currentEntry.enabled && expanded[selectedInboxId]">
            <section class="flex flex-col gap-2">
              <h3
                class="m-0 flex items-center justify-between text-sm font-medium text-n-slate-12"
              >
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.FLOWS.TITLE') }}
                <RouterLink
                  :to="{ name: 'settings_flow_new' }"
                  class="text-n-brand underline"
                >
                  {{ t('CAPTAIN.ASSISTANTS.ENVIOS.FLOWS.CREATE') }}
                </RouterLink>
              </h3>
              <ul class="m-0 flex list-none flex-col gap-2 p-0">
                <li
                  v-for="row in flowRows"
                  :key="row.key"
                  class="flex flex-wrap items-center gap-2 rounded-lg bg-n-solid-2 p-3"
                  data-testid="messaging-flow-row"
                >
                  <div class="min-w-0 grow">
                    <strong class="text-sm text-n-slate-12">{{
                      row.flow?.name || row.resource.id
                    }}</strong>
                    <p
                      v-if="row.note || flowFields(row)"
                      class="mb-0 text-xs text-n-slate-11"
                    >
                      {{ row.note || flowFields(row) }}
                    </p>
                  </div>
                  <span
                    class="rounded-md px-2 py-0.5 text-xs"
                    :class="stateClass(row.state)"
                    >{{ stateLabel(row.state) }}</span
                  >
                  <Button
                    slate
                    outline
                    sm
                    icon="i-lucide-eye"
                    :aria-label="
                      t('CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_FLOW', {
                        name: row.flow?.name || row.resource.id,
                      })
                    "
                    @click="openPreview(row)"
                  />
                  <Button
                    v-if="row.state === 'not_published_here'"
                    slate
                    outline
                    sm
                    :label="t('CAPTAIN.ASSISTANTS.ENVIOS.FLOWS.PUBLISH')"
                    :to="flowEditRoute(row)"
                  />
                  <button
                    v-else-if="isResourceToggle(row)"
                    type="button"
                    role="switch"
                    class="rounded-full px-2 py-1 text-xs"
                    :aria-checked="row.state === 'available'"
                    @click="setResourceExcluded(row)"
                  >
                    {{
                      t('CAPTAIN.ASSISTANTS.ENVIOS.ROW_TOGGLE', {
                        name: row.flow?.name || row.resource.id,
                      })
                    }}
                  </button>
                  <Button
                    v-else-if="
                      ['new', 'changed', 'needs_review'].includes(row.state)
                    "
                    slate
                    outline
                    sm
                    :label="t('CAPTAIN.ASSISTANTS.ENVIOS.ROW_ALLOW')"
                    @click="reviewResource(row)"
                  />
                </li>
              </ul>
            </section>
            <section class="flex flex-col gap-2">
              <h3
                class="m-0 flex items-center justify-between text-sm font-medium text-n-slate-12"
              >
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.TITLE') }}
                <RouterLink
                  :to="accountScopedRoute('settings_templates')"
                  class="text-n-brand underline"
                >
                  {{ t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.CREATE') }}
                </RouterLink>
              </h3>
              <ul class="m-0 flex list-none flex-col gap-2 p-0">
                <li
                  v-for="row in templateRows"
                  :key="row.key"
                  class="flex flex-wrap items-center gap-2 rounded-lg bg-n-solid-2 p-3"
                  data-testid="messaging-template-row"
                >
                  <div class="min-w-0 grow">
                    <strong class="text-sm text-n-slate-12"
                      >{{ row.resource.name }} ({{
                        row.resource.language
                      }})</strong
                    >
                    <span
                      class="ms-2 rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-11"
                      >{{
                        t(
                          `CAPTAIN.ASSISTANTS.ENVIOS.CATEGORY.${row.resource.category?.toUpperCase() || 'UTILITY'}`
                        )
                      }}</span
                    >
                    <p
                      v-if="rowReason(row)"
                      class="mb-0 text-xs text-n-slate-11"
                    >
                      {{ rowReason(row) }}
                    </p>
                    <p v-else class="mb-0 text-xs text-n-slate-11">
                      {{
                        t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.USED_FOR', {
                          text: templatePurpose(row),
                        })
                      }}
                      <button
                        type="button"
                        class="text-n-brand underline"
                        @click="openNote(row)"
                      >
                        {{
                          t(
                            row.note
                              ? 'CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.EDIT_NOTE'
                              : 'CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.ADD_NOTE'
                          )
                        }}
                      </button>
                    </p>
                  </div>
                  <span
                    class="rounded-md px-2 py-0.5 text-xs"
                    :class="stateClass(row.state)"
                    >{{ stateLabel(row.state) }}</span
                  >
                  <Button
                    slate
                    outline
                    sm
                    icon="i-lucide-eye"
                    :aria-label="
                      t('CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_TEMPLATE', {
                        name: row.resource.name,
                      })
                    "
                    @click="openPreview(row)"
                  />
                  <Button
                    v-if="row.state === 'needs_data'"
                    slate
                    outline
                    sm
                    :label="t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.ASSIGN')"
                    @click="openAssignment(row)"
                  />
                  <Button
                    v-if="
                      ['new', 'changed', 'needs_review'].includes(row.state)
                    "
                    slate
                    outline
                    sm
                    :label="t('CAPTAIN.ASSISTANTS.ENVIOS.ROW_ALLOW')"
                    @click="reviewResource(row)"
                  />
                  <button
                    v-if="isResourceToggle(row)"
                    type="button"
                    role="switch"
                    class="rounded-full px-2 py-1 text-xs"
                    :aria-checked="row.state === 'available'"
                    @click="setResourceExcluded(row)"
                  >
                    {{
                      t('CAPTAIN.ASSISTANTS.ENVIOS.ROW_TOGGLE', {
                        name: row.resource.name,
                      })
                    }}
                  </button>
                </li>
              </ul>
              <p class="mb-0 text-xs text-n-slate-11">
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.FOOTER') }}
              </p>
            </section>
          </template>
          <section class="flex flex-col gap-2">
            <h3 class="m-0 text-sm font-medium text-n-slate-12">
              {{ t('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.TITLE') }}
            </h3>
            <div
              class="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-n-weak p-3 text-sm text-n-slate-12"
            >
              <span>
                {{
                  followupName
                    ? t('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.REENGAGEMENT', {
                        name: followupName,
                      })
                    : t('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.NO_TEMPLATE')
                }}
                <template v-if="followupName">
                  <span
                    aria-hidden="true"
                    class="mx-1 inline-block size-1 rounded-full bg-n-slate-7"
                  />
                  {{
                    followupExists(selectedInbox)
                      ? t(
                          'CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.APPROVED_HERE',
                          { name: followupName }
                        )
                      : t(
                          'CAPTAIN.ASSISTANTS.ENVIOS.APPOINTMENTS.MISSING_HERE',
                          { name: followupName }
                        )
                  }}
                </template>
                <span
                  aria-hidden="true"
                  class="mx-1 inline-block size-1 rounded-full bg-n-slate-7"
                />
                {{
                  followupEnabled
                    ? t('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.NUDGE_ON')
                    : t('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.NUDGE_OFF')
                }}
              </span>
              <RouterLink
                :to="openSettings('captain_assistants_settings_followup_index')"
                class="text-n-brand underline"
              >
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.LINK') }}
              </RouterLink>
            </div>
          </section>
        </template>
        <template v-else>
          <section class="flex flex-col gap-2">
            <h3 class="m-0 text-sm font-medium text-n-slate-12">
              {{ t('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.TITLE') }}
            </h3>
            <div
              class="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-n-weak p-3 text-sm text-n-slate-12"
            >
              <span v-if="selectedInbox.channel_type === 'Channel::Email'">
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.NUDGE_EMAIL') }}
              </span>
              <span v-else-if="followupEnabled">
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.NUDGE_ON') }}
              </span>
              <span v-else>
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.NUDGE_OFF') }}
              </span>
              <RouterLink
                :to="openSettings('captain_assistants_settings_followup_index')"
                class="text-n-brand underline"
              >
                {{ t('CAPTAIN.ASSISTANTS.ENVIOS.FOLLOWUP.LINK') }}
              </RouterLink>
            </div>
          </section>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('CAPTAIN.ASSISTANTS.ENVIOS.ONLY_WHATSAPP') }}
          </p>
        </template>
      </article>
    </template>

    <Button
      data-testid="messaging-save"
      :disabled="!capValid"
      :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
      @click="save"
    />

    <Dialog
      ref="noteDialog"
      :title="
        t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.NOTE_TITLE', {
          name: selectedRow?.resource?.name || '',
        })
      "
      :confirm-button-label="t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.SAVE')"
      @confirm="saveNote"
    >
      <TextArea
        v-model="noteDraft"
        maxlength="300"
        :label="t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.NOTE_LABEL')"
        :help="t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.NOTE_HELP')"
      />
    </Dialog>
    <Dialog
      ref="assignDialog"
      :title="
        t('CAPTAIN.ASSISTANTS.ENVIOS.TEMPLATES.ASSIGN_TITLE', {
          name: selectedRow?.resource?.name || '',
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
