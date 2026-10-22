<script setup>
import {
  CALENDAR_LEGEND_STATUSES,
  calendarEventStyle,
} from 'dashboard/helper/appointmentStatus';
</script>

<template>
  <div class="flex flex-col gap-1.5 text-xs text-n-slate-11">
    <span
      v-for="status in CALENDAR_LEGEND_STATUSES"
      :key="status"
      v-tooltip.top="$t('SIDEBAR.CALENDAR_PAGE.LEGEND_HELP')"
      class="inline-flex items-center gap-1.5"
    >
      <span
        class="size-2 rounded-full"
        :class="calendarEventStyle({ appointment_status: status }).dot"
      />
      {{ $t(`SIDEBAR.CALENDAR_PAGE.STATUS.${status.toUpperCase()}`) }}
    </span>
  </div>
</template>
