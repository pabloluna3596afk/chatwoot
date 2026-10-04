import { flushPromises, mount } from '@vue/test-utils';
import AssistantAppointmentsForm from './AssistantAppointmentsForm.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

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
      mocks: { $t: key => key },
      stubs: {
        InsertVariableButton: true,
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
  reminder_1: { enabled: true, hours_before: 24 },
  reminder_2: { enabled: true, hours_before: 3 },
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
    const appointments = {
      enabled: true,
      calendar_connection_id: 7,
      calendar_id: 'cal-1',
    };
    const openFields = (config = {}) =>
      mountForm({ config: { appointments, ...config } });
    const check = (wrapper, testId) =>
      wrapper.get(`[data-testid="${testId}"] input`);

    const whatsappInbox = templates => ({
      channel_type: 'Channel::Whatsapp',
      message_templates: templates,
    });

    const hours = (wrapper, number) =>
      wrapper.get(
        `[data-testid="appointments-reminder-${number}-hours"] input`
      );

    it('has no confirmation switch: the confirmation is always the booking reply', async () => {
      const wrapper = await openFields();

      expect(
        wrapper.find('[data-testid="appointments-send-confirmation"]').exists()
      ).toBe(false);
      expect(
        wrapper.get('[data-testid="appointments-confirmation-note"]').text()
      ).toBe(
        'CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.CONFIRMATION_NOTE'
      );
    });

    it('turns both reminders on by default, at 24 h and 3 h', async () => {
      const wrapper = await openFields();

      expect(check(wrapper, 'appointments-reminder-1').element.checked).toBe(
        true
      );
      expect(check(wrapper, 'appointments-reminder-2').element.checked).toBe(
        true
      );
      expect(hours(wrapper, 1).element.value).toBe('24');
      expect(hours(wrapper, 2).element.value).toBe('3');
    });

    it('explains next to each reminder that it is free only inside the 24 h window', async () => {
      const wrapper = await openFields();

      [1, 2].forEach(number => {
        expect(
          wrapper
            .get(`[data-testid="appointments-reminder-${number}-hint"]`)
            .text()
        ).toBe('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.WINDOW_HINT');
      });
    });

    it('shows the saved lead times, and reads the old 24 h / 2 h settings as they come from the API', async () => {
      const wrapper = await openFields({
        appointments: {
          ...appointments,
          reminder_1: { enabled: false, hours_before: 48 },
          reminder_2: { enabled: true, hours_before: 6 },
        },
      });

      expect(check(wrapper, 'appointments-reminder-1').element.checked).toBe(
        false
      );
      expect(hours(wrapper, 1).element.value).toBe('48');
      expect(hours(wrapper, 2).element.value).toBe('6');
    });

    it('saves the lead times of both reminders as numbers', async () => {
      const wrapper = await openFields();
      await hours(wrapper, 1).setValue('48');
      await hours(wrapper, 2).setValue('2');
      await check(wrapper, 'appointments-reminder-2').setValue(false);

      await wrapper.get('[data-testid="appointments-save"]').trigger('click');

      expect(wrapper.emitted('submit')[0][0].config.appointments).toMatchObject(
        {
          reminder_1: { enabled: true, hours_before: 48 },
          reminder_2: { enabled: false, hours_before: 2 },
        }
      );
    });

    it('does not save a lead time outside 1 to 168 hours, and says so', async () => {
      const wrapper = await openFields();
      await hours(wrapper, 1).setValue('200');

      await wrapper.get('[data-testid="appointments-save"]').trigger('click');

      expect(wrapper.emitted('submit')).toBeUndefined();
      expect(wrapper.text()).toContain(
        'CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.HOURS_ERROR'
      );
    });

    it('has no paid templates switch of its own: it points to the assistant one', async () => {
      const wrapper = await openFields();

      expect(
        wrapper.find('[data-testid="appointments-paid-templates"]').exists()
      ).toBe(false);
      expect(wrapper.get('[data-testid="appointments-paid-hint"]').text()).toBe(
        'CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.REMINDERS.PAID_HINT'
      );
      expect(
        wrapper.find('[data-testid="appointments-templates"]').exists()
      ).toBe(false);
    });

    it('lists only approved WhatsApp templates once the assistant allows paid templates', async () => {
      inboxes.value = [
        whatsappInbox([
          { name: 'recordatorio', language: 'es', status: 'APPROVED' },
          { name: 'borrador', language: 'es', status: 'PENDING' },
        ]),
        {
          channel_type: 'Channel::WebWidget',
          message_templates: [
            { name: 'otro', language: 'es', status: 'APPROVED' },
          ],
        },
      ];
      const wrapper = await openFields({ allow_paid_templates: true });

      expect(
        wrapper.find('[data-testid="appointments-paid-hint"]').exists()
      ).toBe(false);
      const options = wrapper
        .get('[data-testid="appointments-template-reminder"] select')
        .findAll('option')
        .map(option => option.element.value);
      expect(options).toEqual(['', 'recordatorio|es']);
    });

    it('has no confirmation template picker: the confirmation is free and never a template', async () => {
      const wrapper = await openFields({ allow_paid_templates: true });

      expect(
        wrapper
          .find('[data-testid="appointments-template-confirmation"]')
          .exists()
      ).toBe(false);
      expect(
        wrapper.find('[data-testid="appointments-template-reminder"]').exists()
      ).toBe(true);
      expect(
        wrapper.find('[data-testid="appointments-template-cancelled"]').exists()
      ).toBe(true);
    });

    const templateWithVariables = {
      name: 'recordatorio',
      language: 'es',
      status: 'approved',
      components: [
        { type: 'HEADER', format: 'TEXT', text: 'Cita {{titulo}}' },
        { type: 'BODY', text: 'Hola {{nombre}}, es el {{fecha}}.' },
      ],
      parameter_format: 'NAMED',
    };

    const parser = wrapper => wrapper.findComponent(WhatsAppTemplateParser);

    const fillParser = async (wrapper, values) => {
      const inputs = parser(wrapper).findAll('input[type="text"]');
      for (let index = 0; index < values.length; index += 1) {
        // eslint-disable-next-line no-await-in-loop
        await inputs[index].setValue(values[index]);
      }
    };

    const pickTemplate = async wrapper => {
      await select(wrapper, 'appointments-template-reminder').setValue(
        'recordatorio|es'
      );
      await flushPromises();
    };

    it('saves the toggles and the chosen template with the text of each variable, without the paid switch', async () => {
      inboxes.value = [whatsappInbox([templateWithVariables])];
      const wrapper = await openFields({ allow_paid_templates: true });
      await check(wrapper, 'appointments-reminder-2').setValue(false);
      await pickTemplate(wrapper);
      await fillParser(wrapper, [
        '{{ appointment.title }}',
        'Hola {{ contact.name }}',
        '{{ appointment.date }}',
      ]);

      await wrapper.get('[data-testid="appointments-save"]').trigger('click');

      const [payload] = wrapper.emitted('submit')[0];
      expect(payload.config.appointments).toMatchObject({
        reminder_1: { enabled: true, hours_before: 24 },
        reminder_2: { enabled: false, hours_before: 3 },
        template_reminder: {
          name: 'recordatorio',
          language: 'es',
          processed_params: {
            header: { titulo: '{{ appointment.title }}' },
            body: {
              nombre: 'Hola {{ contact.name }}',
              fecha: '{{ appointment.date }}',
            },
          },
        },
        template_cancelled: null,
      });
      expect(payload.config.appointments).not.toHaveProperty(
        'allow_paid_templates'
      );
      expect(payload.config.allow_paid_templates).toBe(true);
    });

    it('offers the variables of the appointment, the assistant and the customer, and previews samples', async () => {
      inboxes.value = [whatsappInbox([templateWithVariables])];
      const wrapper = await openFields({ allow_paid_templates: true });
      await pickTemplate(wrapper);

      expect(
        parser(wrapper)
          .props('variableOptions')
          .map(option => option.key)
      ).toEqual([
        'contact.name',
        'contact.first_name',
        'appointment.date',
        'appointment.time',
        'appointment.datetime',
        'appointment.title',
        'assistant.name',
      ]);
      expect(Object.keys(parser(wrapper).props('previewValues'))).toContain(
        'appointment.date'
      );
    });

    it('cannot be saved with a variable left empty, and says so', async () => {
      inboxes.value = [whatsappInbox([templateWithVariables])];
      const wrapper = await openFields({ allow_paid_templates: true });
      await pickTemplate(wrapper);
      await fillParser(wrapper, ['{{ appointment.title }}', 'Hola']);

      await wrapper.get('[data-testid="appointments-save"]').trigger('click');

      expect(wrapper.emitted('submit')).toBeUndefined();
      expect(
        wrapper
          .get('[data-testid="appointments-template-reminder-error"]')
          .text()
      ).toBe('CAPTAIN.ASSISTANTS.FORM.TEMPLATE_VARIABLES.ERROR');
    });

    it('shows the saved text of each variable and saves it again as it was', async () => {
      inboxes.value = [whatsappInbox([templateWithVariables])];
      const saved = {
        name: 'recordatorio',
        language: 'es',
        processed_params: {
          header: { titulo: '{{ appointment.title }}' },
          body: {
            nombre: '{{ contact.name }}',
            fecha: '{{ appointment.date }}',
          },
        },
      };
      const wrapper = await openFields({
        allow_paid_templates: true,
        appointments: { ...appointments, template_reminder: saved },
      });

      expect(
        parser(wrapper)
          .findAll('input[type="text"]')
          .map(input => input.element.value)
      ).toEqual([
        '{{ appointment.title }}',
        '{{ contact.name }}',
        '{{ appointment.date }}',
      ]);

      await wrapper.get('[data-testid="appointments-save"]').trigger('click');

      expect(
        wrapper.emitted('submit')[0][0].config.appointments.template_reminder
      ).toEqual(saved);
    });

    it('starts the variables over when another template is chosen', async () => {
      inboxes.value = [
        whatsappInbox([
          templateWithVariables,
          {
            ...templateWithVariables,
            name: 'otra',
            components: [{ type: 'BODY', text: 'Hola {{1}}' }],
          },
        ]),
      ];
      const wrapper = await openFields({ allow_paid_templates: true });
      await pickTemplate(wrapper);
      await fillParser(wrapper, ['a', 'b', 'c']);

      await select(wrapper, 'appointments-template-reminder').setValue(
        'otra|es'
      );
      await flushPromises();

      expect(
        parser(wrapper)
          .findAll('input[type="text"]')
          .map(input => input.element.value)
      ).toEqual(['']);
    });
  });
});
