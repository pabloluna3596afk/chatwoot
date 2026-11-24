import { computed, reactive, ref } from 'vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import AssistantAPI from 'dashboard/api/captain/assistant';

export const usesCalendar = (assistant, calendar) => {
  const appointments = assistant.config?.appointments;
  return (
    String(appointments?.calendar_connection_id) ===
      String(calendar.connection.id) &&
    appointments?.calendar_id === calendar.id
  );
};

export function useCitasPanel({ store, accountId, captainEnabled }) {
  const connections = ref([]);
  const calendars = ref([]);
  const assistants = ref([]);
  const attributes = ref(null);
  const loading = reactive({
    connections: false,
    calendars: false,
    assistants: false,
    attributes: false,
  });
  const errors = reactive({
    connections: false,
    calendars: false,
    assistants: false,
    attributes: false,
  });
  const run = async (section, action) => {
    loading[section] = true;
    errors[section] = false;
    try {
      await action();
    } catch {
      errors[section] = true;
    } finally {
      loading[section] = false;
    }
  };
  const calendarErrors = reactive({});
  const calendarLoading = reactive({});
  const loadCalendar = connection => {
    calendarLoading[connection.id] = true;
    return CalendarAPI.getCalendars(connection.id)
      .then(({ data }) => {
        calendarErrors[connection.id] = false;
        calendars.value = [
          ...calendars.value.filter(
            item => item.connection.id !== connection.id
          ),
          ...data.payload.map(calendar => ({ ...calendar, connection })),
        ];
      })
      .catch(() => {
        calendarErrors[connection.id] = true;
      })
      .finally(() => {
        calendarLoading[connection.id] = false;
      });
  };
  const loadCalendars = () =>
    run('calendars', () =>
      Promise.allSettled(connections.value.map(loadCalendar))
    );
  const loadConnections = () =>
    run('connections', async () => {
      const data = await store.dispatch(
        'calendarConnections/get',
        accountId.value
      );
      connections.value = data.payload.filter(
        connection => connection.provider === 'google'
      );
    });
  const loadAssistants = () =>
    run('assistants', async () => {
      if (!captainEnabled()) return;
      const { data } = await AssistantAPI.get();
      assistants.value = data.payload;
    });
  const loadAttributes = () =>
    run('attributes', async () => {
      const { data } = await CalendarAPI.getAppointmentAttributes();
      attributes.value = data;
    });
  const withoutCalendar = computed(() =>
    assistants.value.filter(
      assistant =>
        !calendars.value.some(calendar => usesCalendar(assistant, calendar))
    )
  );
  return {
    connections,
    calendars,
    assistants,
    withoutCalendar,
    attributes,
    loading,
    errors,
    loadConnections,
    loadCalendars,
    loadCalendar,
    loadAssistants,
    loadAttributes,
    calendarErrors,
    calendarLoading,
  };
}
