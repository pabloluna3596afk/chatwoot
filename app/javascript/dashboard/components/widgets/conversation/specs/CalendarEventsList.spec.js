import { flushPromises, shallowMount } from '@vue/test-utils';
import CalendarEventsList from '../CalendarEventsList.vue';
import { ref } from 'vue';

const { getConversationEvents, getConnections } = vi.hoisted(() => ({
  getConversationEvents: vi.fn(),
  getConnections: vi.fn(),
}));

vi.mock('dashboard/api/integrations/calendar', () => ({
  default: { getConversationEvents, getConnections, getCalendars: vi.fn() },
}));

vi.mock('dashboard/helper/useCalendarCancelledVisibility', () => ({
  useCalendarCancelledVisibility: () => ({ showCancelled: ref(true) }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: ref(1), currentAccount: ref({}) }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: ref({ calendar_timezone: 'America/Guayaquil' }),
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'es' } }),
}));

const future = days => new Date(Date.now() + days * 86400000).toISOString();

const events = [
  {
    id: 'next',
    summary: 'Próxima',
    start: future(2),
    end: future(2),
    creator: { type: 'captain', name: 'Aurora' },
  },
  { id: 'old', summary: 'Vieja', start: future(-5), end: future(-5) },
  {
    id: 'gone',
    summary: 'Cancelada',
    start: future(3),
    end: future(3),
    deleted: true,
  },
];

describe('CalendarEventsList', () => {
  it('shows its own error once, or stays quiet (never "no appointments") when the card already shows it', async () => {
    getConnections.mockResolvedValue({ data: { payload: [] } });
    getConversationEvents.mockRejectedValue(new Error('boom'));
    const mountList = errorShownElsewhere =>
      shallowMount(CalendarEventsList, {
        props: { conversationId: 1, errorShownElsewhere },
        global: {
          mocks: { $t: key => key },
          directives: { tooltip: {} },
          stubs: { EventModal: true },
        },
      });
    const alone = mountList(false);
    await flushPromises();
    expect(alone.text()).toContain('CONVERSATION_SIDEBAR.CALENDAR.LOAD_ERROR');
    const withCard = mountList(true);
    await flushPromises();
    expect(withCard.text()).not.toContain(
      'CONVERSATION_SIDEBAR.CALENDAR.LOAD_ERROR'
    );
    expect(withCard.text()).not.toContain(
      'CONVERSATION_SIDEBAR.CALENDAR.EMPTY'
    );
    getConversationEvents.mockResolvedValue({ data: { payload: [] } });
    await withCard.vm.refresh();
    expect(withCard.text()).toContain('CONVERSATION_SIDEBAR.CALENDAR.EMPTY');
  });

  it('splits upcoming from past, and keeps the past minimal', async () => {
    getConnections.mockResolvedValue({ data: { payload: [] } });
    getConversationEvents.mockResolvedValue({ data: { payload: events } });

    const wrapper = shallowMount(CalendarEventsList, {
      props: { conversationId: 1 },
      global: {
        mocks: { $t: key => key },
        directives: { tooltip: {} },
        stubs: { EventModal: true },
      },
    });
    await flushPromises();

    const headings = wrapper.findAll('h5').map(item => item.text());
    expect(headings).toEqual([
      'CONVERSATION_SIDEBAR.CALENDAR.UPCOMING',
      'CONVERSATION_SIDEBAR.CALENDAR.PAST',
    ]);
    const [upcoming, past] = wrapper.findAll('section');
    expect(upcoming.text()).toContain('America/Guayaquil');
    expect(upcoming.text()).toContain('Próxima');
    expect(
      upcoming.findComponent({ name: 'AppointmentCreatorAvatar' }).exists()
    ).toBe(true);
    expect(past.text()).toContain('Vieja');
    expect(past.text()).toContain('CONVERSATION_SIDEBAR.CALENDAR.PAST_BADGE');
    expect(past.text()).toContain('Cancelada');
    expect(past.text()).not.toContain('Próxima');
    wrapper
      .findComponent({ name: 'EventModal' })
      .vm.$emit('saved', { id: 'gone', deleted: true });
    await flushPromises();
    expect(wrapper.emitted('saved')[0]).toEqual([
      { id: 'gone', deleted: true },
    ]);
  });
});
