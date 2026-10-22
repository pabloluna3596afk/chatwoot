<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCalendarTime } from 'dashboard/composables/useCalendarTime';
import AppointmentOriginLogo from 'dashboard/components/widgets/conversation/AppointmentOriginLogo.vue';

import {
  calendarEventStyle,
  isCancelledEvent,
} from 'dashboard/helper/appointmentStatus';

const props = defineProps({
  event: { type: Object, required: true },
  compact: { type: Boolean, default: false },
});

const emit = defineEmits(['select']);

const { calendarEventTooltip } = useCalendarTime();

const { t } = useI18n();
const APPOINTMENT_TITLE_PREFIX = /^(?:Cita|Appointment)\s*·\s*/i;
const displayTitle = computed(() =>
  props.compact
    ? props.event.summary.replace(APPOINTMENT_TITLE_PREFIX, '')
    : props.event.summary
);
</script>

<template>
  <button
    type="button"
    class="col-start-1 z-[1] min-w-0 overflow-hidden rounded-md px-1 py-0.5 text-start"
    :class="calendarEventStyle(event).surface"
    :title="calendarEventTooltip(event, t)"
    @click.stop="emit('select', event)"
  >
    <span class="flex min-w-0 items-center gap-1 text-[11px] leading-tight">
      <span v-if="!compact" class="shrink-0 font-medium">{{
        event.timeLabel
      }}</span>
      <span
        class="truncate"
        :class="{ 'line-through': isCancelledEvent(event) }"
      >
        {{ displayTitle }}
      </span>
      <AppointmentOriginLogo
        v-if="!compact"
        :origin="event.origin"
        :size="12"
        class="ms-auto"
      />
    </span>
  </button>
</template>
