import { flushPromises, shallowMount } from '@vue/test-utils';
import EventModal from '../EventModal.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      key.endsWith('_CHANGED') ? `${values.from} \u2192 ${values.to}` : key,
    locale: { value: 'es' },
  }),
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
    createEvent: vi.fn(),
    updateEvent: vi.fn(),
    lockEvent: vi.fn().mockResolvedValue({}),
    unlockEvent: vi.fn(),
    getCalendars: vi.fn().mockImplementation(async () => ({
      data: { payload: [{ id: 'cal-1' }] },
    })),
    getInvitation: vi.fn().mockResolvedValue({ data: {} }),
  },
}));

beforeEach(() => {
  CalendarAPI.getCalendars.mockResolvedValue({
    data: { payload: [{ id: 'cal-1' }] },
  });
});

const mountModal = (props = {}) =>
  shallowMount(EventModal, {
    props: {
      connections: [{ id: 1, email: 'a@b.c' }],

      ...props,
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Dialog: {
          name: 'Dialog',
          props: ['showConfirmButton'],
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

describe('EventModal appointment status', () => {
  it('offers confirmed and pending through ComboBox and sends the selected status', async () => {
    CalendarAPI.createEvent.mockResolvedValue({ data: { payload: {} } });
    const wrapper = mountModal();
    await wrapper.vm.open({
      defaults: {
        connectionId: '1',
        calendarId: 'cal-1',
        start: '2030-01-15T10:00:00-05:00',
      },
    });
    const status = wrapper
      .findAllComponents(ComboBox)
      .find(combo => combo.attributes('data-testid') === 'appointment-status');
    expect(status.props('options').map(option => option.value)).toEqual([
      'confirmed',
      'pending_confirmation',
    ]);
    expect(wrapper.find('select').exists()).toBe(false);
    status.vm.$emit('update:modelValue', 'pending_confirmation');
    wrapper
      .findAllComponents({ name: 'Input' })
      .find(
        input => input.props('label') === 'SIDEBAR.CALENDAR_PAGE.MODAL.TITLE'
      )
      .vm.$emit('update:modelValue', 'Consultation');
    await flushPromises();
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');
    await flushPromises();
    expect(CalendarAPI.createEvent).toHaveBeenCalledWith(
      expect.objectContaining({ appointment_status: 'pending_confirmation' })
    );
    wrapper.unmount();
  });

  it('keeps legacy status-only cancellations read-only', async () => {
    const wrapper = mountModal();
    await wrapper.vm.open({
      event: {
        id: 'cancelled',
        summary: 'Consultation',
        appointment_status: 'cancelled',
        connection_id: 1,
        calendar_id: 'cal-1',
        start: '2030-01-15T10:00:00-05:00',
        end: '2030-01-15T10:30:00-05:00',
      },
      defaults: {},
    });
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'Dialog' }).props('showConfirmButton')
    ).toBe(false);
    expect(CalendarAPI.lockEvent).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});

it('shows localized status and full date changes in the activity tab without broken text', async () => {
  const wrapper = mountModal();
  await wrapper.vm.open({
    event: {
      id: 'history',
      summary: 'Consultation',
      appointment_status: 'confirmed',
      connection_id: 1,
      calendar_id: 'cal-1',
      start: '2030-01-15T10:00:00-05:00',
      end: '2030-01-15T10:30:00-05:00',
      activities: [
        {
          id: 1,
          action: 'updated',
          created_at: '2030-01-14T09:00:00-05:00',
          details: {
            start_at: [
              '2030-01-15T10:00:00-05:00',
              '2030-01-16T11:00:00-05:00',
            ],
            appointment_status: ['pending_confirmation', 'confirmed'],
          },
        },
      ],
    },
    defaults: {},
  });
  wrapper
    .findComponent({ name: 'TabBar' })
    .vm.$emit('tabChanged', { value: 'activity' });
  await flushPromises();
  expect(wrapper.text()).toContain('2030');
  expect(wrapper.text()).toContain('10:00');
  expect(wrapper.text()).toContain('11:00');
  expect(wrapper.text()).toContain('\u2192');
  expect(wrapper.text()).toContain(
    'SIDEBAR.CALENDAR_PAGE.STATUS.PENDING_CONFIRMATION'
  );
  expect(wrapper.text()).toContain('SIDEBAR.CALENDAR_PAGE.STATUS.CONFIRMED');
  wrapper.unmount();
});
