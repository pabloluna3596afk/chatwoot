<script setup>
import AssistantNameText from 'dashboard/components-next/AssistantNameText.vue';
import { useAssistantName } from 'dashboard/composables/useAssistantName';
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAccount } from 'dashboard/composables/useAccount';
import { isWhatsAppComplete } from '@chatwoot/utils';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import DurationSelect from './DurationSelect.vue';
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
const { nameRich, nameText } = useAssistantName(() => props.assistant);

const { isCloudFeatureEnabled } = useAccount();
const isCaptainV2Enabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN_V2)
);
const { templateOptions, templateEntry, templateInboxId, disallowedTemplate } =
  useApprovedTemplates(props.assistant?.id);
const { variableOptions, defaultValues, previewValues } = useTemplateVariables({
  appointment: false,
});

const AFTER_OPTIONS = [5, 10, 15, 30, 45, 60, 120, 240];
const initialState = {
  completionSignalEnabled: false,
  completionGraceMinutes: 5,
  sendInactivityResolutionMessage: true,
  resolutionMessage: '',
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
const remindersEnabled = computed(
  () => state.inactivityEnabled && state.maxNudges > 0
);
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
    completionSignalEnabled:
      assistant?.config?.completion_signal_enabled ?? false,
    completionGraceMinutes: assistant?.config?.completion_grace_minutes ?? 5,
    sendInactivityResolutionMessage:
      assistant?.config?.send_inactivity_resolution_message ?? true,
    resolutionMessage: assistant?.config?.resolution_message,
    autoResolveMode: assistant?.config?.auto_resolve_mode ?? 'evaluated',
    inactivityThresholdMinutes: isCaptainV2Enabled.value
      ? (assistant?.config?.auto_resolve_after ??
        initialState.inactivityThresholdMinutes)
      : initialState.inactivityThresholdMinutes,
    inactivityEnabled: settings.inactivity_enabled !== false,
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
  auto_resolve_mode: state.autoResolveMode,
  auto_resolve_after: state.inactivityThresholdMinutes,
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
    state.maxNudges > 0 &&
    state.autoResolveMode !== 'disabled' &&
    Number(state.afterMinutes) >= Number(state.inactivityThresholdMinutes)
);

const autoResolveOptions = computed(() => [
  {
    value: 'evaluated',
    label: nameText(
      'CAPTAIN.ASSISTANTS.FORM.INACTIVITY_RESOLUTION.MODES.EVALUATED.LABEL'
    ),
  },
  {
    value: 'legacy',
    label: t(
      'CAPTAIN.ASSISTANTS.FORM.INACTIVITY_RESOLUTION.MODES.LEGACY.LABEL'
    ),
  },
  {
    value: 'disabled',
    label: t(
      'CAPTAIN.ASSISTANTS.FORM.INACTIVITY_RESOLUTION.MODES.DISABLED.LABEL'
    ),
  },
]);

const graceOptions = computed(() =>
  [5, 10, 15].map(value => ({
    value,
    label: t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.MINUTES', { count: value }),
  }))
);

const timingError = computed(() =>
  afterError.value
    ? t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.AFTER_ERROR', {
        interval: state.afterMinutes,
        minutes: state.inactivityThresholdMinutes,
      })
    : ''
);
const inactivityThresholdError = computed(() => {
  if (!isCaptainV2Enabled.value || state.autoResolveMode === 'disabled')
    return '';
  const value = state.inactivityThresholdMinutes;
  if (value === null || value === undefined || value === '')
    return t('GENERAL.VALIDATION.REQUIRED');
  if (!Number.isInteger(value)) return t('GENERAL.VALIDATION.INTEGER');
  if (value < 5) return t('GENERAL.VALIDATION.MIN_VALUE', { min: 5 });
  if (value > 1440) return t('GENERAL.VALIDATION.MAX_VALUE', { max: 1440 });
  return '';
});

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
  if (
    !templateComplete.value ||
    afterError.value ||
    inactivityThresholdError.value
  )
    return;

  emit('submit', {
    config: {
      ...(isCaptainV2Enabled.value
        ? {
            auto_resolve_mode: state.autoResolveMode,
            auto_resolve_after: state.inactivityThresholdMinutes,
            completion_signal_enabled: state.completionSignalEnabled,
            completion_grace_minutes: state.completionGraceMinutes,
            send_inactivity_resolution_message:
              state.sendInactivityResolutionMessage,
          }
        : {}),
      resolution_message: state.resolutionMessage,
      followup: {
        ...props.assistant.config?.followup,
        inactivity_enabled: state.inactivityEnabled,
        inactivity_after_minutes: Number(state.afterMinutes),
        max_nudges: Number(state.maxNudges),
        close_after_minutes:
          props.assistant.config?.followup?.close_after_minutes ?? 120,
        reengagement_enabled: state.reengagementEnabled,
        reengagement_template: state.template
          ? {
              ...(templateToValue(
                props.assistant.config?.followup?.reengagement_template
              ) === state.template
                ? props.assistant.config.followup.reengagement_template
                : {}),
              ...templateFromValue(state.template, state.params),
            }
          : null,
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
    <SettingsToggleSection
      v-if="isCaptainV2Enabled"
      hide-toggle
      :header="t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.TITLE')"
      :description="nameRich('CAPTAIN.ASSISTANTS.FORM.CLOSURE.HELP')"
    >
      <div class="flex w-full flex-col gap-4 px-4 pt-3">
        <ComboBox
          v-model="state.autoResolveMode"
          data-testid="closure-mode"
          :options="autoResolveOptions"
          :allow-deselect="false"
          :aria-label="
            t('CAPTAIN.ASSISTANTS.FORM.INACTIVITY_RESOLUTION.MODE_LABEL')
          "
        />
      </div>
    </SettingsToggleSection>
    <section class="flex flex-col gap-4" data-testid="no-reply-section">
      <h3 class="m-0 text-heading-3 text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.NO_REPLY') }}
      </h3>
      <div
        v-if="isCaptainV2Enabled && state.autoResolveMode !== 'disabled'"
        class="flex flex-col gap-2"
      >
        <span class="text-body-main font-medium text-n-slate-12">{{
          t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.INACTIVITY')
        }}</span>
        <DurationSelect
          v-model="state.inactivityThresholdMinutes"
          :error="inactivityThresholdError || timingError"
          :hours-aria-label="
            t(
              'CAPTAIN.ASSISTANTS.FORM.INACTIVITY_RESOLUTION.DURATION_HOURS_ARIA_LABEL'
            )
          "
          :minutes-aria-label="
            t(
              'CAPTAIN.ASSISTANTS.FORM.INACTIVITY_RESOLUTION.DURATION_MINUTES_ARIA_LABEL'
            )
          "
        />
        <p class="m-0 text-xs text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.INACTIVITY_HELP') }}
        </p>
        <p
          v-if="timingError || inactivityThresholdError"
          data-testid="closure-timing-error"
          role="alert"
          class="m-0 text-xs text-n-ruby-9"
        >
          {{ inactivityThresholdError || timingError }}
        </p>
        <p
          v-if="state.inactivityThresholdMinutes === 5"
          data-testid="five-minute-hint"
          class="m-0 text-xs text-n-slate-11"
        >
          {{ t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.FIVE_MINUTES') }}
        </p>
        <Button
          v-if="state.inactivityThresholdMinutes === 5 && remindersEnabled"
          intent="tertiary"
          data-testid="disable-reminders"
          :label="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.DISABLE')"
          @click="setInactivityEnabled(false)"
        />
      </div>
      <SettingsToggleSection
        data-testid="followup-reminders"
        :model-value="remindersEnabled"
        :header="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.TOGGLE')"
        :description="nameRich('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.TOGGLE_HELP')"
        @update:model-value="setInactivityEnabled"
      >
        <div
          v-if="remindersEnabled"
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
            <p
              v-if="afterError"
              data-testid="followup-after-error"
              role="alert"
              class="m-0 text-xs text-n-ruby-9"
            >
              {{ timingError }}
            </p>
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
            {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.INTERVAL_HELP') }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11 sm:col-span-2">
            <AssistantNameText
              :text="nameRich('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.HINT')"
            />
          </p>
        </div>
      </SettingsToggleSection>

      <ClosureSummary :config="closureConfig" />
      <SettingsToggleSection
        v-if="isCaptainV2Enabled"
        v-model="state.sendInactivityResolutionMessage"
        :header="
          t(
            'CAPTAIN.ASSISTANTS.FORM.INACTIVITY_RESOLUTION.RESOLUTION_MESSAGE.TITLE'
          )
        "
        :description="
          t(
            'CAPTAIN.ASSISTANTS.FORM.INACTIVITY_RESOLUTION.RESOLUTION_MESSAGE.DESCRIPTION'
          )
        "
      >
        <template v-if="state.sendInactivityResolutionMessage" #editor>
          <Editor
            v-model="state.resolutionMessage"
            :placeholder="
              t('CAPTAIN.ASSISTANTS.FORM.RESOLUTION_MESSAGE.PLACEHOLDER')
            "
            class="z-0 [&_.editor-wrapper]:!min-h-32 [&_.editor-wrapper]:!border-0 [&_.editor-wrapper]:!bg-transparent [&_.editor-wrapper]:!p-0"
          />
        </template>
      </SettingsToggleSection>
      <Editor
        v-if="!isCaptainV2Enabled"
        v-model="state.resolutionMessage"
        :label="t('CAPTAIN.ASSISTANTS.FORM.RESOLUTION_MESSAGE.LABEL')"
        :placeholder="
          t('CAPTAIN.ASSISTANTS.FORM.RESOLUTION_MESSAGE.PLACEHOLDER')
        "
      />
    </section>
    <section
      v-if="isCaptainV2Enabled && state.autoResolveMode === 'evaluated'"
      class="flex flex-col gap-4"
      data-testid="completion-section"
    >
      <h3 class="m-0 text-heading-3 text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.CONVERSATION_ENDS') }}
      </h3>
      <SettingsToggleSection
        v-if="state.autoResolveMode === 'evaluated'"
        v-model="state.completionSignalEnabled"
        data-testid="completion-signal"
        :header="t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.DETECT')"
        :description="nameRich('CAPTAIN.ASSISTANTS.FORM.CLOSURE.DETECT_HELP')"
      >
        <div
          v-if="state.completionSignalEnabled"
          class="flex w-full flex-col gap-2 px-4 pt-3"
        >
          <span class="text-body-main font-medium text-n-slate-12">{{
            t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.GRACE')
          }}</span>
          <ComboBox
            v-model="state.completionGraceMinutes"
            data-testid="completion-grace"
            :options="graceOptions"
            :allow-deselect="false"
            :aria-label="t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.GRACE')"
          />
        </div>
      </SettingsToggleSection>
    </section>
    <section class="flex flex-col gap-4" data-testid="after-closing-section">
      <h3 class="m-0 text-heading-3 text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.CLOSURE.AFTER_CLOSING') }}
      </h3>
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
    </section>
    <div>
      <Button
        data-testid="followup-save"
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleSubmit"
      />
    </div>
  </div>
</template>
