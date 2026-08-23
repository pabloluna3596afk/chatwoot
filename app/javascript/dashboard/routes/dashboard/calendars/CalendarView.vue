<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { vOnClickOutside } from '@vueuse/components';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import OutlinedAttributeField from 'dashboard/components-next/CustomAttributes/OutlinedAttributeField.vue';
import OutlinedSelectField from 'dashboard/components-next/CustomAttributes/OutlinedSelectField.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import WeekGrid from './WeekGrid.vue';
import AgendaSidebar from './AgendaSidebar.vue';
import EventModal from './EventModal.vue';
import googleLogo from 'dashboard/assets/images/integrations/google.svg';
import microsoftLogo from 'dashboard/assets/images/integrations/microsoft.svg';
import {
  HOUR_END,
  HOUR_START,
  addDaysKey,
  compareEventsByStart,
  eventDateKey,
  formatDayLabel,
  formatTime,
  startOfWeekKey,
  weekBoundsIso,
  weekDays,
} from 'dashboard/helper/calendarTime';
import {
  calendarDisplayName,
  connectionDisplayName,
} from 'dashboard/helper/calendarLabels';
import { useCalendarCancelledVisibility } from 'dashboard/helper/useCalendarCancelledVisibility';

const { t, locale } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();
const { isAdmin } = useAdmin();

const loading = ref(true);
const calendarsReady = ref(false);
const loadingEvents = ref(false);
const connections = ref([]);
const calendars = ref([]);
const events = ref([]);
const selectedConnectionId = ref('');
const selectedCalendarId = ref('');
const weekStartKey = ref(startOfWeekKey());
const modalRef = ref(null);
const showMenu = ref(false);
const showAccountMenu = ref(false);
const { showCancelled } = useCalendarCancelledVisibility();

const visibleEvents = computed(() =>
  showCancelled.value
    ? events.value
    : events.value.filter(event => !event.deleted)
);

const calendarOutlineOptions = computed(() =>
  calendars.value.map(item => ({
    id: item.id,
    name: calendarDisplayName(item, t),
  }))
);

const selectedCalendarItem = computed(
  () =>
    calendarOutlineOptions.value.find(
      item => item.id === selectedCalendarId.value
    ) || null
);

const onCalendarSelect = item => {
  if (item?.id) selectedCalendarId.value = item.id;
};

const providerLogoFor = provider =>
  provider === 'microsoft' ? microsoftLogo : googleLogo;

const selectedConnection = computed(() =>
  connections.value.find(item => String(item.id) === selectedConnectionId.value)
);

const selectedConnectionLabel = computed(() =>
  connectionDisplayName(selectedConnection.value, t)
);

const selectConnection = connectionId => {
  selectedConnectionId.value = String(connectionId);
  showAccountMenu.value = false;
};

const weekLabel = computed(() => {
  const start = weekStartKey.value;
  const end = addDaysKey(start, 6);
  return `${formatDayLabel(start, locale.value)} - ${formatDayLabel(end, locale.value)}`;
});

const groupedEvents = computed(() =>
  weekDays(weekStartKey.value).map(dateKey => ({
    key: dateKey,
    label: formatDayLabel(dateKey, locale.value),
    events: visibleEvents.value
      .filter(event => eventDateKey(event.start) === dateKey)
      .sort(compareEventsByStart),
  }))
);

const hasConnections = computed(() => connections.value.length > 0);
const hasEnabledCalendars = computed(() => calendars.value.length > 0);
const selectedCalendar = computed(() =>
  calendars.value.find(item => item.id === selectedCalendarId.value)
);
const hourStart = computed(() =>
  Number(selectedCalendar.value?.hour_start ?? HOUR_START)
);
const hourEnd = computed(() =>
  Number(selectedCalendar.value?.hour_end ?? HOUR_END)
);

const showGrid = computed(() => !loading.value && calendarsReady.value);

const loadConnections = async () => {
  loading.value = true;
  calendarsReady.value = false;
  try {
    const { data } = await CalendarAPI.getConnections();
    connections.value = (data.payload || []).filter(item =>
      ['google', 'microsoft'].includes(item.provider)
    );
    if (connections.value.length && !selectedConnectionId.value) {
      selectedConnectionId.value = String(connections.value[0].id);
    }
    if (!connections.value.length) {
      calendarsReady.value = true;
    }
  } catch (error) {
    calendarsReady.value = true;
    useAlert(t('SIDEBAR.CALENDAR_PAGE.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

const loadCalendars = async () => {
  if (!selectedConnectionId.value) {
    calendars.value = [];
    selectedCalendarId.value = '';
    calendarsReady.value = true;
    return;
  }
  calendarsReady.value = false;
  try {
    const { data } = await CalendarAPI.getCalendars(selectedConnectionId.value);
    calendars.value = (data.payload || []).filter(
      item => item.enabled !== false
    );
    const current = calendars.value.find(
      item => item.id === selectedCalendarId.value
    );
    selectedCalendarId.value = current?.id || calendars.value[0]?.id || '';
  } catch (error) {
    calendars.value = [];
    useAlert(t('SIDEBAR.CALENDAR_PAGE.LOAD_ERROR'));
  } finally {
    calendarsReady.value = true;
  }
};

const loadEvents = async ({ silent = false, keepEvent = null } = {}) => {
  if (!selectedConnectionId.value || !selectedCalendarId.value) {
    events.value = [];
    return;
  }
  if (!silent) loadingEvents.value = true;
  try {
    const bounds = weekBoundsIso(weekStartKey.value);
    const { data } = await CalendarAPI.getEvents({
      connectionId: selectedConnectionId.value,
      calendarId: selectedCalendarId.value,
      timeMin: bounds.timeMin,
      timeMax: bounds.timeMax,
    });
    let next = [...(data.payload || [])];
    if (keepEvent?.id && !next.some(item => item.id === keepEvent.id)) {
      next.push(keepEvent);
    }
    events.value = next;
  } catch (error) {
    if (!silent) {
      events.value = [];
      useAlert(t('SIDEBAR.CALENDAR_PAGE.LOAD_ERROR'));
    }
  } finally {
    if (!silent) loadingEvents.value = false;
  }
};

const applySavedEvent = event => {
  if (!event?.id) return;
  const idx = events.value.findIndex(item => item.id === event.id);
  if (idx >= 0) {
    events.value.splice(idx, 1, { ...events.value[idx], ...event });
  } else {
    events.value = [...events.value, event];
  }
};

const onSaved = async event => {
  applySavedEvent(event);
  await loadEvents({ silent: true, keepEvent: event });
};

const goToSettings = () => {
  router.push(accountScopedRoute('settings_integrations_calendars'));
};

const openCreate = slot => {
  modalRef.value?.open({
    defaults: {
      connectionId: selectedConnectionId.value,
      calendarId: selectedCalendarId.value,
      dateKey: slot.dateKey,
      hours: slot.hours,
      minutes: slot.minutes,
      hideConversation: true,
    },
  });
};

const openEvent = event => {
  modalRef.value?.open({
    event,
    defaults: {
      connectionId: selectedConnectionId.value,
      calendarId: selectedCalendarId.value,
      hideConversation: true,
    },
  });
};

watch(selectedConnectionId, () => {
  loadCalendars();
});

watch([selectedCalendarId, weekStartKey], () => {
  loadEvents();
});

onMounted(loadConnections);
</script>

<template>
  <section class="flex flex-col w-full h-full min-w-0 bg-n-surface-1">
    <header
      class="flex items-start justify-between gap-4 px-6 py-3 border-b border-n-weak min-w-0"
    >
      <h1 class="text-lg font-medium text-n-slate-12 shrink-0 pt-1">
        {{ $t('SIDEBAR.CALENDAR_PAGE.TITLE') }}
      </h1>
      <div
        v-if="hasConnections"
        class="ml-auto flex flex-wrap items-end justify-end gap-2 min-w-0 max-w-full"
      >
        <div class="w-44 shrink-0">
          <OutlinedAttributeField
            :label="$t('SIDEBAR.CALENDAR_PAGE.ACCOUNT')"
            filled
            :focused="showAccountMenu"
          >
            <div
              v-on-click-outside="() => (showAccountMenu = false)"
              class="relative flex items-center w-full min-h-8 gap-1.5 cursor-pointer"
              :class="{ 'z-50': showAccountMenu }"
            >
              <button
                type="button"
                class="flex w-full items-center gap-1.5 min-w-0"
                :aria-expanded="showAccountMenu"
                :aria-label="$t('SIDEBAR.CALENDAR_PAGE.ACCOUNT')"
                @click="showAccountMenu = !showAccountMenu"
              >
                <img
                  :src="providerLogoFor(selectedConnection?.provider)"
                  alt=""
                  class="size-4 shrink-0 rounded-sm"
                />
                <span class="flex-1 truncate text-left text-sm text-n-slate-12">
                  {{ selectedConnectionLabel }}
                </span>
                <span
                  class="i-lucide-chevron-down size-3.5 shrink-0 text-n-slate-11"
                  :class="{ 'rotate-180': showAccountMenu }"
                />
              </button>
              <div
                v-if="showAccountMenu"
                class="absolute z-50 mt-1 top-full ltr:left-0 rtl:right-0 w-full min-w-[14rem] overflow-hidden rounded-xl border border-n-weak bg-n-solid-2 py-1 shadow-lg"
              >
                <button
                  v-for="connection in connections"
                  :key="connection.id"
                  type="button"
                  class="flex w-full items-center gap-2 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-2"
                  :class="{
                    'bg-n-alpha-2':
                      String(connection.id) === selectedConnectionId,
                  }"
                  @click="selectConnection(connection.id)"
                >
                  <img
                    :src="providerLogoFor(connection.provider)"
                    alt=""
                    class="size-4 shrink-0 rounded-sm"
                  />
                  <span class="truncate">
                    {{ connectionDisplayName(connection, t) }}
                  </span>
                </button>
              </div>
            </div>
          </OutlinedAttributeField>
        </div>
        <div class="w-44 shrink-0">
          <OutlinedSelectField
            :label="$t('SIDEBAR.CALENDAR_PAGE.CALENDAR')"
            :options="calendarOutlineOptions"
            :selected-item="selectedCalendarItem"
            :show-search="false"
            :disabled="!calendars.length"
            @select="onCalendarSelect"
          />
        </div>
        <div class="flex items-center gap-1 shrink-0">
          <Button
            icon="i-lucide-chevron-left"
            faded
            slate
            sm
            :title="$t('SIDEBAR.CALENDAR_PAGE.PREV_WEEK')"
            @click="weekStartKey = addDaysKey(weekStartKey, -7)"
          />
          <span class="px-2 text-sm text-n-slate-12 whitespace-nowrap">
            {{ weekLabel }}
          </span>
          <Button
            icon="i-lucide-chevron-right"
            faded
            slate
            sm
            :title="$t('SIDEBAR.CALENDAR_PAGE.NEXT_WEEK')"
            @click="weekStartKey = addDaysKey(weekStartKey, 7)"
          />
          <Button
            faded
            slate
            sm
            :label="$t('SIDEBAR.CALENDAR_PAGE.THIS_WEEK')"
            @click="weekStartKey = startOfWeekKey()"
          />
          <Button
            blue
            sm
            icon="i-lucide-plus"
            :label="$t('SIDEBAR.CALENDAR_PAGE.NEW_EVENT')"
            :disabled="!selectedCalendarId"
            @click="openCreate({ dateKey: weekStartKey, hours: 9, minutes: 0 })"
          />
          <div v-on-click-outside="() => (showMenu = false)" class="relative">
            <Button
              faded
              slate
              sm
              icon="i-lucide-ellipsis-vertical"
              :title="$t('SIDEBAR.CALENDAR_PAGE.SHOW_CANCELLED')"
              @click="showMenu = !showMenu"
            />
            <div
              v-if="showMenu"
              class="absolute z-50 mt-1 ltr:right-0 rtl:left-0 w-64 rounded-xl border border-n-weak bg-n-solid-2 p-3 shadow-lg"
            >
              <label
                class="flex items-center justify-between gap-3 text-sm text-n-slate-12"
              >
                {{ $t('SIDEBAR.CALENDAR_PAGE.SHOW_CANCELLED') }}
                <Switch v-model="showCancelled" />
              </label>
            </div>
          </div>
        </div>
      </div>
    </header>

    <div v-if="!showGrid" class="flex-1 bg-n-surface-1">
      <div class="flex items-center justify-center h-full">
        <Spinner />
      </div>
    </div>

    <div
      v-else-if="!hasConnections"
      class="flex flex-col items-center justify-center flex-1 gap-4 px-6 text-center"
    >
      <p class="text-sm text-n-slate-11 max-w-md">
        {{ $t('SIDEBAR.CALENDAR_PAGE.EMPTY') }}
      </p>
      <Button
        v-if="isAdmin"
        blue
        :label="$t('SIDEBAR.CALENDAR_PAGE.CONNECT_CTA')"
        @click="goToSettings"
      />
    </div>

    <div
      v-else-if="!hasEnabledCalendars"
      class="flex flex-col items-center justify-center flex-1 gap-4 px-6 text-center"
    >
      <p class="text-sm text-n-slate-11 max-w-md">
        {{ $t('SIDEBAR.CALENDAR_PAGE.EMPTY_CALENDARS') }}
      </p>
      <Button
        v-if="isAdmin"
        blue
        :label="$t('SIDEBAR.CALENDAR_PAGE.ENABLE_CTA')"
        @click="goToSettings"
      />
    </div>

    <div v-else class="flex flex-1 min-h-0">
      <AgendaSidebar :groups="groupedEvents" @event-click="openEvent" />
      <div class="flex flex-col flex-1 min-h-0 min-w-0">
        <WeekGrid
          :week-start-key="weekStartKey"
          :events="visibleEvents"
          :hour-start="hourStart"
          :hour-end="hourEnd"
          @slot-click="openCreate"
          @event-click="openEvent"
        />
        <div class="md:hidden flex-1 overflow-auto px-4 py-4">
          <div class="flex flex-col gap-4">
            <section
              v-for="group in groupedEvents"
              :key="group.key"
              class="rounded-xl border border-n-weak bg-n-card p-4"
            >
              <h2 class="text-sm font-medium text-n-slate-12 capitalize mb-3">
                {{ group.label }}
              </h2>
              <p v-if="!group.events.length" class="text-sm text-n-slate-10">
                {{ $t('SIDEBAR.CALENDAR_PAGE.NO_EVENTS') }}
              </p>
              <div v-else class="flex flex-col gap-0.5">
                <button
                  v-for="event in group.events"
                  :key="event.id"
                  type="button"
                  class="flex w-full items-start gap-2 rounded-lg px-2 py-2 text-left"
                  :class="
                    event.deleted
                      ? 'bg-n-ruby-3/50 hover:bg-n-ruby-4'
                      : 'hover:bg-n-alpha-2'
                  "
                  @click="openEvent(event)"
                >
                  <span
                    class="mt-1.5 size-2 shrink-0 rounded-full"
                    :class="event.deleted ? 'bg-n-ruby-9' : 'bg-n-blue-9'"
                    aria-hidden="true"
                  />
                  <span class="min-w-0 flex-1">
                    <span
                      v-if="event.deleted"
                      class="block text-[10px] font-medium text-n-ruby-11"
                    >
                      {{ $t('SIDEBAR.CALENDAR_PAGE.DELETED') }}
                    </span>
                    <span
                      class="block text-sm truncate"
                      :class="
                        event.deleted
                          ? 'text-n-ruby-11 line-through'
                          : 'text-n-slate-12'
                      "
                    >
                      {{ event.summary }}
                    </span>
                    <span
                      class="block text-xs truncate"
                      :class="
                        event.deleted ? 'text-n-ruby-11/80' : 'text-n-slate-11'
                      "
                    >
                      {{
                        event.all_day
                          ? $t('SIDEBAR.CALENDAR_PAGE.ALL_DAY')
                          : formatTime(event.start)
                      }}
                      <template
                        v-if="event.deleted_by?.name || event.created_by?.name"
                      >
                        · {{ event.deleted_by?.name || event.created_by.name }}
                      </template>
                    </span>
                    <span
                      v-if="event.deleted && event.deleted_note"
                      class="block text-xs text-n-ruby-11 truncate"
                    >
                      {{ event.deleted_note }}
                    </span>
                  </span>
                </button>
              </div>
            </section>
          </div>
        </div>
      </div>
    </div>

    <EventModal
      ref="modalRef"
      :connections="connections"
      :calendars="calendars"
      @saved="onSaved"
    />
  </section>
</template>
