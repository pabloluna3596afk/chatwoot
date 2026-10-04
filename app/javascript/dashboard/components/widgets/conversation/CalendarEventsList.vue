<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EventModal from 'dashboard/routes/dashboard/calendars/EventModal.vue';
import AppointmentCreatorAvatar from './AppointmentCreatorAvatar.vue';
import {
  formatEventWhen,
  isUpcomingEvent,
} from 'dashboard/helper/calendarTime';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  contactId: {
    type: [Number, String],
    default: null,
  },
  contactName: {
    type: String,
    default: '',
  },
});

const { t, locale } = useI18n();
const events = ref([]);
const connections = ref([]);
const panelAiActive = ref(false);
const calendars = ref([]);
const isLoading = ref(false);
const modalRef = ref(null);
const selectedConnectionId = ref('');

const hasEvents = computed(() => events.value.length > 0);
const upcomingEvents = computed(() =>
  events.value.filter(event => isUpcomingEvent(event))
);
// What already happened (or was cancelled) is kept short: title, date and that it is past.
const pastEvents = computed(() =>
  events.value.filter(event => !isUpcomingEvent(event)).reverse()
);

const loadConnections = async () => {
  const { data } = await CalendarAPI.getConnections();
  panelAiActive.value = Boolean(data.panel_ai_active);
  connections.value = (data.payload || []).filter(
    item => item.provider === 'google'
  );
  selectedConnectionId.value = connections.value[0]
    ? String(connections.value[0].id)
    : '';
  if (selectedConnectionId.value) {
    const calendarsResponse = await CalendarAPI.getCalendars(
      selectedConnectionId.value
    );
    calendars.value = calendarsResponse.data.payload || [];
  }
};

const loadEvents = async () => {
  isLoading.value = true;
  try {
    const { data } = await CalendarAPI.getConversationEvents(
      props.conversationId
    );
    events.value = data.payload || [];
  } catch (error) {
    events.value = [];
  } finally {
    isLoading.value = false;
  }
};

const openCreate = () => {
  modalRef.value?.open({
    defaults: {
      connectionId: selectedConnectionId.value,
      calendarId: calendars.value[0]?.id,
      conversationId: props.conversationId,
      contactId: props.contactId,
      contactName: props.contactName,
    },
  });
};

const openEvent = event => {
  modalRef.value?.open({
    event,
    defaults: {
      conversationId: props.conversationId,
      contactId: props.contactId,
      contactName: props.contactName,
    },
  });
};

watch(
  () => props.conversationId,
  () => {
    loadEvents();
  }
);

onMounted(async () => {
  try {
    await loadConnections();
  } catch (error) {
    useAlert(t('SIDEBAR.CALENDAR_PAGE.LOAD_ERROR'));
  }
  await loadEvents();
});
</script>

<template>
  <div>
    <div class="px-4 pt-3 pb-2">
      <Button
        ghost
        xs
        icon="i-lucide-plus"
        :label="$t('CONVERSATION_SIDEBAR.CALENDAR.NEW')"
        :disabled="!calendars.length"
        @click="openCreate"
      />
    </div>
    <div v-if="isLoading" class="flex justify-center p-8">
      <Spinner />
    </div>
    <div v-else-if="!hasEvents" class="flex justify-center p-4">
      <p class="text-sm text-n-slate-11">
        {{ $t('CONVERSATION_SIDEBAR.CALENDAR.EMPTY') }}
      </p>
    </div>
    <template v-else>
      <section v-if="upcomingEvents.length">
        <h5 class="px-4 pt-2 pb-1 m-0 text-xs font-medium text-n-slate-11">
          {{ $t('CONVERSATION_SIDEBAR.CALENDAR.UPCOMING') }}
        </h5>
        <ul class="max-h-[300px] overflow-y-auto list-none m-0 p-0">
          <li
            v-for="event in upcomingEvents"
            :key="event.id"
            class="px-4 py-3 border-b border-n-weak last:border-b-0"
          >
            <button
              type="button"
              class="w-full text-left"
              @click="openEvent(event)"
            >
              <p class="flex items-center gap-1.5 text-sm text-n-slate-12">
                <span class="flex-1 truncate">{{ event.summary }}</span>
                <AppointmentCreatorAvatar :creator="event.creator" />
              </p>
              <p
                v-if="
                  event.appointment_status &&
                  event.appointment_status !== 'none'
                "
                class="mt-0.5 text-[10px] font-medium uppercase tracking-wide text-n-blue-11"
              >
                {{
                  $t(
                    `CONVERSATION_SIDEBAR.CALENDAR.STATUS.${String(event.appointment_status).toUpperCase()}`
                  )
                }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ formatEventWhen(event.start, locale) }}
              </p>
            </button>
          </li>
        </ul>
      </section>
      <section v-if="pastEvents.length">
        <h5 class="px-4 pt-3 pb-1 m-0 text-xs font-medium text-n-slate-11">
          {{ $t('CONVERSATION_SIDEBAR.CALENDAR.PAST') }}
        </h5>
        <ul class="max-h-[200px] overflow-y-auto list-none m-0 p-0">
          <li
            v-for="event in pastEvents"
            :key="event.id"
            class="px-4 py-2 border-b border-n-weak last:border-b-0"
            :class="{ 'bg-n-ruby-3/40': event.deleted }"
          >
            <button
              type="button"
              class="w-full text-left"
              @click="openEvent(event)"
            >
              <p
                class="text-sm truncate"
                :class="
                  event.deleted
                    ? 'text-n-ruby-11 line-through'
                    : 'text-n-slate-11'
                "
              >
                {{ event.summary }}
              </p>
              <p
                class="text-xs"
                :class="event.deleted ? 'text-n-ruby-11/80' : 'text-n-slate-10'"
              >
                {{ formatEventWhen(event.start, locale) }} ·
                {{
                  event.deleted
                    ? $t('CONVERSATION_SIDEBAR.CALENDAR.DELETED')
                    : $t('CONVERSATION_SIDEBAR.CALENDAR.PAST_BADGE')
                }}
              </p>
              <p
                v-if="event.deleted && event.deleted_note"
                class="text-xs text-n-ruby-11 truncate"
              >
                {{ event.deleted_note }}
              </p>
            </button>
          </li>
        </ul>
      </section>
    </template>
    <EventModal
      ref="modalRef"
      :connections="connections"
      :calendars="calendars"
      :panel-ai-active="panelAiActive"
      @saved="loadEvents"
    />
  </div>
</template>
