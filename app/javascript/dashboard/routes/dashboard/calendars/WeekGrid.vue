<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNow } from '@vueuse/core';
import EventBlock from './EventBlock.vue';
import {
  HOUR_END,
  HOUR_START,
  dayNumberFromKey,
  eventDateKey,
  eventLayout,
  formatTime,
  formatWeekdayMonth,
  nowLinePercent,
  slotFromClick,
  todayKey,
  weekDays,
} from 'dashboard/helper/calendarTime';

const props = defineProps({
  weekStartKey: {
    type: String,
    required: true,
  },
  events: {
    type: Array,
    default: () => [],
  },
  hourStart: {
    type: Number,
    default: HOUR_START,
  },
  hourEnd: {
    type: Number,
    default: HOUR_END,
  },
});

const emit = defineEmits(['slotClick', 'event-click']);
const { locale } = useI18n();
const now = useNow({ interval: 60_000 });

const hours = computed(() => {
  const start = Number(props.hourStart) || HOUR_START;
  const end = Number(props.hourEnd) || HOUR_END;
  const span = Math.max(end - start, 1);
  return Array.from({ length: span }, (_, index) => start + index);
});

const today = computed(() => todayKey(now.value));

const nowLineTop = computed(() =>
  nowLinePercent(props.hourStart, props.hourEnd, now.value)
);

const showNowLine = dateKey =>
  dateKey === today.value && nowLineTop.value !== null;

const isToday = dateKey => dateKey === today.value;

const days = computed(() =>
  weekDays(props.weekStartKey).map(dateKey => ({
    dateKey,
    label: formatWeekdayMonth(dateKey, locale.value),
    dayNumber: dayNumberFromKey(dateKey),
    allDay: props.events.filter(
      event => event.all_day && eventDateKey(event.start) === dateKey
    ),
    timed: props.events
      .filter(event => !event.all_day && eventDateKey(event.start) === dateKey)
      .map(event => {
        const layout = eventLayout(
          event.start,
          event.end,
          props.hourStart,
          props.hourEnd
        );
        return {
          ...event,
          ...layout,
          timeLabel: formatTime(event.start),
        };
      }),
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
      class="grid grid-cols-[3.5rem_repeat(7,minmax(0,1fr))] border-b border-n-weak sticky top-0 bg-n-surface-1 z-10"
    >
      <div />
      <div
        v-for="day in days"
        :key="day.dateKey"
        class="px-2 py-2 border-l border-n-weak"
        :class="isToday(day.dateKey) ? 'bg-n-blue-2/25' : ''"
      >
        <div class="flex items-center gap-1.5 capitalize">
          <span
            class="inline-flex items-center justify-center size-7 shrink-0 rounded-full text-xs font-medium"
            :class="
              isToday(day.dateKey)
                ? 'bg-n-blue-9 text-white'
                : 'text-n-slate-12'
            "
          >
            {{ day.dayNumber }}
          </span>
          <span
            class="text-xs truncate"
            :class="
              isToday(day.dateKey)
                ? 'font-medium text-n-blue-11'
                : 'font-medium text-n-slate-12'
            "
          >
            {{ day.label }}
          </span>
        </div>
      </div>
    </div>

    <div
      class="grid grid-cols-[3.5rem_repeat(7,minmax(0,1fr))] min-h-[2.5rem] border-b border-n-weak"
    >
      <div class="text-[10px] text-n-slate-10 px-1 py-1">
        {{ $t('SIDEBAR.CALENDAR_PAGE.ALL_DAY') }}
      </div>
      <div
        v-for="day in days"
        :key="`all-${day.dateKey}`"
        class="border-l border-n-weak px-1 py-1 flex flex-col gap-1"
        :class="isToday(day.dateKey) ? 'bg-n-blue-2/15' : ''"
      >
        <button
          v-for="event in day.allDay"
          :key="event.id"
          type="button"
          class="truncate rounded px-1 text-[11px] text-left"
          :class="
            event.deleted
              ? 'bg-n-ruby-3/80 text-n-ruby-11 line-through'
              : 'bg-n-blue-4 text-n-blue-11'
          "
          @click="emit('event-click', event)"
        >
          <template v-if="event.deleted">
            {{ $t('SIDEBAR.CALENDAR_PAGE.DELETED') }}
            <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
            ·
          </template>
          {{ event.summary }}
          <span v-if="event.created_by?.name" class="opacity-70">
            <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
            · {{ event.created_by.name }}
          </span>
        </button>
      </div>
    </div>

    <div
      class="grid grid-cols-[3.5rem_repeat(7,minmax(0,1fr))] relative"
      :style="{ minHeight: `${hours.length * 4}rem` }"
    >
      <div class="relative">
        <div v-for="hour in hours" :key="hour" class="relative h-16">
          <span
            class="absolute right-1 -top-2 text-[10px] leading-none text-n-slate-10"
          >
            <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
            {{ String(hour).padStart(2, '0') }}:00
          </span>
        </div>
      </div>
      <div
        v-for="day in days"
        :key="`col-${day.dateKey}`"
        class="relative border-l border-n-weak cursor-pointer"
        :class="isToday(day.dateKey) ? 'bg-n-blue-2/15' : ''"
        @click="onColumnClick($event, day.dateKey)"
      >
        <div
          v-for="hour in hours"
          :key="`${day.dateKey}-${hour}`"
          class="h-16 border-b border-n-weak/80"
        />
        <div
          v-if="showNowLine(day.dateKey)"
          class="absolute left-0 right-0 z-20 pointer-events-none"
          :style="{ top: `${nowLineTop}%` }"
        >
          <div class="relative border-t-2 border-n-ruby-9">
            <span
              class="absolute -left-1 -top-1 size-2 rounded-full bg-n-ruby-9"
              aria-hidden="true"
            />
          </div>
        </div>
        <EventBlock
          v-for="event in day.timed"
          :key="event.id"
          :event="event"
          @select="emit('event-click', $event)"
        />
      </div>
    </div>
  </div>
</template>
