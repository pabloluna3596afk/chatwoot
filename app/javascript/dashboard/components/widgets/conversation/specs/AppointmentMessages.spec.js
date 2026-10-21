import { flushPromises, shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversation.json';
import es from 'dashboard/i18n/locale/es/conversation.json';
import enSettings from 'dashboard/i18n/locale/en/settings.json';
import esSettings from 'dashboard/i18n/locale/es/settings.json';
import NextAppointmentCard from '../NextAppointmentCard.vue';
import CalendarEventsList from '../CalendarEventsList.vue';

const { fetchEvents } = vi.hoisted(() => ({ fetchEvents: vi.fn() }));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    getContactEvents: fetchEvents,
    getConversationEvents: fetchEvents,
    getConnections: vi.fn().mockResolvedValue({ data: { payload: [] } }),
  },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(1),
    currentAccount: ref({}),
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

it('keeps the calendar message keys in parity in English and Spanish', () => {
  expect(Object.keys(en.CONVERSATION_SIDEBAR.CALENDAR).sort()).toEqual(
    Object.keys(es.CONVERSATION_SIDEBAR.CALENDAR).sort()
  );
  ['STATUS', 'INVITATION'].forEach(group => {
    expect(Object.keys(en.CONVERSATION_SIDEBAR.CALENDAR[group]).sort()).toEqual(
      Object.keys(es.CONVERSATION_SIDEBAR.CALENDAR[group]).sort()
    );
  });
});
it.each([
  ['en', NextAppointmentCard],
  ['es', NextAppointmentCard],
  ['en', CalendarEventsList],
  ['es', CalendarEventsList],
])(
  'renders localized error, retry and genuine empty in %s',
  async (locale, component) => {
    fetchEvents
      .mockRejectedValueOnce(new Error('HTTP 503'))
      .mockResolvedValueOnce({ data: { payload: [] } });
    const messages = {
      en: { ...en, ...enSettings },
      es: { ...es, ...esSettings },
    };
    const text = messages[locale].CONVERSATION_SIDEBAR.CALENDAR;
    const wrapper = shallowMount(component, {
      props: {
        contactId: 7,
        ...(component === CalendarEventsList ? { conversationId: 9 } : {}),
      },
      global: { plugins: [createI18n({ legacy: false, locale, messages })] },
    });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(text.LOAD_ERROR);
    expect(wrapper.text()).not.toContain(text.EMPTY);
    const retry = wrapper.findAllComponents({ name: 'Button' }).at(-1);
    expect(retry.props('label')).toBe(text.RETRY);
    retry.vm.$emit('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      component === NextAppointmentCard ? text.NEXT_EMPTY : text.EMPTY
    );
    wrapper.unmount();
  }
);
