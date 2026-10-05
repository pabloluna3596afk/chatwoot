import { flushPromises, shallowMount } from '@vue/test-utils';
import EventModal from '../EventModal.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'es' } }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { name: 'Pablo' } }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: { name: 'Clínica Sol' } } }),
}));

vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    lockEvent: vi.fn().mockResolvedValue({}),
    unlockEvent: vi.fn(),
    getInvitation: vi.fn().mockResolvedValue({ data: {} }),
  },
}));

const mountModal = (props = {}) =>
  shallowMount(EventModal, {
    props: {
      connections: [{ id: 1, email: 'a@b.c' }],
      calendars: [],
      ...props,
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Dialog: {
          template: '<div><slot /></div>',
          methods: { open() {}, close() {} },
        },
        TabBar: true,
      },
    },
  });

const followupOptions = wrapper =>
  wrapper.findAll('input[type="radio"]').map(input => input.element.value);

const openWithConversation = async wrapper => {
  await wrapper.vm.open({
    defaults: { connectionId: '1', calendarId: 'cal-1', conversationId: 9 },
  });
  await flushPromises();
};

describe('EventModal customer notification', () => {
  it('offers the AI bot follow-up only when an AI bot is active', async () => {
    const without = mountModal({ panelAiActive: false });
    await openWithConversation(without);
    expect(followupOptions(without)).toEqual(['none', 'notice_only']);

    const withBot = mountModal({ panelAiActive: true });
    await openWithConversation(withBot);
    expect(followupOptions(withBot)).toEqual([
      'none',
      'notice_only',
      'bot_followup',
    ]);
  });

  it('keeps the AI bot follow-up as the default of a new appointment only with an AI bot', async () => {
    const withBot = mountModal({ panelAiActive: true });
    await openWithConversation(withBot);
    expect(withBot.find('input[value="bot_followup"]').element.checked).toBe(
      true
    );

    const without = mountModal({ panelAiActive: false });
    await openWithConversation(without);
    expect(without.find('input[value="none"]').element.checked).toBe(true);
  });

  it('keeps showing the follow-up of an appointment that already has it', async () => {
    const wrapper = mountModal({ panelAiActive: false });
    await wrapper.vm.open({
      event: {
        id: 'e1',
        summary: 'Cita',
        start: '2030-01-15T10:00:00-05:00',
        end: '2030-01-15T10:30:00-05:00',
        connection_id: 1,
        calendar_id: 'cal-1',
        conversation: { id: 9 },
        bot_followup_policy: { enabled: true, confirmation: true },
      },
      defaults: {},
    });
    await flushPromises();

    expect(followupOptions(wrapper)).toContain('bot_followup');
  });

  it('explains every option and that Captain handles its own appointments', async () => {
    const wrapper = mountModal({ panelAiActive: false });
    await openWithConversation(wrapper);

    expect(wrapper.text()).toContain(
      'SIDEBAR.CALENDAR_PAGE.MODAL.FOLLOWUP_CAPTAIN_NOTE'
    );
    expect(wrapper.text()).toContain(
      'SIDEBAR.CALENDAR_PAGE.MODAL.FOLLOWUP_NONE_HELP'
    );
    expect(wrapper.text()).toContain(
      'SIDEBAR.CALENDAR_PAGE.MODAL.FOLLOWUP_NOTICE_HELP'
    );
  });
});
