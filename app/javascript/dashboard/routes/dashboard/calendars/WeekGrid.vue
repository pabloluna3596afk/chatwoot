<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNow } from '@vueuse/core';
import EventBlock from './EventBlock.vue';
import {
  calendarEventStyle,
  isCancelledEvent,
} from 'dashboard/helper/appointmentStatus';
import {
  GRID_ROWS_PER_HOUR,
  gridRowStyle,
  layoutDayEvents,
} from 'dashboard/helper/calendarGrid';
import { useCalendarTime } from 'dashboard/composables/useCalendarTime';
import {
  HOUR_END,
  HOUR_START,
  dayNumberFromKey,
  slotFromClick,
  weekDays,
} from 'dashboard/helper/calendarTime';

const props = defineProps({
  weekStartKey: { type: String, required: true },
  events: { type: Array, default: () => [] },
  hourStart: { type: Number, default: HOUR_START },
  hourEnd: { type: Number, default: HOUR_END },
});

const emit = defineEmits(['slotClick', 'event-click']);

const {
  timezone,
  calendarEventTooltip,
  eventDateKey,
  formatTime,
  formatWeekdayMonth,
  nowLinePercent,
  todayKey,
} = useCalendarTime();

const { t, locale } = useI18n();
const now = useNow({ interval: 60_000 });
const hours = computed(() =>
  Array.from(
    { length: props.hourEnd - props.hourStart },
    (_, index) => props.hourStart + index
  )
);
const gridStyle = computed(() => ({
  gridTemplateRows: `repeat(${hours.value.length * GRID_ROWS_PER_HOUR}, minmax(0, calc(1rem/15)))`,
}));
const today = computed(() => todayKey(now.value));
const nowLineTop = computed(() =>
  nowLinePercent(props.hourStart, props.hourEnd, now.value)
);
const days = computed(() =>
  weekDays(props.weekStartKey).map(dateKey => ({
    dateKey,
    label: formatWeekdayMonth(dateKey, locale.value),
    dayNumber: dayNumberFromKey(dateKey),
    allDay: props.events.filter(
      event => event.all_day && eventDateKey(event.start) === dateKey
    ),
    groups: layoutDayEvents(
      props.events,
      dateKey,
      props.hourStart,
      props.hourEnd,
      timezone.value
    ),
  }))
);
const onColumnClick = (event, dateKey) => {
  const rect = event.currentTarget.getBoundingClientRect();
  const slot = slotFromClick(
    event.clientY,
    rect.top,
    rect.height,
    props.hourStart,
    props.hourEnd
  );
  emit('slotClick', { dateKey, ...slot });
};
</script>

<template>
  <div class="hidden md:flex flex-col min-h-0 flex-1 overflow-auto">
    <div
      class="grid grid-cols-[3.5rem_repeat(7,minmax(0,1fr))] sticky top-0 bg-n-surface-1 z-10"
    >
      <div />
      <div
        v-for="day in days"
        :key="day.dateKey"
        class="px-2 py-2"
        :class="{ 'bg-n-blue-2/25': day.dateKey === today }"
      >
        <div class="flex items-center gap-1.5 capitalize">
          <span
            class="inline-flex items-center justify-center size-7 shrink-0 rounded-full text-xs font-medium"
            :class="
              day.dateKey === today
                ? 'bg-n-blue-9 text-n-blue-1'
                : 'text-n-slate-12'
            "
          >
            {{ day.dayNumber }}
          </span>
          <span class="text-xs truncate font-medium text-n-slate-12">{{
            day.label
          }}</span>
        </div>
      </div>
    </div>
    <div class="grid grid-cols-[3.5rem_repeat(7,minmax(0,1fr))] min-h-[2.5rem]">
      <div class="text-[10px] text-n-slate-10 px-1 py-1">
        {{ $t('SIDEBAR.CALENDAR_PAGE.ALL_DAY') }}
      </div>
      <div
        v-for="day in days"
        :key="`all-${day.dateKey}`"
        class="px-1 py-1 flex flex-col gap-1"
      >
        <button
          v-for="event in day.allDay"
          :key="event.id"
          type="button"
          class="truncate rounded px-1 text-[11px] text-start"
          :title="calendarEventTooltip(event, t)"
          :class="[
            calendarEventStyle(event).surface,
            { 'line-through': isCancelledEvent(event) },
          ]"
          @click="emit('event-click', event)"
        >
          {{ event.summary }}
        </button>
      </div>
    </div>
    <div class="grid grid-cols-[3.5rem_repeat(7,minmax(0,1fr))] relative">
      <div>
        <div v-for="hour in hours" :key="hour" class="relative h-16">
          <span
            class="absolute end-1 -top-2 text-[10px] leading-none text-n-slate-10"
          >
            <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
            {{ `${String(hour).padStart(2, '0')}:00` }}
          </span>
          <span
            class="absolute end-1 top-6 text-[10px] leading-none text-n-slate-10"
          >
            <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
            {{ `${String(hour).padStart(2, '0')}:30` }}
          </span>
        </div>
      </div>
      <div
        v-for="day in days"
        :key="day.dateKey"
        class="relative grid min-w-0 cursor-pointer border-s border-n-weak px-1"
        :style="gridStyle"
        @click="onColumnClick($event, day.dateKey)"
      >
        <div class="absolute inset-0 flex flex-col pointer-events-none">
          <div
            v-for="hour in hours"
            :key="hour"
            class="h-16 shrink-0 border-b border-n-weak/80"
          />
        </div>
        <div
          v-for="group in day.groups"
          :key="group.lanes[0][0].id"
          class="flex min-w-0 gap-1 z-[1] col-start-1"
          :style="gridRowStyle(group.row, group.endRow - group.row)"
        >
          <div
            v-for="(lane, index) in group.lanes"
            :key="index"
            class="grid auto-rows-[calc(1rem/15)] flex-1 min-w-0"
          >
            <EventBlock
              v-for="event in lane"
              :key="event.id"
              :event="{ ...event, timeLabel: formatTime(event.start) }"
              :compact="group.lanes.length > 1"
              :style="gridRowStyle(event.row - group.row, event.rowSpan)"
              @select="emit('event-click', $event)"
            />
          </div>
        </div>
        <div
          v-if="day.dateKey === today && nowLineTop !== null"
          class="absolute inset-x-0 border-t-2 border-n-ruby-9 pointer-events-none z-20"
          :style="{ top: `${nowLineTop}%` }"
        />
      </div>
    </div>
  </div>
</template>
