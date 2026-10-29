<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import OutlinedSelectField from 'dashboard/components-next/CustomAttributes/OutlinedSelectField.vue';

const props = defineProps({
  item: { type: Object, required: true },
  labels: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
  teams: { type: Array, default: () => [] },
});
const emit = defineEmits(['approve', 'reject', 'edit']);
const { t } = useI18n();
const isEditing = ref(false);
const draft = ref({ ...props.item.payload });
watch(
  () => props.item.payload,
  value => {
    draft.value = { ...value };
  }
);
const actionIcon = computed(
  () =>
    ({
      add_label: 'i-lucide-tag',
      private_note: 'i-lucide-sticky-note',
      assignment: 'i-lucide-user-round-check',
    })[props.item.action] || 'i-lucide-circle-help'
);
const isPending = computed(() => props.item.status === 'pending');
const labelOptions = computed(() =>
  props.labels.map(label => ({ id: label.id, name: label.title }))
);
const selectedLabel = computed(
  () =>
    labelOptions.value.find(
      label => Number(label.id) === Number(draft.value.label_id)
    ) || null
);
const agentOptions = computed(() => [
  { id: null, name: t('CAPTAIN.COPILOT.ACTIONS.NO_AGENT') },
  ...props.agents.map(agent => ({ id: agent.id, name: agent.name })),
]);
const selectedAgent = computed(
  () =>
    agentOptions.value.find(
      agent => Number(agent.id) === Number(draft.value.assignee_id)
    ) || agentOptions.value[0]
);
const teamOptions = computed(() => [
  { id: null, name: t('CAPTAIN.COPILOT.ACTIONS.NO_TEAM') },
  ...props.teams.map(team => ({ id: team.id, name: team.name })),
]);
const selectedTeam = computed(
  () =>
    teamOptions.value.find(
      team => Number(team.id) === Number(draft.value.team_id)
    ) || teamOptions.value[0]
);
const targetLabel = computed(() => {
  const values = {
    name: props.item.target_name || t('CAPTAIN.COPILOT.ACTIONS.UNKNOWN_TARGET'),
    id: props.item.target_id,
  };
  return props.item.target_type === 'Contact'
    ? t('CAPTAIN.COPILOT.ACTIONS.CONTACT_TARGET', values)
    : t('CAPTAIN.COPILOT.ACTIONS.CONVERSATION_TARGET', values);
});
const title = computed(() => {
  if (props.item.action === 'add_label')
    return t('CAPTAIN.COPILOT.ACTIONS.ADD_LABEL_TITLE', {
      target: targetLabel.value,
    });
  if (props.item.action === 'private_note')
    return t('CAPTAIN.COPILOT.ACTIONS.PRIVATE_NOTE_TITLE');
  if (props.item.action === 'assignment')
    return t('CAPTAIN.COPILOT.ACTIONS.ASSIGNMENT_TITLE');
  return t('CAPTAIN.COPILOT.ACTIONS.GENERIC_TITLE');
});
const description = computed(() => {
  if (props.item.action === 'add_label') {
    return (
      props.item.payload.label_name ||
      props.labels.find(
        label => label.id === Number(props.item.payload.label_id)
      )?.title ||
      t('CAPTAIN.COPILOT.ACTIONS.LABEL_FALLBACK', {
        id: props.item.payload.label_id,
      })
    );
  }
  if (props.item.action === 'private_note') return props.item.payload.content;
  const agent = props.agents.find(
    entry => entry.id === Number(props.item.payload.assignee_id)
  );
  const team = props.teams.find(
    entry => entry.id === Number(props.item.payload.team_id)
  );
  return (
    [agent?.name, team?.name].filter(Boolean).join(' · ') ||
    t('CAPTAIN.COPILOT.ACTIONS.ASSIGNMENT_PREVIEW')
  );
});
const statusLabel = computed(() => {
  const labels = {
    pending: t('CAPTAIN.COPILOT.ACTIONS.STATUS.PENDING'),
    approved: t('CAPTAIN.COPILOT.ACTIONS.STATUS.APPROVED'),
    executed: t('CAPTAIN.COPILOT.ACTIONS.STATUS.EXECUTED'),
    rejected: t('CAPTAIN.COPILOT.ACTIONS.STATUS.REJECTED'),
    expired: t('CAPTAIN.COPILOT.ACTIONS.STATUS.EXPIRED'),
    failed: t('CAPTAIN.COPILOT.ACTIONS.STATUS.FAILED'),
  };
  return labels[props.item.status] || props.item.status;
});
const statusClass = computed(() => {
  if (props.item.status === 'approved' || props.item.status === 'executed')
    return 'text-n-teal-11';
  if (props.item.status === 'rejected' || props.item.status === 'failed')
    return 'text-n-slate-11';
  if (props.item.status === 'expired') return 'text-n-amber-11';
  return 'text-n-slate-10';
});
const resultLabel = computed(() => {
  const result = props.item.result;
  if (result?.code === 'label_added')
    return t('CAPTAIN.COPILOT.ACTIONS.RESULT.LABEL_ADDED', {
      label: result.label,
    });
  if (result?.code === 'private_note_added')
    return t('CAPTAIN.COPILOT.ACTIONS.RESULT.PRIVATE_NOTE_ADDED');
  if (result?.code === 'assignment_updated')
    return t('CAPTAIN.COPILOT.ACTIONS.RESULT.ASSIGNMENT_UPDATED');
  return '';
});
const edit = () => {
  emit('edit', { id: props.item.id, payload: draft.value });
  isEditing.value = false;
};
</script>

<template>
  <article
    class="min-w-0 w-full max-w-full rounded-xl border border-n-weak bg-n-surface-2 p-3 text-sm text-n-slate-12"
  >
    <div class="flex min-w-0 items-start gap-2">
      <i
        class="mt-0.5 shrink-0 text-n-slate-11"
        :class="[actionIcon]"
        aria-hidden="true"
      />
      <div class="min-w-0 flex-1">
        <div class="font-medium break-words">{{ title }}</div>
        <div class="mt-1 break-words text-xs text-n-slate-10">
          {{ targetLabel }}
        </div>
        <div v-if="!isEditing" class="mt-2 whitespace-pre-wrap break-words">
          {{ description }}
        </div>
        <div v-else class="mt-2 flex flex-col gap-2">
          <OutlinedSelectField
            v-if="item.action === 'add_label'"
            :label="$t('CAPTAIN.COPILOT.ACTIONS.LABEL')"
            :options="labelOptions"
            :selected-item="selectedLabel"
            :placeholder="$t('CAPTAIN.COPILOT.ACTIONS.LABEL')"
            @select="draft.label_id = $event?.id"
          />
          <textarea
            v-else-if="item.action === 'private_note'"
            v-model="draft.content"
            rows="3"
            class="w-full resize-y rounded-md border border-n-weak bg-n-surface-1 p-2"
            :aria-label="$t('CAPTAIN.COPILOT.ACTIONS.NOTE')"
          />
          <template v-else>
            <OutlinedSelectField
              :label="$t('CAPTAIN.COPILOT.ACTIONS.AGENT')"
              :options="agentOptions"
              :selected-item="selectedAgent"
              :placeholder="$t('CAPTAIN.COPILOT.ACTIONS.NO_AGENT')"
              @select="draft.assignee_id = $event?.id"
            />
            <OutlinedSelectField
              :label="$t('CAPTAIN.COPILOT.ACTIONS.TEAM')"
              :options="teamOptions"
              :selected-item="selectedTeam"
              :placeholder="$t('CAPTAIN.COPILOT.ACTIONS.NO_TEAM')"
              @select="draft.team_id = $event?.id"
            />
          </template>
        </div>
        <div class="mt-2 text-xs" :class="statusClass">{{ statusLabel }}</div>
        <div
          v-if="item.status === 'executed'"
          class="mt-1 flex items-center gap-1 text-xs text-n-teal-11"
        >
          <i class="i-lucide-circle-check" aria-hidden="true" />{{
            resultLabel
          }}
        </div>
        <div
          v-if="item.status === 'failed'"
          class="mt-1 break-words text-xs text-n-ruby-11"
        >
          {{ $t('CAPTAIN.COPILOT.ACTIONS.FAILED_DESCRIPTION') }}
        </div>
        <div v-if="isPending" class="mt-3 flex flex-wrap items-center gap-2">
          <template v-if="isEditing">
            <Button
              :label="$t('CAPTAIN.COPILOT.ACTIONS.SAVE')"
              intent="primary"
              size="sm"
              @click="edit"
            />
            <Button
              :label="$t('CAPTAIN.COPILOT.ACTIONS.CANCEL')"
              intent="secondary"
              size="sm"
              @click="isEditing = false"
            />
          </template>
          <template v-else>
            <Button
              :label="$t('CAPTAIN.COPILOT.ACTIONS.APPROVE')"
              intent="primary"
              color="teal"
              size="sm"
              @click="emit('approve', item.id)"
            />
            <Button
              :label="$t('CAPTAIN.COPILOT.ACTIONS.REJECT')"
              intent="secondary"
              size="sm"
              @click="emit('reject', item.id)"
            />
            <Button
              :label="$t('CAPTAIN.COPILOT.ACTIONS.EDIT')"
              intent="tertiary"
              size="sm"
              @click="isEditing = true"
            />
          </template>
        </div>
      </div>
    </div>
  </article>
</template>
