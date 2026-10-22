<script setup>
import { computed, watch } from 'vue';
import { useAppointmentEvents } from 'dashboard/composables/useAppointmentEvents';
import { useAppointmentClock } from 'dashboard/composables/useAppointmentClock';
import Button from 'dashboard/components-next/button/Button.vue';
import { useI18n } from 'vue-i18n';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import AppointmentCreatorAvatar from './AppointmentCreatorAvatar.vue';
import { useCalendarTime } from 'dashboard/composables/useCalendarTime';

import {
  calendarEventStyle,
  appointmentStatusKey,
  invitationStatusKey,
} from 'dashboard/helper/appointmentStatus';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['errorChange', 'retry']);

// The next upcoming appointment of the contact, pinned under its details whatever conversation it was made in.
const { timezone, formatEventWhen, isUpcomingEvent } = useCalendarTime();

const { t, locale } = useI18n();
const { events, hasError, isLoading, load } = useAppointmentEvents({
  context: () => props.contactId,
  contactId: () => props.contactId,
  fetchEvents: signal =>
    CalendarAPI.getContactEvents(props.contactId, { signal }),
});
const now = useAppointmentClock(events, timezone);

const nextEvent = computed(
  () =>
    events.value
      .filter(event => isUpcomingEvent(event, now.value))
      .sort((a, b) => new Date(a.start) - new Date(b.start))[0]
);

const statusLabel = computed(() => {
  const key = appointmentStatusKey(nextEvent.value);
  return key ? t(`CONVERSATION_SIDEBAR.CALENDAR.STATUS.${key}`) : '';
});

const invitationLabel = computed(() => {
  const key = invitationStatusKey(nextEvent.value);
  return key ? t(`CONVERSATION_SIDEBAR.CALENDAR.INVITATION.${key}`) : '';
});

// The list below shows no second error while this card shows the failure; one retry reloads both.
watch(hasError, value => emit('errorChange', value), { immediate: true });
const retry = () => {
  load();
  emit('retry');
};

defineExpose({ refresh: load });
</script>

<template>
  <div
    v-if="hasError"
    role="alert"
    class="mx-3 mb-3 rounded-xl bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
  >
    <p>{{ t('CONVERSATION_SIDEBAR.CALENDAR.LOAD_ERROR') }}</p>
    <Button
      sm
      ghost
      :label="t('CONVERSATION_SIDEBAR.CALENDAR.RETRY')"
      @click="retry"
    />
  </div>
  <p
    v-else-if="!isLoading && !nextEvent"
    class="mx-3 mb-3 text-xs text-n-slate-11"
  >
    {{ t('CONVERSATION_SIDEBAR.CALENDAR.NEXT_EMPTY') }}
  </p>
  <div
    v-else-if="nextEvent"
    class="mx-3 mb-3 flex items-start gap-2 rounded-xl px-3 py-2.5"
    :class="calendarEventStyle(nextEvent).surface"
    data-testid="next-appointment"
  >
    <span
      class="i-lucide-calendar-clock mt-0.5 size-4 shrink-0"
      :class="calendarEventStyle(nextEvent).text"
    />
    <div class="flex min-w-0 flex-1 flex-col gap-0.5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('CONVERSATION_SIDEBAR.CALENDAR.NEXT') }}
      </span>
      <span class="truncate text-sm font-medium text-n-slate-12">
        {{ nextEvent.summary }}
      </span>
      <span class="text-xs text-n-slate-11">
        {{ formatEventWhen(nextEvent.start, locale) }}
      </span>
      <span
        v-if="statusLabel"
        class="text-xs"
        :class="calendarEventStyle(nextEvent).text"
      >
        {{ statusLabel }}
      </span>
      <span
        v-if="invitationLabel"
        class="text-xs text-n-slate-11"
        data-testid="next-appointment-invitation"
      >
        {{ invitationLabel }}
      </span>
    </div>
    <AppointmentCreatorAvatar :creator="nextEvent.creator" />
  </div>
</template>
