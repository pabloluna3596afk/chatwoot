<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import AppointmentCreatorAvatar from './AppointmentCreatorAvatar.vue';
import {
  formatEventWhen,
  isUpcomingEvent,
} from 'dashboard/helper/calendarTime';
import {
  appointmentStatusKey,
  invitationStatusKey,
} from 'dashboard/helper/appointmentStatus';

// The next upcoming appointment of the contact, pinned under its details whatever conversation it was made in.
const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});

const { t, locale } = useI18n();
const events = ref([]);

const nextEvent = computed(
  () =>
    events.value
      .filter(event => isUpcomingEvent(event))
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

const load = async () => {
  try {
    const { data } = await CalendarAPI.getContactEvents(props.contactId);
    events.value = data.payload || [];
  } catch (error) {
    events.value = [];
  }
};

watch(() => props.contactId, load, { immediate: true });
</script>

<template>
  <div
    v-if="nextEvent"
    class="mx-3 mb-3 flex items-start gap-2 rounded-xl bg-n-alpha-2 px-3 py-2.5"
    data-testid="next-appointment"
  >
    <span
      class="i-lucide-calendar-clock mt-0.5 size-4 shrink-0 text-n-blue-11"
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
      <span v-if="statusLabel" class="text-xs text-n-blue-11">
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
