<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import { isSupportedForCaptain, templateKey } from './captainTemplates';

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
const captainInboxes = useMapGetter('captainInboxes/getRecords');
const inboxes = useMapGetter('inboxes/getInboxes');

const enabled = ref(false);
// { [inboxId]: { flows: [{ flow_id, purpose }], templates: [{ name, language, purpose }] } }
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
const current = computed(
  () => permissions[selectedInboxId.value] || { flows: [], templates: [] }
);
const paidEnabled = computed(
  () => props.assistant?.config?.allow_paid_templates === true
);

const hydrate = () => {
  const saved = props.assistant?.config?.messaging;
  enabled.value = saved?.enabled === true;
  Object.keys(permissions).forEach(key => delete permissions[key]);
  (saved?.inboxes || []).forEach(entry => {
    permissions[entry.inbox_id] = {
      flows: (entry.flows || []).map(flow => ({ ...flow })),
      templates: (entry.templates || []).map(template => ({ ...template })),
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

const ensureEntry = inboxId => {
  if (!permissions[inboxId])
    permissions[inboxId] = { flows: [], templates: [] };
  return permissions[inboxId];
};

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
const draft = reactive({ resource: '', purpose: '' });
const resetDraft = () => {
  draft.resource = '';
  draft.purpose = '';
};
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
  if (!draft.resource) return;
  const [name, language] = draft.resource.split('|');
  ensureEntry(selectedInboxId.value).templates.push({
    name,
    language,
    purpose: draft.purpose.trim(),
  });
  templateDialog.value.close();
};
const removeFlow = index => current.value.flows.splice(index, 1);
const removeTemplate = index => current.value.templates.splice(index, 1);

const submit = () => {
  const entries = Object.entries(permissions)
    .map(([inboxId, entry]) => ({
      inbox_id: Number(inboxId),
      flows: entry.flows,
      templates: entry.templates,
    }))
    .filter(entry => entry.flows.length || entry.templates.length);
  emit('submit', {
    config: {
      ...props.assistant.config,
      messaging: { enabled: enabled.value, inboxes: entries },
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
    <SettingsToggleSection
      v-model="enabled"
      :header="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.TOGGLE')"
      :description="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.TOGGLE_HELP')"
    />

    <p v-if="!whatsappInboxes.length" class="mb-0 text-sm text-n-slate-11">
      {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.NO_INBOXES') }}
    </p>

    <template v-else>
      <div class="flex flex-col gap-1 max-w-sm">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.INBOX') }}
        </span>
        <ComboBox
          v-model="selectedInboxId"
          :options="inboxOptions"
          :allow-deselect="false"
          :placeholder="
            t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.INBOX_PLACEHOLDER')
          "
          teleport
          data-testid="messaging-inbox"
        />
      </div>

      <section class="flex flex-col gap-3" data-testid="messaging-flows">
        <div class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1">
            <h3 class="mb-0 text-heading-3 text-n-slate-12">
              {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.FLOWS') }}
            </h3>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.FLOWS_HELP') }}
            </p>
          </div>
          <Button
            slate
            outline
            sm
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
            class="flex items-center gap-3 p-3 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
            data-testid="messaging-flow-row"
          >
            <div class="flex flex-col min-w-0 gap-0.5 grow">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ row.name }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ row.purpose || '—' }}
              </span>
            </div>
            <span
              class="text-xs shrink-0"
              :class="row.available ? 'text-n-teal-11' : 'text-n-amber-11'"
            >
              {{
                row.available
                  ? t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.STATE_PUBLISHED')
                  : t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.UNAVAILABLE')
              }}
            </span>
            <Button
              ghost
              slate
              sm
              icon="i-lucide-trash-2"
              :aria-label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.REMOVE')"
              @click="removeFlow(index)"
            />
          </li>
        </ul>
      </section>

      <section class="flex flex-col gap-3" data-testid="messaging-templates">
        <div class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1">
            <h3 class="mb-0 text-heading-3 text-n-slate-12">
              {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.TEMPLATES') }}
            </h3>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.TEMPLATES_HELP') }}
            </p>
          </div>
          <Button
            slate
            outline
            sm
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
            class="flex items-center gap-3 p-3 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
            data-testid="messaging-template-row"
          >
            <div class="flex flex-col min-w-0 gap-0.5 grow">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ row.name }} ({{ row.language }})
              </span>
              <span class="text-xs text-n-slate-11">
                {{ row.purpose || '—' }}
              </span>
            </div>
            <span
              class="text-xs shrink-0"
              :class="row.available ? 'text-n-slate-11' : 'text-n-amber-11'"
            >
              {{
                row.available
                  ? row.category
                  : t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.UNAVAILABLE')
              }}
            </span>
            <Button
              ghost
              slate
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

      <section
        class="flex flex-col gap-1 p-3 rounded-xl bg-n-alpha-2"
        data-testid="messaging-limits"
      >
        <h3 class="mb-1 text-heading-3 text-n-slate-12">
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.LIMITS') }}
        </h3>
        <span class="text-sm text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.LIMIT_FLOW_GAP') }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.LIMIT_FLOWS') }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.LIMIT_TEMPLATES') }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.LIMIT_PENDING') }}
        </span>
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
      :title="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.ADD_TEMPLATE_TITLE')"
      :confirm-button-label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.ADD')"
      :cancel-button-label="t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.CANCEL')"
      :disable-confirm-button="!draft.resource"
      @confirm="addTemplate"
    >
      <div class="flex flex-col gap-4">
        <p v-if="!templateChoices.length" class="mb-0 text-sm text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.NO_TEMPLATES_LEFT') }}
        </p>
        <ComboBox
          v-else
          v-model="draft.resource"
          :options="templateChoices"
          :placeholder="
            t('CAPTAIN.ASSISTANTS.FORM.MESSAGING.ADD_TEMPLATE_PLACEHOLDER')
          "
          teleport
          data-testid="messaging-template-choice"
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
  </div>
</template>
