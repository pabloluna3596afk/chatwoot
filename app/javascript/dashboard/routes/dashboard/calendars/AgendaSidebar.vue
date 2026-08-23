<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useNow } from '@vueuse/core';
import {
  compareEventsByStart,
  formatTime,
  isEventCurrent,
  isEventPast,
  todayKey,
} from 'dashboard/helper/calendarTime';

const props = defineProps({
  groups: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['event-click']);

const scrollRoot = ref(null);
const now = useNow({ interval: 60_000 });

const daysWithEvents = computed(() =>
  props.groups
    .map(group => ({
      ...group,
      events: (group.events || [])
        .filter(event => !event.deleted)
        .sort(compareEventsByStart),
    }))
    .filter(group => group.events.length)
);

const deletedEvents = computed(() =>
  props.groups.flatMap(group =>
    (group.events || []).filter(event => event.deleted)
  )
);

const scrollAnchorId = computed(() => {
  const today = todayKey(now.value);
  const weekHasToday = props.groups.some(group => group.key === today);
  if (!weekHasToday) return null;

  const entries = daysWithEvents.value.flatMap(group =>
    group.events.map(event => ({
      id: `agenda-event-${event.id}`,
      past: isEventPast(event, now.value.getTime()),
    }))
  );
  const firstCurrentOrFuture = entries.find(entry => !entry.past);
  if (firstCurrentOrFuture) return firstCurrentOrFuture.id;
  return entries.at(-1)?.id ?? null;
});

const scrollToAnchor = async () => {
  await nextTick();
  const root = scrollRoot.value;
  if (!root) return;

  const anchorId = scrollAnchorId.value;
  if (!anchorId) {
    root.scrollTop = 0;
    return;
  }

  const anchor = root.querySelector(`#${anchorId}`);
  if (anchor) {
    anchor.scrollIntoView({ block: 'start', behavior: 'auto' });
  }
};

watch([() => props.groups, scrollAnchorId], scrollToAnchor, {
  immediate: true,
});

const isCurrentEvent = event => isEventCurrent(event, now.value.getTime());
</script>

<template>
  <aside
    ref="scrollRoot"
    class="hidden md:flex flex-col w-64 shrink-0 border-r border-n-weak overflow-auto px-3 py-4"
  >
    <h2 class="px-1 mb-3 text-sm font-medium text-n-slate-12 shrink-0">
      {{ $t('SIDEBAR.CALENDAR_PAGE.AGENDA') }}
    </h2>
    <p v-if="!daysWithEvents.length" class="px-1 text-sm text-n-slate-11">
      {{ $t('SIDEBAR.CALENDAR_PAGE.NO_EVENTS') }}
    </p>
    <div v-else class="flex flex-col gap-5">
      <section v-for="group in daysWithEvents" :key="group.key">
        <h3
          class="px-1 mb-2 text-xs font-medium capitalize"
          :class="
            group.key === todayKey(now) ? 'text-n-blue-11' : 'text-n-slate-11'
          "
        >
          {{ group.label }}
        </h3>
        <div class="flex flex-col gap-0.5">
          <button
            v-for="event in group.events"
            :id="`agenda-event-${event.id}`"
            :key="event.id"
            type="button"
            class="flex w-full items-start gap-2 rounded-lg px-1 py-1.5 text-left hover:bg-n-alpha-2"
            :class="isCurrentEvent(event) ? 'bg-n-blue-3/40' : ''"
            @click="emit('event-click', event)"
          >
            <span
              class="mt-1.5 size-2 shrink-0 rounded-full"
              :class="isCurrentEvent(event) ? 'bg-n-blue-11' : 'bg-n-blue-9'"
              aria-hidden="true"
            />
            <span class="min-w-0 flex-1">
              <span class="block text-sm text-n-slate-12 truncate">
                {{ event.summary }}
              </span>
              <span class="block text-[11px] text-n-slate-11 truncate">
                {{
                  event.all_day
                    ? $t('SIDEBAR.CALENDAR_PAGE.ALL_DAY')
                    : formatTime(event.start)
                }}
                <template v-if="event.created_by?.name">
                  · {{ event.created_by.name }}
                </template>
              </span>
            </span>
          </button>
        </div>
      </section>
    </div>
    <section
      v-if="deletedEvents.length"
      class="mt-6 pt-4 border-t border-n-ruby-6"
    >
      <h3 class="px-1 mb-2 text-xs font-medium text-n-ruby-11">
        {{ $t('SIDEBAR.CALENDAR_PAGE.DELETED_SECTION') }}
      </h3>
      <div class="flex flex-col gap-0.5">
        <button
          v-for="event in deletedEvents"
          :key="event.id"
          type="button"
          class="flex w-full items-start gap-2 rounded-lg px-1 py-1.5 text-left bg-n-ruby-3/50 hover:bg-n-ruby-4"
          @click="emit('event-click', event)"
        >
          <span
            class="mt-1.5 size-2 shrink-0 rounded-full bg-n-ruby-9"
            aria-hidden="true"
          />
          <span class="min-w-0 flex-1">
            <span class="block text-[10px] font-medium text-n-ruby-11">
              {{ $t('SIDEBAR.CALENDAR_PAGE.DELETED') }}
            </span>
            <span class="block text-sm text-n-ruby-11 truncate line-through">
              {{ event.summary }}
            </span>
            <span class="block text-[11px] text-n-ruby-11/80 truncate">
              {{ formatTime(event.start) }}
              <template v-if="event.deleted_by?.name">
                · {{ event.deleted_by.name }}
              </template>
            </span>
            <span
              v-if="event.deleted_note"
              class="block text-[11px] text-n-ruby-11 truncate"
            >
              {{ event.deleted_note }}
            </span>
          </span>
        </button>
      </div>
    </section>
  </aside>
</template>
