import { vi, describe, expect, it, beforeEach } from 'vitest';
import { flushPromises, shallowMount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import EventModal from '../EventModal.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import en from 'dashboard/i18n/locale/en/settings.json';
import es from 'dashboard/i18n/locale/es/settings.json';

const account = vi.hoisted(() => ({ value: {} }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: account }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    createEvent: vi.fn(),
    updateEvent: vi.fn(),
    lockEvent: vi.fn().mockResolvedValue({}),
    unlockEvent: vi.fn(),
    getInvitation: vi
      .fn()
      .mockResolvedValue({ data: { template: '{{fecha}} {{hora}}' } }),
  },
}));
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  fallbackLocale: 'en',
  messages: { en, es },
  missingWarn: false,
  fallbackWarn: false,
});
config.global.plugins = [i18n];
beforeEach(() => {
  CalendarAPI.getInvitation.mockResolvedValue({
    data: { template: '{{fecha}} {{hora}}' },
  });
  CalendarAPI.lockEvent.mockResolvedValue({});
});

const mountModal = () =>
  shallowMount(EventModal, {
    props: { connections: [{ id: 1 }], calendars: [] },
    global: {
      stubs: {
        Dialog: {
          name: 'Dialog',
          props: ['disableConfirmButton'],
          template: '<div><slot /></div>',
          methods: { open() {}, close() {} },
        },
      },
    },
  });

describe.each(['en', 'es'])('appointment timezone in %s', language => {
  it.each([
    ['America/Guayaquil', '2030-07-15T10:00:00-05:00'],
    ['America/New_York', '2030-07-15T10:00:00-04:00'],
  ])('creates, reloads and previews 10:00 in %s', async (timezone, start) => {
    account.value = { calendar_timezone: timezone };
    i18n.global.locale.value = language;
    CalendarAPI.createEvent.mockResolvedValue({ data: { payload: {} } });
    const wrapper = mountModal();
    await wrapper.vm.open({
      defaults: { connectionId: 1, calendarId: 'cal-1', startIso: start },
    });
    const inputs = wrapper.findAllComponents({ name: 'Input' });
    inputs[0].vm.$emit('update:modelValue', 'Consultation');
    await flushPromises();
    expect(
      inputs.find(input => input.props('type') === 'time').props('modelValue')
    ).toBe('10:00');
    expect(wrapper.text()).toContain(timezone);
    expect(wrapper.get('[data-testid="invitation-preview"]').text()).toContain(
      '10:00'
    );
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');
    await flushPromises();
    expect(CalendarAPI.createEvent).toHaveBeenCalledWith(
      expect.objectContaining({ start })
    );
    await wrapper.vm.open({
      event: {
        id: 'e',
        summary: 'Consultation',
        connection_id: 1,
        calendar_id: 'cal-1',
        start,
        end: start.replace('10:00', '10:30'),
      },
    });
    await flushPromises();
    expect(
      wrapper
        .findAllComponents({ name: 'Input' })
        .find(input => input.props('type') === 'time')
        .props('modelValue')
    ).toBe('10:00');
    wrapper.unmount();
  });

  it('blocks nonexistent DST times and retains the later occurrence when editing', async () => {
    account.value = { calendar_timezone: 'America/New_York' };
    i18n.global.locale.value = language;
    const wrapper = mountModal();
    await wrapper.vm.open({
      defaults: {
        connectionId: 1,
        calendarId: 'cal-1',
        dateKey: '2030-03-10',
        hours: 2,
        minutes: 30,
      },
    });
    wrapper
      .findAllComponents({ name: 'Input' })[0]
      .vm.$emit('update:modelValue', 'Consultation');
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'Dialog' }).props('disableConfirmButton')
    ).toBe(true);
    const event = {
      id: 'e',
      summary: 'Consultation',
      connection_id: 1,
      calendar_id: 'cal-1',
      start: '2030-11-03T01:30:00-05:00',
      end: '2030-11-03T02:00:00-05:00',
    };
    CalendarAPI.updateEvent.mockResolvedValue({ data: { payload: event } });
    await wrapper.vm.open({ event });
    await flushPromises();
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');
    await flushPromises();
    expect(CalendarAPI.updateEvent).toHaveBeenCalledWith(
      'e',
      expect.objectContaining({ start: event.start, end: event.end })
    );
    wrapper.unmount();
  });
  it('renders the activity date and clock in the account zone at New Year', async () => {
    account.value = { calendar_timezone: 'America/New_York' };
    i18n.global.locale.value = language;
    const wrapper = mountModal();
    await wrapper.vm.open({
      event: {
        id: 'e',
        summary: 'Consultation',
        connection_id: 1,
        calendar_id: 'cal-1',
        start: '2031-01-01T00:30:00Z',
        end: '2031-01-01T01:00:00Z',
        activities: [
          {
            id: 1,
            action: 'created',
            created_at: '2031-01-01T00:30:00Z',
            details: {},
          },
        ],
      },
    });
    wrapper
      .findComponent({ name: 'TabBar' })
      .vm.$emit('tabChanged', { value: 'activity' });
    await flushPromises();
    expect(wrapper.text()).toContain('19:30');
    expect(wrapper.text()).toContain('2030');
    wrapper.unmount();
  });
});
