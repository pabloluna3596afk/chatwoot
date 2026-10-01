import { flushPromises, mount } from '@vue/test-utils';
import AssistantAppointmentsForm from './AssistantAppointmentsForm.vue';

const { getConnections, getCalendars, inboxes } = vi.hoisted(() => ({
  getConnections: vi.fn(),
  getCalendars: vi.fn(),
  inboxes: { value: [] },
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => inboxes,
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    locale: { value: 'en' },
    t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
  }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));

vi.mock('dashboard/api/integrations/calendar', () => ({
  default: { getConnections, getCalendars },
}));

const CONNECTIONS = [{ id: 7, email: 'agenda@example.com', name: 'Agenda' }];
const CALENDARS = [
  {
    id: 'cal-1',
    summary: 'Consultas',
    hour_start: 9,
    hour_end: 18,
    working_days: [1, 2, 3, 4, 5],
  },
  { id: 'cal-2', summary: 'Otro', hour_start: 8, hour_end: 20 },
];

const mountForm = async (
  assistant = { config: { response_window: 'always' } }
) => {
  const wrapper = mount(AssistantAppointmentsForm, {
    props: { assistant },
    global: {
      stubs: {
        RouterLink: {
          props: ['to'],
          template: '<a data-testid="calendar-link"><slot /></a>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const toggle = wrapper => wrapper.get('button[role="switch"]').trigger('click');
const select = (wrapper, testId) =>
  wrapper.get(`[data-testid="${testId}"] select`);

const REMINDER_DEFAULTS = {
  send_confirmation: true,
  reminder_24h: true,
  reminder_2h: true,
  allow_paid_templates: false,
  template_confirmation: null,
  template_reminder: null,
  template_cancelled: null,
};

describe('AssistantAppointmentsForm', () => {
  beforeEach(() => {
    inboxes.value = [];
    getConnections
      .mockReset()
      .mockResolvedValue({ data: { payload: CONNECTIONS } });
    getCalendars
      .mockReset()
      .mockResolvedValue({ data: { payload: CALENDARS } });
  });

  it('points to the calendars integration when the account has no calendar connected', async () => {
    getConnections.mockResolvedValue({ data: { payload: [] } });
    const wrapper = await mountForm();

    expect(
      wrapper.find('[data-testid="appointments-no-calendar"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="calendar-link"]').exists()).toBe(true);
    expect(wrapper.find('button[role="switch"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="appointments-save"]').exists()).toBe(
      false
    );
  });

  it('is off by default and shows the fields only when switched on', async () => {
    const wrapper = await mountForm();

    expect(wrapper.find('[data-testid="appointments-fields"]').exists()).toBe(
      false
    );
    await toggle(wrapper);

    expect(wrapper.find('[data-testid="appointments-fields"]').exists()).toBe(
      true
    );
  });

  it('saves the disabled defaults and keeps the rest of the config', async () => {
    const wrapper = await mountForm({
      config: { response_window: 'always', product_name: 'Acme' },
    });

    await wrapper.get('[data-testid="appointments-save"]').trigger('click');

    expect(wrapper.emitted('submit')[0][0]).toEqual({
      config: {
        response_window: 'always',
        product_name: 'Acme',
        appointments: {
          enabled: false,
          calendar_connection_id: null,
          calendar_id: null,
          slot_duration_minutes: 30,
          required_contact_fields: ['name', 'phone', 'email'],
          min_notice_minutes: 60,
          booking_window_days: 14,
          ...REMINDER_DEFAULTS,
        },
      },
    });
  });

  it('asks for an account and a calendar before saving an enabled configuration', async () => {
    const wrapper = await mountForm();
    await toggle(wrapper);

    await wrapper.get('[data-testid="appointments-save"]').trigger('click');

    expect(wrapper.emitted('submit')).toBeUndefined();
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.ERRORS.CONNECTION'
    );
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.ERRORS.CALENDAR'
    );
  });

  it('loads the calendars of the chosen account and shows the calendar hours', async () => {
    const wrapper = await mountForm();
    await toggle(wrapper);

    await select(wrapper, 'appointments-connection').setValue(7);
    await flushPromises();
    expect(getCalendars).toHaveBeenCalledWith(7);

    await select(wrapper, 'appointments-calendar').setValue('cal-1');

    expect(
      wrapper.get('[data-testid="appointments-hours-hint"]').text()
    ).toContain('"start":"09:00","end":"18:00"');
  });

  it('lists the working days of the calendar, or says every day', async () => {
    const wrapper = await mountForm();
    await toggle(wrapper);
    await select(wrapper, 'appointments-connection').setValue(7);
    await flushPromises();

    await select(wrapper, 'appointments-calendar').setValue('cal-1');
    expect(
      wrapper.get('[data-testid="appointments-hours-hint"]').text()
    ).toContain('"days":"Mon, Tue, Wed, Thu, Fri"');

    await select(wrapper, 'appointments-calendar').setValue('cal-2');
    expect(
      wrapper.get('[data-testid="appointments-hours-hint"]').text()
    ).toContain('"days":"CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.EVERY_DAY"');
  });

  it('saves a full enabled configuration with numeric values', async () => {
    const wrapper = await mountForm();
    await toggle(wrapper);
    await select(wrapper, 'appointments-connection').setValue(7);
    await flushPromises();
    await select(wrapper, 'appointments-calendar').setValue('cal-2');
    await select(wrapper, 'appointments-duration').setValue(45);
    await select(wrapper, 'appointments-notice').setValue(120);
    await select(wrapper, 'appointments-window').setValue(30);
    await wrapper
      .get('[data-testid="appointments-field-phone"] input')
      .setValue(false);

    await wrapper.get('[data-testid="appointments-save"]').trigger('click');

    expect(wrapper.emitted('submit')[0][0].config.appointments).toEqual({
      enabled: true,
      calendar_connection_id: 7,
      calendar_id: 'cal-2',
      slot_duration_minutes: 45,
      required_contact_fields: ['name', 'email'],
      min_notice_minutes: 120,
      booking_window_days: 30,
      ...REMINDER_DEFAULTS,
    });
  });

  it('shows the saved configuration', async () => {
    const wrapper = await mountForm({
      config: {
        appointments: {
          enabled: true,
          calendar_connection_id: 7,
          calendar_id: 'cal-1',
          slot_duration_minutes: 60,
          required_contact_fields: ['phone'],
          min_notice_minutes: 240,
          booking_window_days: 7,
        },
      },
    });

    expect(getCalendars).toHaveBeenCalledWith(7);
    expect(select(wrapper, 'appointments-calendar').element.value).toBe(
      'cal-1'
    );
    expect(select(wrapper, 'appointments-duration').element.value).toBe('60');
    expect(select(wrapper, 'appointments-notice').element.value).toBe('240');
    expect(select(wrapper, 'appointments-window').element.value).toBe('7');
    expect(
      wrapper.get('[data-testid="appointments-field-phone"] input').element
        .checked
    ).toBe(true);
    expect(
      wrapper.get('[data-testid="appointments-field-name"] input').element
        .checked
    ).toBe(false);
  });

  describe('confirmation and reminders', () => {
    const openFields = async assistant => {
      const wrapper = await mountForm(
        assistant || {
          config: {
            appointments: { enabled: true, calendar_connection_id: 7 },
          },
        }
      );
      return wrapper;
    };
    const check = (wrapper, testId) =>
      wrapper.get(`[data-testid="${testId}"] input`);

    it('turns confirmation and both reminders on and paid templates off by default', async () => {
      const wrapper = await openFields();

      expect(
        check(wrapper, 'appointments-send-confirmation').element.checked
      ).toBe(true);
      expect(check(wrapper, 'appointments-reminder-24h').element.checked).toBe(
        true
      );
      expect(check(wrapper, 'appointments-reminder-2h').element.checked).toBe(
        true
      );
      expect(
        check(wrapper, 'appointments-paid-templates').element.checked
      ).toBe(false);
      expect(
        wrapper.find('[data-testid="appointments-templates"]').exists()
      ).toBe(false);
    });

    it('always shows the note that outside 24 h WhatsApp needs a paid template', async () => {
      const wrapper = await openFields();

      expect(wrapper.get('[data-testid="appointments-paid-note"]').text()).toBe(
        'CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.PAID_NOTE'
      );
    });

    it('lists only approved WhatsApp templates once paid templates are allowed', async () => {
      inboxes.value = [
        {
          channel_type: 'Channel::Whatsapp',
          message_templates: [
            { name: 'recordatorio', language: 'es', status: 'APPROVED' },
            { name: 'borrador', language: 'es', status: 'PENDING' },
          ],
        },
        {
          channel_type: 'Channel::WebWidget',
          message_templates: [
            { name: 'otro', language: 'es', status: 'APPROVED' },
          ],
        },
      ];
      const wrapper = await openFields();
      await check(wrapper, 'appointments-paid-templates').setValue(true);

      const options = wrapper
        .get('[data-testid="appointments-template-reminder"] select')
        .findAll('option')
        .map(option => option.element.value);
      expect(options).toEqual(['', 'recordatorio|es']);
    });

    it('saves the toggles and the chosen templates', async () => {
      inboxes.value = [
        {
          channel_type: 'Channel::Whatsapp',
          message_templates: [
            { name: 'recordatorio', language: 'es', status: 'approved' },
          ],
        },
      ];
      const wrapper = await openFields({
        config: {
          appointments: {
            enabled: true,
            calendar_connection_id: 7,
            calendar_id: 'cal-1',
          },
        },
      });
      await check(wrapper, 'appointments-reminder-2h').setValue(false);
      await check(wrapper, 'appointments-paid-templates').setValue(true);
      await select(wrapper, 'appointments-template-reminder').setValue(
        'recordatorio|es'
      );

      await wrapper.get('[data-testid="appointments-save"]').trigger('click');

      expect(wrapper.emitted('submit')[0][0].config.appointments).toMatchObject(
        {
          send_confirmation: true,
          reminder_24h: true,
          reminder_2h: false,
          allow_paid_templates: true,
          template_confirmation: null,
          template_reminder: { name: 'recordatorio', language: 'es' },
          template_cancelled: null,
        }
      );
    });
  });
});
