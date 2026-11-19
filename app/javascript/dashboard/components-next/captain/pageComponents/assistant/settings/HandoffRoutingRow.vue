<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import { useAssistantName } from 'dashboard/composables/useAssistantName';

const props = defineProps({
  kind: { type: String, required: true },
  teams: { type: Array, required: true },
  eligibleTeamIds: { type: Array, required: true },
  loading: { type: Boolean, default: false },
  loadError: { type: Boolean, default: false },
  submitted: { type: Boolean, default: false },
  assistant: { type: Object, default: null },
});
const row = defineModel({ type: Object, required: true });
const { t } = useI18n();
const { nameRich } = useAssistantName(() => props.assistant);
const key = 'CAPTAIN.ASSISTANTS.FORM.HANDOFF_ROUTING';
const modes = ['inbox', 'last_agent', 'team', 'ai_team'];
const labelKey = mode =>
  mode === 'last_agent'
    ? `LAST_AGENT_${props.kind.toUpperCase()}`
    : mode.toUpperCase();
const noTeams = computed(
  () => !props.loading && !props.loadError && !props.teams.length
);
const options = computed(() =>
  modes.map(mode => ({
    value: mode,
    label: nameRich(`${key}.MODES.${labelKey(mode)}.LABEL`),
    disabled: noTeams.value && ['team', 'ai_team'].includes(mode),
  }))
);
const teamOptions = computed(() =>
  props.teams.map(team => ({ value: team.id, label: team.name }))
);
const deleted = computed(
  () =>
    !props.loading &&
    !props.loadError &&
    row.value.mode === 'team' &&
    row.value.team_id != null &&
    !props.teams.some(team => team.id === row.value.team_id)
);
const error = computed(() => {
  if (deleted.value) return t(`${key}.TEAM_DELETED_HELP`);
  if (props.submitted && row.value.mode === 'team' && !row.value.team_id)
    return t(`${key}.TEAM_REQUIRED`);
  return '';
});
const teamPlaceholder = computed(() => {
  if (props.loading) return t(`${key}.TEAMS_LOADING`);
  if (props.loadError) return t(`${key}.TEAMS_ERROR`);
  return t(`${key}.TEAM_PLACEHOLDER`);
});
const warning = computed(() => {
  if (props.loading || props.loadError || deleted.value) return '';
  if (
    row.value.mode === 'team' &&
    row.value.team_id &&
    !props.eligibleTeamIds.includes(row.value.team_id)
  )
    return t(`${key}.TEAM_NO_MEMBERS`);
  if (row.value.mode === 'ai_team' && !props.eligibleTeamIds.length)
    return t(`${key}.AI_TEAM_NONE`);
  return '';
});
const updateMode = mode => {
  row.value = { mode, team_id: null };
};
</script>

<template>
  <div
    class="grid grid-cols-1 items-start gap-2 sm:grid-cols-[11rem_1fr] sm:gap-4"
  >
    <div>
      <label :for="`handoff-${kind}`" class="text-heading-3 text-n-slate-12">
        {{ t(`${key}.${kind.toUpperCase()}`) }}
      </label>
      <p v-if="kind === 'reopened'" class="mb-0 mt-1 text-xs text-n-slate-11">
        {{ t(`${key}.REOPENED_HELP`) }}
      </p>
    </div>
    <div class="flex min-w-0 flex-col gap-2">
      <ComboBox
        :id="`handoff-${kind}`"
        :model-value="row.mode"
        :options="options"
        :allow-deselect="false"
        :help="nameRich(`${key}.MODES.${row.mode.toUpperCase()}.HELP`)"
        @update:model-value="updateMode"
      />
      <p v-if="noTeams" class="m-0 text-xs text-n-slate-11">
        {{ t(`${key}.NO_TEAMS`) }}
      </p>
      <ComboBox
        v-if="row.mode === 'team'"
        :model-value="row.team_id ?? ''"
        :options="loading || loadError ? [] : teamOptions"
        :aria-label="t(`${key}.TEAM_PLACEHOLDER`)"
        :placeholder="teamPlaceholder"
        :display-label="deleted ? t(`${key}.TEAM_DELETED`) : ''"
        :disabled="loading || loadError"
        :has-error="!!error"
        :message="error"
        :allow-deselect="false"
        @update:model-value="row = { ...row, team_id: $event }"
      />
      <p v-if="warning" role="status" class="m-0 text-xs text-n-amber-11">
        {{ warning }}
      </p>
    </div>
  </div>
</template>
