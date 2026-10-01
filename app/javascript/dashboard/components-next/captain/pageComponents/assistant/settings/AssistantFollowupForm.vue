<script setup>
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
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
const { templateOptions } = useApprovedTemplates();

const AFTER_OPTIONS = [10, 15, 30, 45, 60, 120, 240];
const CLOSE_OPTIONS = [30, 60, 120, 240, 480, 1440];

const initialState = {
  inactivityEnabled: true,
  afterMinutes: 30,
  maxNudges: 1,
  closeAfter: 120,
  reengagementEnabled: false,
  template: '',
};

const state = reactive({ ...initialState });

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

const closeOptions = computed(() =>
  withCurrent(CLOSE_OPTIONS, state.closeAfter).map(value => ({
    value,
    label: minutesLabel(value),
  }))
);

const nudgeOptions = computed(() => [
  { value: 0, label: t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.NUDGES_NONE') },
  { value: 1, label: t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.NUDGES_ONE') },
  { value: 2, label: t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.NUDGES_TWO') },
]);

const updateStateFromAssistant = assistant => {
  const settings = assistant?.config?.followup || {};
  Object.assign(state, {
    inactivityEnabled: settings.inactivity_enabled !== false,
    afterMinutes:
      settings.inactivity_after_minutes ?? initialState.afterMinutes,
    maxNudges: settings.max_nudges ?? initialState.maxNudges,
    closeAfter: settings.close_after_minutes ?? initialState.closeAfter,
    reengagementEnabled: settings.reengagement_enabled === true,
    template: templateToValue(settings.reengagement_template),
  });
};

const handleSubmit = () => {
  emit('submit', {
    config: {
      ...props.assistant.config,
      followup: {
        inactivity_enabled: state.inactivityEnabled,
        inactivity_after_minutes: Number(state.afterMinutes),
        max_nudges: Number(state.maxNudges),
        close_after_minutes: Number(state.closeAfter),
        reengagement_enabled: state.reengagementEnabled,
        reengagement_template: templateFromValue(state.template),
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
  <div class="flex flex-col gap-4">
    <SettingsToggleSection
      v-model="state.inactivityEnabled"
      :header="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.TOGGLE')"
      :description="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.TOGGLE_HELP')"
    >
      <div
        v-if="state.inactivityEnabled"
        data-testid="followup-fields"
        class="grid w-full gap-4 border-t border-n-weak px-4 pb-2 pt-4 sm:grid-cols-3"
      >
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.AFTER') }}
          </label>
          <Select
            v-model.number="state.afterMinutes"
            data-testid="followup-after"
            full-width
            :options="afterOptions"
            :aria-label="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.AFTER')"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.NUDGES') }}
          </label>
          <Select
            v-model.number="state.maxNudges"
            data-testid="followup-nudges"
            full-width
            :options="nudgeOptions"
            :aria-label="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.NUDGES')"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.CLOSE') }}
          </label>
          <Select
            v-model.number="state.closeAfter"
            data-testid="followup-close"
            full-width
            :options="closeOptions"
            :aria-label="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.CLOSE')"
          />
        </div>
        <p class="mb-0 text-xs text-n-slate-11 sm:col-span-3">
          {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.HINT') }}
        </p>
      </div>
    </SettingsToggleSection>

    <div
      data-testid="followup-reengagement"
      class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
    >
      <label
        class="flex items-center gap-2 text-sm font-medium text-n-slate-12"
      >
        <Checkbox
          data-testid="followup-reengagement-enabled"
          :model-value="state.reengagementEnabled"
          @update:model-value="state.reengagementEnabled = $event"
        />
        {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.REENGAGEMENT') }}
      </label>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.REENGAGEMENT_HELP') }}
      </p>
      <template v-if="state.reengagementEnabled">
        <p
          v-if="!paidEnabled"
          data-testid="followup-paid-hint"
          class="mb-0 text-xs text-n-slate-11"
        >
          {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.PAID_HINT') }}
        </p>
        <div v-else class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.TEMPLATE') }}
          </label>
          <Select
            v-model="state.template"
            data-testid="followup-template"
            full-width
            :options="templateOptions(state.template)"
            :aria-label="t('CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.TEMPLATE')"
          />
        </div>
      </template>
    </div>

    <div>
      <Button
        data-testid="followup-save"
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleSubmit"
      />
    </div>
  </div>
</template>
