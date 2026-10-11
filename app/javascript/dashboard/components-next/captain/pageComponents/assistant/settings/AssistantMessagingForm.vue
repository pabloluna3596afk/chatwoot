<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import {
  isSupportedForCaptain,
  templateKey,
  templateVariables,
  variablesFilled,
} from './captainTemplates';
import {
  CONTACT_DEFAULT_VALUES,
  useTemplateVariables,
} from './useTemplateVariables';

// What Captain may send, per inbox: the Flows and templates the owner allows, each with a purpose Captain reads to
// decide when to use it. Everything starts off. This page only stores the permission (assistant.config.messaging);
// the sending itself, its limits and its cost rules live on the server.
const props = defineProps({
  assistant: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['submit']);

const { t } = useI18n();
const route = useRoute();
const store = useStore();
// The same variables (and the same selector) Follow-up uses: what the template says is filled in by name, never by the model.
const { variableOptions, previewValues } = useTemplateVariables({
  appointment: false,
});
const captainInboxes = useMapGetter('captainInboxes/getRecords');
const inboxes = useMapGetter('inboxes/getInboxes');

// { [inboxId]: { enabled, flows: [{ flow_id, purpose }], templates: [{ name, language, purpose }] } }
const permissions = reactive({});
const selectedInboxId = ref(null);
const publishedFlows = ref([]);

const whatsappInboxes = computed(() =>
  (captainInboxes.value || [])
    .map(connected => (inboxes.value || []).find(i => i.id === connected.id))
    .filter(inbox => inbox?.channel_type === 'Channel::Whatsapp')
);
const inboxOptions = computed(() =>
  whatsappInboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);
// One tab per WhatsApp inbox, each with its own Flows and templates.
const inboxTabs = computed(() =>
  inboxOptions.value.map(option => ({ label: option.label }))
);
const activeTabIndex = computed(() =>
  Math.max(
    0,
    inboxOptions.value.findIndex(
      option => option.value === selectedInboxId.value
    )
  )
);
const selectInboxTab = ({ index }) => {
  selectedInboxId.value = inboxOptions.value[index]?.value ?? null;
};
const limits = [
  'LIMIT_FLOW_GAP',
  'LIMIT_FLOWS',
  'LIMIT_TEMPLATES',
  'LIMIT_PENDING',
];
const current = computed(
  () =>
    permissions[selectedInboxId.value] || {
      enabled: false,
      flows: [],
      templates: [],
    }
);
const ensureEntry = inboxId => {
  if (!permissions[inboxId])
    permissions[inboxId] = { enabled: false, flows: [], templates: [] };
  return permissions[inboxId];
};

// The switch is per inbox: each WhatsApp inbox decides on its own whether Captain may send there.
const inboxEnabled = computed({
  get: () => current.value.enabled === true,
  set: value => {
    ensureEntry(selectedInboxId.value).enabled = value;
  },
});
const paidEnabled = computed(
  () => props.assistant?.config?.allow_paid_templates === true
);

const hydrate = () => {
  const saved = props.assistant?.config?.messaging;
  Object.keys(permissions).forEach(key => delete permissions[key]);
  (saved?.inboxes || []).forEach(entry => {
    permissions[entry.inbox_id] = {
      enabled: entry.enabled === true,
      flows: (entry.flows || []).map(flow => ({ ...flow })),
      templates: (entry.templates || []).map(template => ({
        ...template,
        processed_params: JSON.parse(
          JSON.stringify(template.processed_params || {})
        ),
      })),
    };
  });
};
watch(() => props.assistant, hydrate, { immediate: true });
watch(
  inboxOptions,
  options => {
    if (!options.some(option => option.value === selectedInboxId.value))
      selectedInboxId.value = options[0]?.value ?? null;
  },
  { immediate: true }
);

const flowById = id => publishedFlows.value.find(flow => flow.id === id);
const flowRows = computed(() =>
  current.value.flows.map(entry => ({
    ...entry,
    name: flowById(entry.flow_id)?.name || `#${entry.flow_id}`,
    available: Boolean(flowById(entry.flow_id)),
  }))
);

const inbox = computed(() =>
  (inboxes.value || []).find(i => i.id === selectedInboxId.value)
);
const approvedTemplates = computed(() =>
  (inbox.value?.message_templates || []).filter(
    template =>
      String(template.status).toLowerCase() === 'approved' &&
      isSupportedForCaptain(template)
  )
);
const templateRows = computed(() =>
  current.value.templates.map(entry => {
    const found = approvedTemplates.value.find(
      template => templateKey(template) === templateKey(entry)
    );
    return {
      ...entry,
      category: found?.category,
      available: Boolean(found),
      found,
      hasVariables: templateVariables(found).length > 0,
      complete:
        Boolean(found) && variablesFilled(found, entry.processed_params),
    };
  })
);

const flowChoices = computed(() =>
  publishedFlows.value
    .filter(flow => !current.value.flows.some(e => e.flow_id === flow.id))
    .map(flow => ({ value: flow.id, label: flow.name }))
);
const templateChoices = computed(() =>
  approvedTemplates.value
    .filter(
      template =>
        !current.value.templates.some(
          e => templateKey(e) === templateKey(template)
        )
    )
    .map(template => ({
      value: templateKey(template),
      label: `${template.name} (${template.language})`,
    }))
);

const flowDialog = ref(null);
const templateDialog = ref(null);
// editIndex is set while the variables of a template that is already allowed are being changed.
const draft = reactive({
  resource: '',
  purpose: '',
  params: {},
  editIndex: null,
});
const resetDraft = () => {
  draft.resource = '';
  draft.purpose = '';
  draft.params = {};
  draft.editIndex = null;
};
const draftTemplate = computed(() =>
  draft.editIndex === null
    ? approvedTemplates.value.find(
        template => templateKey(template) === draft.resource
      )
    : templateRows.value[draft.editIndex]?.found
);
const draftComplete = computed(
  () =>
    Boolean(draftTemplate.value) &&
    variablesFilled(draftTemplate.value, draft.params)
);
const openFlowDialog = () => {
  resetDraft();
  flowDialog.value.open();
};
const openTemplateDialog = () => {
  resetDraft();
  templateDialog.value.open();
};
const addFlow = () => {
  if (!draft.resource) return;
  ensureEntry(selectedInboxId.value).flows.push({
    flow_id: draft.resource,
    purpose: draft.purpose.trim(),
  });
  flowDialog.value.close();
};
const addTemplate = () => {
  if (!draftComplete.value) return;
  if (draft.editIndex !== null) {
    current.value.templates[draft.editIndex].processed_params = draft.params;
    templateDialog.value.close();
    return;
  }
  const [name, language] = draft.resource.split('|');
  ensureEntry(selectedInboxId.value).templates.push({
    name,
    language,
    purpose: draft.purpose.trim(),
    processed_params: draft.params,
  });
  templateDialog.value.close();
};
const openVariablesDialog = index => {
  resetDraft();
  draft.editIndex = index;
  draft.params = JSON.parse(
    JSON.stringify(current.value.templates[index].processed_params || {})
  );
  templateDialog.value.open();
};
const templateStatus = row => {
  if (!row.available) return t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.UNAVAILABLE');
  if (!row.complete)
    return t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.MISSING_VARIABLES');
  return row.category;
};
const removeFlow = index => current.value.flows.splice(index, 1);
const removeTemplate = index => current.value.templates.splice(index, 1);

const submit = () => {
  const entries = Object.entries(permissions)
    .map(([inboxId, entry]) => ({
      inbox_id: Number(inboxId),
      enabled: entry.enabled,
      flows: entry.flows,
      templates: entry.templates,
    }))
    .filter(
      entry => entry.enabled || entry.flows.length || entry.templates.length
    );
  emit('submit', {
    config: {
      ...props.assistant.config,
      messaging: { inboxes: entries },
    },
  });
};

const paidRoute = computed(() => ({
  name: 'captain_assistants_settings_paid_messages_index',
  params: { ...route.params },
}));

onMounted(async () => {
  if (route.params.assistantId)
    store.dispatch('captainInboxes/get', {
      assistantId: route.params.assistantId,
    });
  try {
    const { data } = await WhatsappFlowsAPI.list({
      state: 'published',
      per_page: 100,
    });
    publishedFlows.value = data.payload || [];
  } catch {
    publishedFlows.value = [];
  }
});
</script>

<template>
  <div class="flex flex-col gap-5" data-testid="messaging-form">
    <p v-if="!whatsappInboxes.length" class="mb-0 text-sm text-n-slate-11">
      {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.NO_INBOXES') }}
    </p>

    <template v-else>
      <!-- One tab per WhatsApp inbox: Flows and templates belong to the WhatsApp account of each inbox. -->
      <div class="flex">
        <TabBar
          :tabs="inboxTabs"
          :initial-active-tab="activeTabIndex"
          data-testid="messaging-inbox-tabs"
          @tab-changed="selectInboxTab"
        />
      </div>

      <SettingsToggleSection
        v-model="inboxEnabled"
        :header="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.TOGGLE')"
        :description="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.TOGGLE_HELP')"
        data-testid="messaging-inbox-toggle"
      />

      <section
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-1"
        data-testid="messaging-flows"
      >
        <div class="flex items-start gap-3">
          <span
            class="grid shrink-0 size-9 place-items-center rounded-lg bg-n-teal-3 text-n-teal-11"
          >
            <span class="i-lucide-workflow size-5" />
          </span>
          <div class="flex flex-col min-w-0 gap-0.5 grow">
            <h3
              class="flex items-center gap-2 mb-0 text-heading-3 text-n-slate-12"
            >
              {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.FLOWS') }}
              <span
                class="px-1.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
                data-testid="messaging-flows-count"
              >
                {{ flowRows.length }}
              </span>
            </h3>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.FLOWS_HELP') }}
            </p>
          </div>
          <Button
            slate
            outline
            sm
            class="shrink-0 !w-fit whitespace-nowrap"
            icon="i-lucide-plus"
            :label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.ADD_FLOW')"
            data-testid="messaging-add-flow"
            @click="openFlowDialog"
          />
        </div>
        <p
          v-if="!flowRows.length"
          class="mb-0 text-sm text-n-slate-11"
          data-testid="messaging-flows-empty"
        >
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.FLOWS_EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
          <li
            v-for="(row, index) in flowRows"
            :key="row.flow_id"
            class="flex items-center gap-3 p-3 rounded-lg bg-n-solid-2"
            data-testid="messaging-flow-row"
          >
            <div class="flex flex-col min-w-0 gap-1.5 grow">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ row.name }}
              </span>
              <Input
                :model-value="row.purpose"
                size="sm"
                :placeholder="
                  t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.PURPOSE_PLACEHOLDER')
                "
                @update:model-value="
                  value => (current.flows[index].purpose = value)
                "
              />
            </div>
            <span
              v-tooltip.top="
                row.available
                  ? ''
                  : t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.UNAVAILABLE_FLOW')
              "
              class="px-2 py-0.5 text-xs font-medium rounded-md shrink-0"
              :class="
                row.available
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-amber-3 text-n-amber-11'
              "
            >
              {{
                row.available
                  ? t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.STATE_PUBLISHED')
                  : t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.UNAVAILABLE')
              }}
            </span>
            <Button
              slate
              outline
              sm
              icon="i-lucide-trash-2"
              :aria-label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.REMOVE')"
              @click="removeFlow(index)"
            />
          </li>
        </ul>
      </section>

      <section
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-1"
        data-testid="messaging-templates"
      >
        <div class="flex items-start gap-3">
          <span
            class="grid shrink-0 size-9 place-items-center rounded-lg bg-n-blue-3 text-n-blue-11"
          >
            <span class="i-lucide-layout-template size-5" />
          </span>
          <div class="flex flex-col min-w-0 gap-0.5 grow">
            <h3
              class="flex items-center gap-2 mb-0 text-heading-3 text-n-slate-12"
            >
              {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.TEMPLATES') }}
              <span
                class="px-1.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
                data-testid="messaging-templates-count"
              >
                {{ templateRows.length }}
              </span>
            </h3>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.TEMPLATES_HELP') }}
            </p>
          </div>
          <Button
            slate
            outline
            sm
            class="shrink-0 !w-fit whitespace-nowrap"
            icon="i-lucide-plus"
            :label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.ADD_TEMPLATE')"
            data-testid="messaging-add-template"
            @click="openTemplateDialog"
          />
        </div>
        <p
          v-if="!templateRows.length"
          class="mb-0 text-sm text-n-slate-11"
          data-testid="messaging-templates-empty"
        >
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.TEMPLATES_EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
          <li
            v-for="(row, index) in templateRows"
            :key="`${row.name}|${row.language}`"
            class="flex items-center gap-3 p-3 rounded-lg bg-n-solid-2"
            data-testid="messaging-template-row"
          >
            <div class="flex flex-col min-w-0 gap-1.5 grow">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ row.name }} ({{ row.language }})
              </span>
              <Input
                :model-value="row.purpose"
                size="sm"
                :placeholder="
                  t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.PURPOSE_PLACEHOLDER')
                "
                @update:model-value="
                  value => (current.templates[index].purpose = value)
                "
              />
            </div>
            <span
              v-tooltip.top="
                row.available
                  ? ''
                  : t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.UNAVAILABLE_TEMPLATE')
              "
              class="px-2 py-0.5 text-xs font-medium rounded-md shrink-0"
              :class="
                row.available && row.complete
                  ? 'bg-n-alpha-2 text-n-slate-11'
                  : 'bg-n-amber-3 text-n-amber-11'
              "
            >
              {{ templateStatus(row) }}
            </span>
            <Button
              v-if="row.hasVariables"
              slate
              outline
              sm
              icon="i-lucide-braces"
              :aria-label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.VARIABLES')"
              data-testid="messaging-template-variables"
              @click="openVariablesDialog(index)"
            />
            <Button
              slate
              outline
              sm
              icon="i-lucide-trash-2"
              :aria-label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.REMOVE')"
              @click="removeTemplate(index)"
            />
          </li>
        </ul>
        <p class="mb-0 text-sm text-n-slate-11" data-testid="messaging-paid">
          {{
            paidEnabled
              ? t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.PAID_ON')
              : t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.PAID_OFF')
          }}
          <router-link :to="paidRoute" class="text-n-brand">
            {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.PAID_LINK') }}
          </router-link>
        </p>
      </section>

      <section class="flex flex-col gap-2" data-testid="messaging-limits">
        <h3 class="mb-0 text-heading-3 text-n-slate-12">
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.LIMITS') }}
        </h3>
        <ul class="flex flex-wrap gap-2 p-0 m-0 list-none">
          <li
            v-for="limit in limits"
            :key="limit"
            class="flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            <span class="i-lucide-clock size-3.5 shrink-0" />
            {{ t(`CAPTAIN.ASSISTANTS.FORM.MESSAGING.${limit}`) }}
          </li>
        </ul>
      </section>
    </template>

    <div>
      <Button
        :label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.SAVE')"
        data-testid="messaging-save"
        @click="submit"
      />
    </div>

    <Dialog
      ref="flowDialog"
      :title="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.ADD_FLOW_TITLE')"
      :confirm-button-label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.ADD')"
      :cancel-button-label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.CANCEL')"
      :disable-confirm-button="!draft.resource"
      @confirm="addFlow"
    >
      <div class="flex flex-col gap-4">
        <p v-if="!flowChoices.length" class="mb-0 text-sm text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.NO_FLOWS_LEFT') }}
        </p>
        <ComboBox
          v-else
          v-model="draft.resource"
          :options="flowChoices"
          :placeholder="
            t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.ADD_FLOW_PLACEHOLDER')
          "
          teleport
          data-testid="messaging-flow-choice"
        />
        <Input
          v-model="draft.purpose"
          :label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.PURPOSE')"
          :placeholder="
            t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.PURPOSE_PLACEHOLDER')
          "
          :message="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.PURPOSE_HELP')"
        />
      </div>
    </Dialog>

    <Dialog
      ref="templateDialog"
      :title="
        draft.editIndex === null
          ? t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.ADD_TEMPLATE_TITLE')
          : t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.VARIABLES')
      "
      :confirm-button-label="
        draft.editIndex === null
          ? t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.ADD')
          : t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.SAVE_VARIABLES')
      "
      :cancel-button-label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.CANCEL')"
      :disable-confirm-button="!draftComplete"
      @confirm="addTemplate"
    >
      <div class="flex flex-col gap-4">
        <p
          v-if="draft.editIndex === null && !templateChoices.length"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.NO_TEMPLATES_LEFT') }}
        </p>
        <ComboBox
          v-else-if="draft.editIndex === null"
          v-model="draft.resource"
          :options="templateChoices"
          :placeholder="
            t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.ADD_TEMPLATE_PLACEHOLDER')
          "
          teleport
          data-testid="messaging-template-choice"
          @update:model-value="draft.params = {}"
        />
        <WhatsAppTemplateParser
          v-if="draftTemplate"
          :key="draft.resource || draft.editIndex"
          :template="draftTemplate"
          :model-value="draft.params"
          :variable-options="variableOptions"
          :default-values="CONTACT_DEFAULT_VALUES"
          :preview-values="previewValues"
          @update:model-value="draft.params = $event"
        />
        <Input
          v-if="draft.editIndex === null"
          v-model="draft.purpose"
          :label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.PURPOSE')"
          :placeholder="
            t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.PURPOSE_PLACEHOLDER')
          "
          :message="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.PURPOSE_HELP')"
        />
      </div>
    </Dialog>
  </div>
</template>
