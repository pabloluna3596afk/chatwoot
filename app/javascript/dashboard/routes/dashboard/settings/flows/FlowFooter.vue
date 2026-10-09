<script setup>
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
/* eslint-disable vue/no-mutating-props -- exitPolicy is shared mutable from parent */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  exitPolicy: { type: Object, required: true },
  agents: { type: Array, default: () => [] },
  teams: { type: Array, default: () => [] },
});

const { t } = useI18n();

const exitEvents = ['on_complete', 'on_handoff', 'on_fail', 'on_human_break'];

const assigneeModes = computed(() => [
  { id: 'none', label: t('FLOWS.EXIT.MODE_NONE') },
  { id: 'keep', label: t('FLOWS.EXIT.MODE_KEEP') },
  { id: 'unassigned', label: t('FLOWS.EXIT.MODE_UNASSIGNED') },
  { id: 'pending', label: t('FLOWS.EXIT.MODE_PENDING') },
  { id: 'team', label: t('FLOWS.EXIT.MODE_TEAM') },
  { id: 'agent', label: t('FLOWS.EXIT.MODE_AGENT') },
  { id: 'contact_owner', label: t('FLOWS.EXIT.MODE_OWNER') },
]);

const statusOptions = computed(() => [
  { id: 'open', label: t('FLOWS.EXIT.STATUS_OPEN') },
  { id: 'pending', label: t('FLOWS.EXIT.STATUS_PENDING') },
  { id: 'resolved', label: t('FLOWS.EXIT.STATUS_RESOLVED') },
]);

const showTeamPicker = eventKey =>
  props.exitPolicy[eventKey]?.assignee_mode === 'team';

const showAgentPicker = eventKey =>
  props.exitPolicy[eventKey]?.assignee_mode === 'agent';

const showPrivateNote = eventKey =>
  ['on_handoff', 'on_fail', 'on_human_break'].includes(eventKey);
</script>

<template>
  <div class="flex flex-col gap-3 w-full">
    <p class="m-0 text-xs text-n-slate-11">
      {{ t('FLOWS.EXIT.HINT') }}
    </p>
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
      <div
        v-for="eventKey in exitEvents"
        :key="eventKey"
        class="rounded-md border border-n-weak bg-n-background dark:bg-n-solid-1 p-3"
      >
        <p class="m-0 mb-2 text-sm font-medium text-n-slate-12">
          {{ t(`FLOWS.EXIT.${eventKey.toUpperCase()}`) }}
        </p>
        <label class="mb-2 block">
          <span class="mb-1 block text-xs text-n-slate-11">
            {{ t('FLOWS.EXIT.STATUS') }}
          </span>
          <ComboBox
            v-model="exitPolicy[eventKey].status"
            class="mb-0"
            teleport
            :allow-deselect="false"
            :options="[
              ...statusOptions.map(s => ({ value: s.id, label: s.label })),
            ]"
          />
        </label>
        <label class="mb-2 block">
          <span class="mb-1 block text-xs text-n-slate-11">
            {{ t('FLOWS.EXIT.ASSIGNEE') }}
          </span>
          <ComboBox
            v-model="exitPolicy[eventKey].assignee_mode"
            class="mb-0"
            teleport
            :allow-deselect="false"
            :options="[
              ...assigneeModes.map(m => ({ value: m.id, label: m.label })),
            ]"
          />
        </label>
        <label v-if="showTeamPicker(eventKey)" class="mb-2 block">
          <span class="mb-1 block text-xs text-n-slate-11">
            {{ t('FLOWS.EXIT.TEAM') }}
          </span>
          <ComboBox
            v-model="exitPolicy[eventKey].team_id"
            class="mb-0"
            teleport
            :allow-deselect="false"
            :options="[
              { value: null, label: t('FLOWS.EXIT.PICK_TEAM') },
              ...teams.map(team => ({ value: team.id, label: team.name })),
            ]"
          />
        </label>
        <label v-if="showAgentPicker(eventKey)" class="mb-2 block">
          <span class="mb-1 block text-xs text-n-slate-11">
            {{ t('FLOWS.EXIT.AGENT') }}
          </span>
          <ComboBox
            v-model="exitPolicy[eventKey].agent_id"
            class="mb-0"
            teleport
            :allow-deselect="false"
            :options="[
              { value: null, label: t('FLOWS.EXIT.PICK_AGENT') },
              ...agents.map(agent => ({ value: agent.id, label: agent.name })),
            ]"
          />
        </label>
        <label
          v-if="showPrivateNote(eventKey)"
          class="mb-0 flex items-center gap-2"
        >
          <input
            v-model="exitPolicy[eventKey].private_note"
            type="checkbox"
            class="mb-0"
          />
          <span class="text-xs text-n-slate-11">
            {{ t('FLOWS.EXIT.PRIVATE_NOTE') }}
          </span>
        </label>
      </div>
    </div>
  </div>
</template>
