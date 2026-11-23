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
  const drafts = ref(null);
  const kit = ref(null);
  const loading = reactive({
    connections: false,
    calendars: false,
    assistants: false,
    messages: false,
  });
  const errors = reactive({
    connections: false,
    calendars: false,
    assistants: false,
    messages: false,
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
  const loadCalendars = () =>
    run('calendars', async () => {
      const responses = await Promise.all(
        connections.value.map(async connection => {
          const { data } = await CalendarAPI.getCalendars(connection.id);
          return data.payload.map(calendar => ({ ...calendar, connection }));
        })
      );
      calendars.value = responses.flat();
    });
  const loadConnections = () =>
    run('connections', async () => {
      const data = await store.dispatch(
        'calendarConnections/get',
        accountId.value
      );
      connections.value = data.payload.filter(
        connection => connection.provider === 'google'
      );
      await loadCalendars();
    });
  const loadAssistants = () =>
    run('assistants', async () => {
      if (!captainEnabled()) return;
      const { data } = await AssistantAPI.get();
      assistants.value = data.payload;
    });
  const loadMessages = () =>
    run('messages', async () => {
      const [templates, activation] = await Promise.all([
        CalendarAPI.getTemplateDrafts(),
        CalendarAPI.getActivationKit(),
      ]);
      drafts.value = templates.data;
      kit.value = activation.data;
    });
  const load = () =>
    Promise.all([loadConnections(), loadAssistants(), loadMessages()]);
  const withoutCalendar = computed(() =>
    assistants.value.filter(
      assistant =>
        !calendars.value.some(calendar => usesCalendar(assistant, calendar))
    )
  );
  const previouslyConfigured = computed(() =>
    Boolean(
      drafts.value?.prepared_language ||
        Object.values(drafts.value?.results || {}).some(
          result => result.draft_exists
        ) ||
        assistants.value.some(
          assistant => assistant.config?.appointments?.calendar_id
        )
    )
  );
  return {
    connections,
    calendars,
    assistants,
    withoutCalendar,
    drafts,
    kit,
    loading,
    errors,
    load,
    previouslyConfigured,
  };
}
