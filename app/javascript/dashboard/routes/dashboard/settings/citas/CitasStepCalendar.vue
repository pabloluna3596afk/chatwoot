<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CitasStepRow from './CitasStepRow.vue';
import CalendarResources from './CalendarResources.vue';
import { connectionDisplayName } from 'dashboard/helper/calendarLabels';

const props = defineProps({
  connections: { type: Array, required: true },
  calendars: { type: Array, required: true },
  connected: Boolean,
  loading: { type: Object, required: true },
  errors: { type: Object, required: true },
  expanded: Boolean,
  calendarErrors: { type: Object, required: true },
  calendarLoading: { type: Object, required: true },
  assistants: { type: Array, required: true },
  withoutCalendar: { type: Array, required: true },
});
const emit = defineEmits([
  'toggle',
  'retryConnections',
  'retryCalendar',
  'retryAssistants',
  'updated',
]);
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const value = computed(() => {
  if (props.loading.connections || props.loading.calendars) return '';
  if (!props.connections.length) return '';
  const connection = props.connections[0];
  const email = connection.email || connectionDisplayName(connection, t);
  return t('CITAS_SCREEN.CALENDAR_VALUE', props.calendars.length, {
    email,
    count: props.calendars.length,
  });
});
</script>

<template>
  <CitasStepRow
    :icon="connected ? 'done' : '1'"
    :title="$t('CITAS_SCREEN.STEP_CALENDAR')"
    :value="value"
    :expanded="expanded"
    :disabled="!connected && !loading.connections"
    data-testid="citas-calendar-step"
  >
    <template #actions="{ contentId }">
      <Button
        v-if="connected"
        intent="tertiary"
        size="sm"
        :label="expanded ? $t('CITAS_SCREEN.CLOSE') : $t('CITAS_SCREEN.MANAGE')"
        :aria-expanded="expanded"
        :aria-controls="contentId"
        @click="emit('toggle')"
      />
      <RouterLink
        v-else-if="!loading.connections"
        :to="accountScopedRoute('settings_integrations_calendars')"
        class="text-body-main text-n-blue-11 underline"
      >
        {{ $t('CITAS_SCREEN.CONNECT') }}
      </RouterLink>
    </template>
    <Spinner v-if="loading.connections || loading.calendars" />
    <p
      v-else-if="errors.connections"
      role="alert"
      class="text-body-main text-n-ruby-11"
    >
      {{ $t('INTEGRATION_SETTINGS.CALENDARS.LOAD_ERROR') }}
      <Button
        intent="secondary"
        :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
        @click="emit('retryConnections')"
      />
    </p>
    <p v-else-if="!connected" class="text-body-main text-n-slate-11">
      {{ $t('CITAS_SCREEN.NO_GOOGLE') }}
    </p>
    <template v-else>
      <CalendarResources
        :connections="connections"
        :calendar-errors="calendarErrors"
        :calendar-loading="calendarLoading"
        :calendars-loading="loading.calendars"
        :calendars="calendars"
        :assistants="assistants"
        :without-calendar="withoutCalendar"
        :assistants-failed="errors.assistants"
        :assistants-loading="loading.assistants"
        @updated="emit('updated', $event)"
        @retry-calendar="emit('retryCalendar', $event)"
        @retry-assistants="emit('retryAssistants')"
      />
      <p class="m-0 text-body-main text-n-slate-11">
        {{ $t('CITAS_SCREEN.CALENDAR_HELP') }}
        <RouterLink
          :to="accountScopedRoute('settings_integrations_calendars')"
          class="text-n-blue-11 underline"
        >
          {{ $t('CITAS_SETTINGS.MANAGE_CONNECTION') }}
        </RouterLink>
      </p>
    </template>
  </CitasStepRow>
</template>
