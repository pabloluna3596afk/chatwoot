<script setup>
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Label from 'dashboard/components-next/label/Label.vue';
import CalendarHours from './CalendarHours.vue';
import { usesCalendar } from './useCitasPanel';
import {
  calendarDisplayName,
  connectionDisplayName,
} from 'dashboard/helper/calendarLabels';

defineProps({
  calendars: { type: Array, required: true },
  assistants: { type: Array, required: true },
  withoutCalendar: { type: Array, required: true },
  assistantsFailed: Boolean,
});
const emit = defineEmits(['updated']);
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const assistantRoute = assistant =>
  accountScopedRoute('captain_assistants_settings_appointments_index', {
    assistantId: assistant.id,
  });
</script>

<template>
  <div class="flex min-w-0 flex-col gap-4">
    <p v-if="!calendars.length" class="text-body-main text-n-slate-11">
      {{ $t('CITAS_PANEL.NO_CALENDARS') }}
    </p>
    <section
      v-for="calendar in calendars"
      :key="`${calendar.connection.id}:${calendar.id}`"
      class="flex min-w-0 flex-col gap-4 rounded-xl border border-n-weak bg-n-card p-4"
    >
      <div class="min-w-0 break-words">
        <h3 class="text-heading-1 text-n-slate-12">
          {{ calendarDisplayName(calendar, t) }}
        </h3>
        <p class="text-body-main text-n-slate-11">
          {{ connectionDisplayName(calendar.connection, t) }}
        </p>
      </div>
      <CalendarHours :calendar="calendar" @updated="emit('updated', $event)" />
      <div class="flex flex-wrap items-center gap-2">
        <h4 class="text-body-main font-medium text-n-slate-12">
          {{ $t('CITAS_PANEL.BOOKINGS') }}
        </h4>
        <Label :label="$t('CITAS_PANEL.OPEN')" color="teal" role="status" />
      </div>
      <p class="text-body-main text-n-slate-11">
        {{ $t('CITAS_PANEL.BOOKINGS_READ_ONLY') }}
      </p>
      <h4 class="text-body-main font-medium text-n-slate-12">
        {{ $t('CITAS_PANEL.USED_BY') }}
      </h4>
      <template v-if="!assistantsFailed">
        <div
          v-for="assistant in assistants.filter(item =>
            usesCalendar(item, calendar)
          )"
          :key="assistant.id"
          class="flex flex-wrap items-center justify-between gap-2"
        >
          <span class="text-body-main text-n-slate-12">{{
            assistant.name
          }}</span>
          <RouterLink
            :to="assistantRoute(assistant)"
            class="text-body-main text-n-blue-11 underline"
          >
            {{ $t('CITAS_PANEL.CONFIGURE_ASSISTANT') }}
          </RouterLink>
        </div>
        <p
          v-if="!assistants.some(item => usesCalendar(item, calendar))"
          class="text-body-main text-n-slate-11"
        >
          {{ $t('CITAS_PANEL.HUMAN_ONLY') }}
        </p>
      </template>
    </section>
    <section
      v-if="withoutCalendar.length && !assistantsFailed"
      class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
    >
      <h3 class="text-heading-1 text-n-slate-12">
        {{ $t('CITAS_PANEL.WITHOUT_CALENDAR') }}
      </h3>
      <div
        v-for="assistant in withoutCalendar"
        :key="assistant.id"
        class="flex flex-wrap items-center justify-between gap-2"
      >
        <span class="text-body-main text-n-slate-12">{{ assistant.name }}</span>
        <RouterLink
          :to="assistantRoute(assistant)"
          class="text-body-main text-n-blue-11 underline"
        >
          {{ $t('CITAS_PANEL.CHOOSE_CALENDAR') }}
        </RouterLink>
      </div>
    </section>
    <p
      v-if="!assistants.length && !assistantsFailed"
      class="text-body-main text-n-slate-11"
    >
      {{ $t('CITAS_PANEL.NO_ASSISTANTS') }}
    </p>
  </div>
</template>
