<script setup>
import AssistantNameText from 'dashboard/components-next/AssistantNameText.vue';
import { useAssistantName } from 'dashboard/composables/useAssistantName';
import { computed, reactive, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { I18nT, useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAccount } from 'dashboard/composables/useAccount';
import { isWhatsAppComplete } from '@chatwoot/utils';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import ClosureSummary from './ClosureSummary.vue';
import { useTemplateVariables } from './useTemplateVariables';
import {
  useApprovedTemplates,
  templateFromValue,
  templateToValue,
} from './useApprovedTemplates';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();
const { nameRich } = useAssistantName(() => props.assistant);

const route = useRoute();
const { isCloudFeatureEnabled } = useAccount();
const isCaptainV2Enabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN_V2)
);
const { templateOptions, templateEntry, templateInboxId, disallowedTemplate } =
  useApprovedTemplates(props.assistant?.id);
const { variableOptions, defaultValues, previewValues } = useTemplateVariables({
  appointment: false,
});

const AFTER_OPTIONS = [10, 15, 30, 45, 60, 120, 240];
const initialState = {
  autoResolveMode: 'evaluated',
  inactivityThresholdMinutes: 60,
  inactivityEnabled: true,
  afterMinutes: 30,
  maxNudges: 1,
  reengagementEnabled: false,
  template: '',
  params: {},
};

const state = reactive({ ...initialState, params: {} });
const showErrors = ref(false);

// The one "paid templates" switch of the assistant lives in its own page.
const paidEnabled = computed(
  () => props.assistant?.config?.allow_paid_templates === true
);

const minutesLabel = minutes =>
  minutes % 60 === 0
    ? t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.HOURS', { count: minutes / 60 })
    : t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.MINUTES', { count: minutes });

const withCurrent = (options, current) =>
  options.includes(current)
    ? options
    : [...options, current].sort((a, b) => a - b);

const afterOptions = computed(() =>
  withCurrent(AFTER_OPTIONS, state.afterMinutes).map(value => ({
    value,
    label: minutesLabel(value),
  }))
);

const nudgeOptions = computed(() => [
  { value: 1, label: t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.NUDGES_ONE') },
  { value: 2, label: t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.NUDGES_TWO') },
]);

const updateStateFromAssistant = assistant => {
  const settings = assistant?.config?.followup || {};
  const savedMaxNudges = settings.max_nudges ?? initialState.maxNudges;
  Object.assign(state, {
    autoResolveMode: assistant?.config?.auto_resolve_mode ?? 'evaluated',
    inactivityThresholdMinutes: isCaptainV2Enabled.value
      ? (assistant?.config?.auto_resolve_after ??
        initialState.inactivityThresholdMinutes)
      : initialState.inactivityThresholdMinutes,
    inactivityEnabled:
      settings.inactivity_enabled !== false && savedMaxNudges > 0,
    afterMinutes:
      settings.inactivity_after_minutes ?? initialState.afterMinutes,
    maxNudges: savedMaxNudges,
    reengagementEnabled: settings.reengagement_enabled === true,
    template: templateToValue(settings.reengagement_template),
    params: settings.reengagement_template?.processed_params || {},
  });
};

// A template with a variable left empty cannot be saved.
const templateComplete = computed(
  () =>
    !state.reengagementEnabled ||
    !state.template ||
    !templateEntry(state.template) ||
    isWhatsAppComplete(templateEntry(state.template), state.params)
);

const closureConfig = computed(() => ({
  ...props.assistant.config,
  followup: {
    ...props.assistant.config?.followup,
    inactivity_enabled: state.inactivityEnabled,
    inactivity_after_minutes: state.afterMinutes,
    max_nudges: state.maxNudges,
  },
}));

const afterError = computed(
  () =>
    state.inactivityEnabled &&
    state.autoResolveMode !== 'disabled' &&
    Number(state.afterMinutes) >= Number(state.inactivityThresholdMinutes)
);

const selectTemplate = value => {
  state.template = value;
  state.params = {};
};

const setInactivityEnabled = enabled => {
  state.inactivityEnabled = enabled;
  if (enabled && state.maxNudges === 0) state.maxNudges = 1;
};

const handleSubmit = () => {
  showErrors.value = true;
  if (!templateComplete.value || afterError.value) return;

  emit('submit', {
    config: {
      followup: {
        inactivity_enabled: state.inactivityEnabled,
        inactivity_after_minutes: Number(state.afterMinutes),
        max_nudges: Number(state.maxNudges),
        close_after_minutes:
          props.assistant.config?.followup?.close_after_minutes ?? 120,
        reengagement_enabled: state.reengagementEnabled,
        reengagement_template: templateFromValue(state.template, state.params),
      },
    },
  });
};

watch(
  () => props.assistant,
  assistant => {
    if (assistant) updateStateFromAssistant(assistant);
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <ClosureSummary v-if="isCaptainV2Enabled" :config="closureConfig" />
    <I18nT
      keypath="CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.GOODBYE_SENTENCE"
      tag="p"
      class="mb-0 text-body-main text-n-slate-11"
    >
      <template #link>
        <RouterLink
          :to="{
            name: 'captain_assistants_settings_system_index',
            params: route.params,
          }"
          class="text-n-brand underline"
        >
          {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.GOODBYE_LINK') }}
        </RouterLink>
      </template>
    </I18nT>

    <SettingsToggleSection
      :model-value="state.inactivityEnabled"
      :header="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.TOGGLE')"
      :description="nameRich('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.TOGGLE_HELP')"
      @update:model-value="setInactivityEnabled"
    >
      <div
        v-if="state.inactivityEnabled"
        data-testid="followup-fields"
        class="grid w-full gap-4 border-t border-n-weak px-4 pb-2 pt-4 sm:grid-cols-2"
      >
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">{{
            t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.AFTER')
          }}</label>
          <ComboBox
            v-model.number="state.afterMinutes"
            data-testid="followup-after"
            teleport
            :allow-deselect="false"
            :options="afterOptions"
            :aria-label="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.AFTER')"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">{{
            t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.NUDGES')
          }}</label>
          <ComboBox
            v-model.number="state.maxNudges"
            data-testid="followup-nudges"
            teleport
            :allow-deselect="false"
            :options="nudgeOptions"
            :aria-label="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.NUDGES')"
          />
        </div>
        <p class="mb-0 text-xs text-n-slate-11 sm:col-span-2">
          <AssistantNameText
            :text="nameRich('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.HINT')"
          />
        </p>
      </div>
      <p
        v-if="showErrors && afterError"
        data-testid="followup-after-error"
        class="px-4 pb-3 text-xs text-n-ruby-9"
      >
        {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.AFTER_ERROR') }}
      </p>
    </SettingsToggleSection>

    <SettingsToggleSection
      v-model="state.reengagementEnabled"
      data-testid="followup-reengagement"
      :header="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.REENGAGEMENT')"
      :description="
        nameRich('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.REENGAGEMENT_HELP')
      "
    >
      <div
        v-if="state.reengagementEnabled"
        class="flex w-full flex-col gap-3 px-4 pb-3 pt-3"
      >
        <p
          v-if="!paidEnabled"
          data-testid="followup-paid-hint"
          class="mb-0 text-xs text-n-slate-11"
        >
          {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.PAID_HINT') }}
        </p>
        <div v-else class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">{{
            t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.TEMPLATE')
          }}</label>
          <ComboBox
            :model-value="state.template"
            data-testid="followup-template"
            teleport
            :allow-deselect="false"
            :options="templateOptions(state.template)"
            :aria-label="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.TEMPLATE')"
            @update:model-value="selectTemplate"
          />
          <p
            v-if="disallowedTemplate(state.template)"
            role="alert"
            class="text-sm text-n-amber-11"
          >
            {{ t('CAPTAIN.ASSISTANTS.FOLLOWUP.MARKETING_NOT_ALLOWED') }}
          </p>
          <WhatsAppTemplateParser
            v-if="state.template && templateEntry(state.template)"
            :key="state.template"
            variable-surface="captain"
            :template="templateEntry(state.template)"
            :media-inbox-id="templateInboxId(state.template)"
            :model-value="state.params"
            :variable-options="variableOptions"
            :default-values="defaultValues"
            :preview-values="previewValues"
            @update:model-value="state.params = $event"
          />
          <p
            v-if="showErrors && !templateComplete"
            data-testid="followup-template-error"
            class="mb-0 text-xs text-n-ruby-9"
          >
            {{ t('CAPTAIN.ASSISTANTS.FORM.TEMPLATE_VARIABLES.ERROR') }}
          </p>
        </div>
      </div>
    </SettingsToggleSection>

    <div>
      <Button
        data-testid="followup-save"
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleSubmit"
      />
    </div>
  </div>
</template>
