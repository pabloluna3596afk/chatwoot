<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import {
  helpers,
  integer,
  maxValue,
  minLength,
  minValue,
  required,
} from '@vuelidate/validators';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAccount } from 'dashboard/composables/useAccount';

import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import HandoffRoutingRow from './HandoffRoutingRow.vue';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();
const { isCloudFeatureEnabled } = useAccount();
const store = useStore();
const teams = useMapGetter('teams/getTeams');
const teamsLoading = ref(true);
const teamsError = ref(false);
const submitted = ref(false);
const routingKinds = ['new', 'reopened'];
const priorityModes = ['off', 'on_signal', 'always'];
onMounted(async () => {
  try {
    await store.dispatch('teams/get');
  } catch {
    teamsError.value = true;
  } finally {
    teamsLoading.value = false;
  }
});

const isCaptainV2Enabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN_V2)
);

const DEFAULT_MAX_REPLIES = 20;
const MAX_REPLIES_LIMIT = 1000;

const initialState = {
  handoffMessage: '',
  resolutionMessage: '',
  instructions: '',
  sendInactivityResolutionMessage: true,
  maxReplies: DEFAULT_MAX_REPLIES,
  handoffRouting: {},
  handoffPriority: 'off',
};

const state = reactive({ ...initialState });

const requiredMessage = helpers.withMessage(
  () => t('GENERAL.VALIDATION.REQUIRED'),
  required
);
const minLengthMessage = helpers.withMessage(
  ({ $params }) => t('GENERAL.VALIDATION.MIN_LENGTH', { min: $params.min }),
  minLength(1)
);
const validationRules = {
  handoffMessage: { minLength: minLengthMessage },
  resolutionMessage: { minLength: minLengthMessage },
  instructions: { minLength: minLengthMessage },
  maxReplies: {
    required: requiredMessage,
    integer: helpers.withMessage(
      () => t('GENERAL.VALIDATION.INTEGER'),
      integer
    ),
    minValue: helpers.withMessage(
      ({ $params }) => t('GENERAL.VALIDATION.MIN_VALUE', { min: $params.min }),
      minValue(0)
    ),
    maxValue: helpers.withMessage(
      ({ $params }) => t('GENERAL.VALIDATION.MAX_VALUE', { max: $params.max }),
      maxValue(MAX_REPLIES_LIMIT)
    ),
  },
};

const v$ = useVuelidate(validationRules, state);

const getErrorMessage = field => {
  return v$.value[field].$error ? v$.value[field].$errors[0].$message : '';
};

const formErrors = computed(() => ({
  handoffMessage: getErrorMessage('handoffMessage'),
  resolutionMessage: getErrorMessage('resolutionMessage'),
  instructions: getErrorMessage('instructions'),
  maxReplies: getErrorMessage('maxReplies'),
}));

const updateStateFromAssistant = assistant => {
  const { config = {} } = assistant;
  state.handoffMessage = config.handoff_message;
  state.resolutionMessage = config.resolution_message;
  state.instructions = config.instructions;
  state.sendInactivityResolutionMessage =
    config.send_inactivity_resolution_message ?? true;
  state.maxReplies = config.max_replies_per_conversation ?? DEFAULT_MAX_REPLIES;
  state.handoffRouting = Object.fromEntries(
    routingKinds.map(kind => [
      kind,
      { mode: 'inbox', team_id: null, ...config.handoff_routing?.[kind] },
    ])
  );
  state.handoffPriority = config.handoff_priority ?? 'off';
  submitted.value = false;
};

const fieldsToValidate = () => {
  if (!isCaptainV2Enabled.value) {
    return [
      'handoffMessage',
      'resolutionMessage',
      'instructions',
      'maxReplies',
    ];
  }

  const fields = ['handoffMessage', 'maxReplies'];
  if (state.sendInactivityResolutionMessage) fields.push('resolutionMessage');
  return fields;
};

const handleSystemMessagesUpdate = async () => {
  submitted.value = true;
  const isValid = await Promise.all(
    fieldsToValidate().map(field => v$.value[field].$validate())
  ).then(results => results.every(Boolean));
  if (!isValid) return;
  if (
    routingKinds.some(kind => {
      const row = state.handoffRouting[kind];
      return (
        row.mode === 'team' &&
        (teamsLoading.value ||
          teamsError.value ||
          !teams.value.some(team => team.id === row.team_id))
      );
    })
  )
    return;

  const payload = {
    config: {
      handoff_message: state.handoffMessage,
      max_replies_per_conversation: Number(state.maxReplies),
      handoff_routing: Object.fromEntries(
        routingKinds.map(kind => [kind, { ...state.handoffRouting[kind] }])
      ),
      handoff_priority: state.handoffPriority,
    },
  };

  if (isCaptainV2Enabled.value) {
    Object.assign(payload.config, {
      send_inactivity_resolution_message: state.sendInactivityResolutionMessage,
      resolution_message: state.resolutionMessage,
    });
  } else {
    payload.config.resolution_message = state.resolutionMessage;
    payload.config.instructions = state.instructions;
  }

  emit('submit', payload);
};

watch(
  () => props.assistant,
  newAssistant => {
    if (newAssistant) updateStateFromAssistant(newAssistant);
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-6">
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
          :message="formErrors.resolutionMessage"
          :message-type="formErrors.resolutionMessage ? 'error' : 'info'"
          class="z-0 [&_.editor-wrapper]:!min-h-32 [&_.editor-wrapper]:!border-0 [&_.editor-wrapper]:!bg-transparent [&_.editor-wrapper]:!p-0"
        />
      </template>
    </SettingsToggleSection>
    <SettingsToggleSection
      hide-toggle
      :header="t('CAPTAIN.ASSISTANTS.FORM.HANDOFF_MESSAGE.LABEL')"
    >
      <template #editor>
        <Editor
          v-model="state.handoffMessage"
          :placeholder="
            t('CAPTAIN.ASSISTANTS.FORM.HANDOFF_MESSAGE.PLACEHOLDER')
          "
          :message="formErrors.handoffMessage"
          :message-type="formErrors.handoffMessage ? 'error' : 'info'"
          class="z-0 [&_.editor-wrapper]:!min-h-32 [&_.editor-wrapper]:!border-0 [&_.editor-wrapper]:!bg-transparent [&_.editor-wrapper]:!p-0"
        />
        <p class="px-4 pb-3 text-xs text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANTS.FORM.HANDOFF_MESSAGE.OUTSIDE_HOURS_HELP') }}
        </p>
      </template>
    </SettingsToggleSection>

    <SettingsToggleSection
      hide-toggle
      :header="t('CAPTAIN.ASSISTANTS.FORM.HANDOFF_ROUTING.TITLE')"
      :description="t('CAPTAIN.ASSISTANTS.FORM.HANDOFF_ROUTING.DESCRIPTION')"
    >
      <template #editor>
        <div class="flex flex-col gap-4">
          <HandoffRoutingRow
            v-for="kind in routingKinds"
            :key="kind"
            v-model="state.handoffRouting[kind]"
            :kind="kind"
            :teams="teams"
            :eligible-team-ids="assistant.eligible_team_ids ?? []"
            :loading="teamsLoading"
            :load-error="teamsError"
            :submitted="submitted"
          />
        </div>
      </template>
    </SettingsToggleSection>

    <SettingsToggleSection
      hide-toggle
      :header="t('CAPTAIN.ASSISTANTS.FORM.HANDOFF_PRIORITY.TITLE')"
    >
      <template #editor>
        <div
          role="radiogroup"
          :aria-label="t('CAPTAIN.ASSISTANTS.FORM.HANDOFF_PRIORITY.TITLE')"
          class="flex flex-col gap-2"
        >
          <label
            v-for="mode in priorityModes"
            :key="mode"
            class="inline-flex cursor-pointer items-center gap-2 text-sm text-n-slate-12"
          >
            <input
              v-model="state.handoffPriority"
              type="radio"
              name="handoff-priority"
              :value="mode"
              class="size-4 accent-n-blue-9 text-n-blue-9"
            />
            {{
              t(
                `CAPTAIN.ASSISTANTS.FORM.HANDOFF_PRIORITY.${mode.toUpperCase()}`
              )
            }}
          </label>
          <p class="m-0 text-xs text-n-slate-11">
            {{ t('CAPTAIN.ASSISTANTS.FORM.HANDOFF_PRIORITY.HELP') }}
          </p>
        </div>
      </template>
    </SettingsToggleSection>

    <SettingsToggleSection
      hide-toggle
      :header="t('CAPTAIN.ASSISTANTS.FORM.MAX_REPLIES.TITLE')"
      :description="t('CAPTAIN.ASSISTANTS.FORM.MAX_REPLIES.DESCRIPTION')"
    >
      <div class="flex w-full flex-col gap-2 px-4 pb-1 pt-3">
        <Input
          v-model="state.maxReplies"
          type="number"
          min="0"
          :max="MAX_REPLIES_LIMIT"
          :label="t('CAPTAIN.ASSISTANTS.FORM.MAX_REPLIES.LABEL')"
          :message="
            formErrors.maxReplies ||
            t('CAPTAIN.ASSISTANTS.FORM.MAX_REPLIES.HINT')
          "
          :message-type="formErrors.maxReplies ? 'error' : 'info'"
          class="max-w-xs"
        />
      </div>
    </SettingsToggleSection>

    <Editor
      v-if="!isCaptainV2Enabled"
      v-model="state.resolutionMessage"
      :label="t('CAPTAIN.ASSISTANTS.FORM.RESOLUTION_MESSAGE.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.RESOLUTION_MESSAGE.PLACEHOLDER')"
      :message="formErrors.resolutionMessage"
      :message-type="formErrors.resolutionMessage ? 'error' : 'info'"
      class="z-0"
    />

    <Editor
      v-if="!isCaptainV2Enabled"
      v-model="state.instructions"
      :label="t('CAPTAIN.ASSISTANTS.FORM.INSTRUCTIONS.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.INSTRUCTIONS.PLACEHOLDER')"
      :message="formErrors.instructions"
      :max-length="20000"
      :message-type="formErrors.instructions ? 'error' : 'info'"
      class="z-0"
    />

    <div>
      <Button
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleSystemMessagesUpdate"
      />
    </div>
  </div>
</template>
