import { flushPromises, shallowMount } from '@vue/test-utils';
import CalendarEventsList from '../CalendarEventsList.vue';

const { getConversationEvents, getConnections } = vi.hoisted(() => ({
  getConversationEvents: vi.fn(),
  getConnections: vi.fn(),
}));

vi.mock('dashboard/api/integrations/calendar', () => ({
  default: { getConversationEvents, getConnections, getCalendars: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

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
    expect(upcoming.text()).toContain('Próxima');
    expect(
      upcoming.findComponent({ name: 'AppointmentCreatorAvatar' }).exists()
    ).toBe(true);
    expect(past.text()).toContain('Vieja');
    expect(past.text()).toContain('CONVERSATION_SIDEBAR.CALENDAR.PAST_BADGE');
    expect(past.text()).toContain('Cancelada');
    expect(past.text()).not.toContain('Próxima');
  });
});
