<script setup>
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import CalendarHours from './CalendarHours.vue';
import { usesCalendar } from './useCitasPanel';
import {
  calendarDisplayName,
  connectionDisplayName,
} from 'dashboard/helper/calendarLabels';

defineProps({
  connections: { type: Array, required: true },
  calendarErrors: { type: Object, required: true },
  calendarLoading: { type: Object, required: true },
  calendars: { type: Array, required: true },
  assistants: { type: Array, required: true },
  withoutCalendar: { type: Array, required: true },
  assistantsFailed: Boolean,
  assistantsLoading: Boolean,
  calendarsLoading: Boolean,
});
const emit = defineEmits(['updated', 'retryCalendar', 'retryAssistants']);
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const assistantRoute = assistant =>
  accountScopedRoute('captain_assistants_settings_appointments_index', {
    assistantId: assistant.id,
  });
</script>

<template>
  <div class="flex min-w-0 flex-col gap-4">
    <section
      v-for="connection in connections.filter(
        item => calendarErrors[item.id] || calendarLoading[item.id]
      )"
      :key="connection.id"
      :role="calendarErrors[connection.id] ? 'alert' : 'status'"
      class="py-2 text-body-main text-n-ruby-11"
    >
      <h3>{{ connectionDisplayName(connection, t) }}</h3>
      <p>{{ $t('CITAS_SCREEN.STEP_CALENDAR') }}</p>
      <Spinner v-if="calendarLoading[connection.id]" />
      <p v-if="calendarErrors[connection.id]">
        {{ $t('CITAS_PANEL.SECTION_ERROR') }}
      </p>
      <Button
        v-if="calendarErrors[connection.id]"
        intent="secondary"
        :label="$t('CITAS_PANEL.RETRY')"
        :is-loading="calendarLoading[connection.id]"
        @click="emit('retryCalendar', connection)"
      />
    </section>
    <div
      v-if="assistantsFailed"
      role="alert"
      class="text-body-main text-n-ruby-11"
    >
      <h3>{{ $t('CITAS_PANEL.ASSISTANTS') }}</h3>
      <p>{{ $t('CITAS_PANEL.SECTION_ERROR') }}</p>
      <Button
        intent="secondary"
        :label="$t('CITAS_PANEL.RETRY')"
        @click="emit('retryAssistants')"
      />
    </div>
    <p
      v-if="
        !calendarsLoading &&
        !calendars.length &&
        !Object.values(calendarErrors).some(Boolean)
      "
      class="text-body-main text-n-slate-11"
    >
      {{ $t('CITAS_PANEL.NO_CALENDARS') }}
    </p>
    <section
      v-for="calendar in calendars"
      :key="`${calendar.connection.id}:${calendar.id}`"
      class="flex min-w-0 flex-col gap-4 py-3"
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
        <Label
          :label="$t('CITAS_SCREEN.CALENDAR_OPEN')"
          color="teal"
          role="status"
        />
      </div>
      <p class="text-body-main text-n-slate-11">
        {{ $t('CITAS_PANEL.BOOKINGS_READ_ONLY') }}
      </p>
      <h4 class="text-body-main font-medium text-n-slate-12">
        {{ $t('CITAS_PANEL.USED_BY') }}
      </h4>
      <template v-if="!assistantsFailed && !assistantsLoading">
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
      v-if="
        withoutCalendar.length &&
        !assistantsFailed &&
        !assistantsLoading &&
        !calendarsLoading
      "
      class="flex flex-col gap-3 py-3"
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
      v-if="!assistants.length && !assistantsFailed && !assistantsLoading"
      class="text-body-main text-n-slate-11"
    >
      {{ $t('CITAS_PANEL.NO_ASSISTANTS') }}
    </p>
  </div>
</template>
