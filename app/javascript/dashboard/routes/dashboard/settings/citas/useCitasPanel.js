import { computed, reactive, ref } from 'vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import AssistantAPI from 'dashboard/api/captain/assistant';

export const TEMPLATE_STATES = [
  'approved',
  'review',
  'rejected',
  'failed',
  'unsent',
];
const STATE_PRIORITY = ['approved', 'review', 'unsent', 'rejected', 'failed'];
const PENDING_SUBMISSION_STATUSES = ['submitting', 'reconciling', 'submitted'];
const REJECTED_REASONS = [
  'rejected',
  'paused',
  'disabled',
  'category',
  'status',
];

export const mapTemplateState = destination => {
  const submission = destination?.submission || {};
  const remoteStatus = submission.remote_status;
  if (destination?.state === 'usable' || remoteStatus === 'APPROVED')
    return 'approved';
  if (
    destination?.state === 'pending_approval' ||
    PENDING_SUBMISSION_STATUSES.includes(submission.status) ||
    ['PENDING', 'IN_APPEAL'].includes(remoteStatus)
  )
    return 'review';
  if (
    submission.status === 'failed' ||
    destination?.state === 'submission_failed' ||
    (destination?.state === 'not_submitted' && submission.status === 'failed')
  )
    return 'failed';
  if (
    destination?.state === 'incompatible' &&
    (REJECTED_REASONS.includes(submission.remote_status?.toLowerCase()) ||
      REJECTED_REASONS.includes(destination.reason))
  )
    return 'rejected';
  return 'unsent';
};

export const aggregateState = states =>
  [...states].sort(
    (left, right) =>
      STATE_PRIORITY.indexOf(right) - STATE_PRIORITY.indexOf(left)
  )[0] || 'unsent';

export const buildTemplateState = data => {
  const results = data?.results || {};
  const keys = ['confirmation', 'cancellation', 'reminder'];
  const byWaba = new Map();
  keys.forEach(key => {
    (results[key]?.destinations || []).forEach(destination => {
      const wabaId = String(destination.waba_id);
      if (!byWaba.has(wabaId)) {
        const channels = destination.channels || [];
        byWaba.set(wabaId, {
          waba_id: wabaId,
          name: channels
            .map(channel => channel.name)
            .filter(Boolean)
            .join(', '),
          number: channels
            .map(channel => channel.phone_number)
            .filter(Boolean)
            .join(', '),
          templates: {},
        });
      }
      byWaba.get(wabaId).templates[key] = {
        state: mapTemplateState(destination),
        reason:
          destination.submission?.remote_reason || destination.reason || '',
        submission: destination.submission || null,
      };
    });
  });
  const accounts = [...byWaba.values()];
  const functions = keys.map(key => {
    const perWaba = accounts.map(account => ({
      waba_id: account.waba_id,
      name: account.name,
      number: account.number,
      ...(account.templates[key] || {
        state: 'unsent',
        reason: '',
        submission: null,
      }),
    }));
    const states = perWaba.map(item => item.state);
    return {
      key,
      perWaba,
      aggregate: aggregateState(states),
      counts: TEMPLATE_STATES.reduce(
        (counts, state) => ({
          ...counts,
          [state]: states.filter(item => item === state).length,
        }),
        {}
      ),
    };
  });
  return { functions, accounts };
};

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
  const templateState = ref({ functions: [], accounts: [] });
  const templateData = ref(null);
  const loading = reactive({
    connections: false,
    calendars: false,
    assistants: false,
    attributes: false,
    templates: false,
  });
  const errors = reactive({
    connections: false,
    calendars: false,
    assistants: false,
    attributes: false,
    templates: false,
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
  const loadTemplateState = () =>
    run('templates', async () => {
      const { data } = await CalendarAPI.getTemplateDrafts();
      templateData.value = data;
      templateState.value = buildTemplateState(data);
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
    templateState,
    templateData,
    loading,
    errors,
    loadConnections,
    loadCalendars,
    loadCalendar,
    loadAssistants,
    loadAttributes,
    loadTemplateState,
    calendarErrors,
    calendarLoading,
  };
}
