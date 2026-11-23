import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CalendarTemplates from '../CalendarTemplates.vue';
import { fillExamples } from '../calendarTemplatePreview';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import WhatsAppBubble from 'dashboard/components-next/whatsapp/WhatsAppBubble.vue';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/calendarActivationKit.json';
import es from 'dashboard/i18n/locale/es/calendarActivationKit.json';

const { admin, push } = vi.hoisted(() => ({
  admin: { value: true },
  push: vi.fn(),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params, query) => ({
      name,
      params: { accountId: 7, ...params },
      query,
    }),
  }),
}));
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => admin.value) }) };
});
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    getTemplateDrafts: vi.fn(),
    linkTemplateDraft: vi.fn(),
    prepareTemplateDrafts: vi.fn(),
    getActivationKit: vi.fn(),
    updateReminderEnabled: vi.fn(),
  },
}));
const draft = {
  status: 'created',
  draft_id: 31,
  draft_exists: true,
  archived: false,
  linked: false,
  approved: false,
  submitted: false,
  submission_status: null,
  remote_status: null,
};
const kit = {
  template: {
    body: 'Hi {{nombre}}, your appointment "{{cita}}" is booked for {{fecha}} at {{hora}}.',
    buttons: ['Confirm', 'Reschedule', 'Cancel'],
  },
  cancel_template: {
    body: 'Hi {{nombre}}, your appointment "{{cita}}" on {{fecha}} at {{hora}} was cancelled.',
    buttons: [],
  },
  reminder_template: {
    body: 'Hi {{nombre}}, this is a reminder of your appointment "{{cita}}" on {{fecha}} at {{hora}}.',
    buttons: ['Confirm', 'Reschedule', 'Cancel'],
  },
  reminder_enabled: false,
};
const render = async (
  results = { confirmation: draft, cancellation: draft, reminder: draft },
  props = {},
  locale = 'en',
  language = locale
) => {
  CalendarAPI.getTemplateDrafts.mockResolvedValue({
    data: { results, language },
  });
  const wrapper = mount(CalendarTemplates, {
    props: { connected: true, ...props },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale,
          messages: {
            en: { ...en, SWITCH: { TOGGLE: 'Toggle' } },
            es: { ...es, SWITCH: { TOGGLE: 'Alternar' } },
          },
        }),
      ],
    },
  });
  await flushPromises();
  return wrapper;
};
beforeEach(() => {
  vi.clearAllMocks();
  admin.value = true;
  CalendarAPI.getActivationKit.mockResolvedValue({ data: { ...kit } });
});
describe('fillExamples', () => {
  it.each([
    ['es', 'María Consulta 23/08/2026 10:00 María {{otra}}'],
    ['en', 'Maria Consultation 08/23/2026 10:00 Maria {{otra}}'],
  ])(
    'fills known variables in %s and preserves the source and unknown tokens',
    (language, expected) => {
      const body =
        '{{nombre}} {{cita}} {{fecha}} {{hora}} {{ nombre }} {{otra}}';
      expect(fillExamples(body, language)).toBe(expected);
      expect(body).toBe(
        '{{nombre}} {{cita}} {{fecha}} {{hora}} {{ nombre }} {{otra}}'
      );
    }
  );
});

describe('CalendarTemplates', () => {
  it.each([
    ['es', 'en', ['María', 'Consulta', '23/08/2026', '10:00']],
    ['en', 'es', ['Maria', 'Consultation', '08/23/2026', '10:00']],
  ])(
    'renders examples in account language %s independently of UI locale %s',
    async (language, locale, examples) => {
      const original = JSON.stringify(kit);
      const wrapper = await render(undefined, {}, locale, language);
      const bubbles = wrapper.findAllComponents(WhatsAppBubble);
      expect(bubbles).toHaveLength(3);
      bubbles.forEach(bubble => {
        examples.forEach(example => expect(bubble.text()).toContain(example));
        expect(bubble.text()).not.toContain('{{');
      });
      expect(JSON.stringify(kit)).toBe(original);
      expect(kit.template.body).toContain('{{nombre}}');
    }
  );
  it('has matching English and Spanish translation keys', () => {
    expect(Object.keys(en.CALENDAR_TEMPLATES)).toEqual(
      Object.keys(es.CALENDAR_TEMPLATES)
    );
    expect(Object.keys(en.CALENDAR_TEMPLATES.REASONS)).toEqual(
      Object.keys(es.CALENDAR_TEMPLATES.REASONS)
    );
    expect(Object.keys(en.CALENDAR_TEMPLATES.LOCAL_STATUS)).toEqual(
      Object.keys(es.CALENDAR_TEMPLATES.LOCAL_STATUS)
    );
  });
  it.each(['submitting', 'reconciling'])(
    'shows in-review while submission is %s',
    async submission_status => {
      const wrapper = await render({
        confirmation: { ...draft, submission_status },
      });
      expect(wrapper.get('[data-testid="meta-confirmation"]').text()).toBe(
        'In review'
      );
      expect(wrapper.get('[data-testid="local-confirmation"]').text()).toBe(
        'Draft'
      );
    }
  );
  it('shows the spinner until the preview request completes', async () => {
    let finish;
    CalendarAPI.getActivationKit.mockReturnValue(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const wrapper = await render();
    expect(wrapper.findComponent({ name: 'Spinner' }).exists()).toBe(true);
    expect(wrapper.findAllComponents(WhatsAppBubble)).toHaveLength(0);
    finish({ data: kit });
    await flushPromises();
    expect(wrapper.findAllComponents(WhatsAppBubble)).toHaveLength(3);
  });
  it('loads three real previews and keeps local and Meta states separate', async () => {
    const wrapper = await render({
      confirmation: draft,
      cancellation: {
        ...draft,
        submitted: true,
        remote_status: 'APPROVED',
        approved: true,
      },
      reminder: { ...draft, submitted: true, remote_status: 'PENDING' },
    });
    expect(CalendarAPI.getTemplateDrafts).toHaveBeenCalledOnce();
    expect(wrapper.findAllComponents(WhatsAppBubble)).toHaveLength(3);
    expect(wrapper.findComponent(WhatsAppBubble).props('body')).toBe(
      'Hi Maria, your appointment "Consultation" is booked for 08/23/2026 at 10:00.'
    );
    expect(
      wrapper.findAllComponents(WhatsAppBubble)[1].props('buttons')
    ).toEqual([]);
    expect(wrapper.get('[data-testid="local-cancellation"]').text()).toBe(
      'Draft'
    );
    expect(wrapper.get('[data-testid="meta-cancellation"]').text()).toBe(
      'Approved'
    );
    expect(wrapper.get('[data-testid="meta-confirmation"]').text()).toBe(
      'Not sent'
    );
    expect(wrapper.get('[data-testid="meta-reminder"]').text()).toBe(
      'In review'
    );
    await wrapper.get('[data-testid="open-confirmation"]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'settings_templates',
      params: { accountId: 7 },
      query: { draft: '31' },
    });
    expect(wrapper.find('select').exists()).toBe(false);
  });
  it.each(['en', 'es'])(
    'translates conflicts, archived and rejected states in %s',
    async locale => {
      const wrapper = await render(
        {
          confirmation: {
            ...draft,
            status: 'conflict',
            reason: 'remote_template_exists',
            draft_exists: false,
          },
          cancellation: { ...draft, archived: true },
          reminder: {
            ...draft,
            status: 'conflict',
            reason: 'variables',
            remote_status: 'REJECTED',
          },
        },
        {},
        locale
      );
      expect(wrapper.text()).not.toContain('CALENDAR_');
      expect(wrapper.findAll('[role="alert"]')).toHaveLength(3);
      expect(wrapper.get('[data-testid="local-cancellation"]').text()).toBe(
        locale === 'en' ? 'Archived' : 'Archivada'
      );
      expect(wrapper.get('[data-testid="meta-reminder"]').text()).toBe(
        locale === 'en' ? 'Rejected' : 'Rechazada'
      );
      await wrapper.get('[data-testid="open-confirmation"]').trigger('click');
      expect(push.mock.calls[0][0].query).toEqual({});
    }
  );
  it('retries preparation and replaces the returned states', async () => {
    const wrapper = await render({});
    expect(wrapper.text()).toContain('not been prepared');
    CalendarAPI.prepareTemplateDrafts.mockResolvedValue({
      data: { results: { confirmation: draft }, language: 'en' },
    });
    await wrapper.get('[data-testid="prepare-templates"]').trigger('click');
    await flushPromises();
    expect(CalendarAPI.prepareTemplateDrafts).toHaveBeenCalledOnce();
    expect(wrapper.get('[data-testid="local-confirmation"]').text()).toBe(
      'Draft'
    );
  });
  it.each([
    {},
    { approved: true },
    { linked: true },
    { approved: true, linked: true, archived: true },
    { approved: true, linked: true, status: 'conflict' },
    { approved: true, linked: true, draft_exists: false },
  ])('blocks reminder activation until eligible: %j', async extra => {
    const wrapper = await render({ reminder: { ...draft, ...extra } });
    expect(wrapper.get('[role="switch"]').attributes('disabled')).toBeDefined();
    wrapper.findComponent(Switch).vm.$emit('update:modelValue', true);
    await flushPromises();
    expect(CalendarAPI.updateReminderEnabled).not.toHaveBeenCalled();
  });
  it('saves the opt-in only for an approved linked reminder', async () => {
    const wrapper = await render({
      reminder: {
        ...draft,
        approved: true,
        linked: true,
        remote_status: 'APPROVED',
        destinations: [
          { state: 'usable', via: 'linked', waba_id: 'a', channels: [] },
        ],
      },
    });
    expect(wrapper.findComponent(Switch).props('modelValue')).toBe(false);
    expect(
      wrapper.get('[role="switch"]').attributes('disabled')
    ).toBeUndefined();
    CalendarAPI.updateReminderEnabled.mockResolvedValue({
      data: { reminder_enabled: true },
    });
    await wrapper.get('[role="switch"]').trigger('click');
    await flushPromises();
    expect(CalendarAPI.updateReminderEnabled).toHaveBeenCalledWith(true);
    expect(wrapper.findComponent(Switch).props('modelValue')).toBe(true);
  });
  it('allows turning off an existing reminder after approval is lost', async () => {
    CalendarAPI.getActivationKit.mockResolvedValue({
      data: { ...kit, reminder_enabled: true },
    });
    const wrapper = await render();
    CalendarAPI.updateReminderEnabled.mockResolvedValue({
      data: { reminder_enabled: false },
    });
    expect(
      wrapper.get('[role="switch"]').attributes('disabled')
    ).toBeUndefined();
    await wrapper.get('[role="switch"]').trigger('click');
    await flushPromises();
    expect(CalendarAPI.updateReminderEnabled).toHaveBeenCalledWith(false);
  });
  it('shows Google guidance and disables preparation without a connection', async () => {
    const wrapper = await render({}, { connected: false });
    expect(wrapper.text()).toContain('Connect Google');
    expect(
      wrapper.get('[data-testid="prepare-templates"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.get('[role="switch"]').attributes('disabled')).toBeDefined();
  });
  it('does not call admin endpoints or show actions for agents', async () => {
    admin.value = false;
    const wrapper = await render();
    expect(wrapper.text()).toContain('administrator');
    expect(CalendarAPI.getTemplateDrafts).not.toHaveBeenCalled();
    expect(CalendarAPI.getActivationKit).not.toHaveBeenCalled();
    expect(wrapper.find('button').exists()).toBe(false);
  });
  it('offers recovery after a load failure', async () => {
    CalendarAPI.getActivationKit.mockRejectedValueOnce(new Error('offline'));
    const wrapper = await render();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'could not be loaded'
    );
    CalendarAPI.getActivationKit.mockResolvedValue({ data: kit });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.findAllComponents(WhatsAppBubble)).toHaveLength(3);
  });
  it('reports preparation and save errors without changing the switch', async () => {
    const wrapper = await render({
      reminder: {
        ...draft,
        destinations: [
          {
            state: 'usable',
            via: 'legacy_by_name',
            waba_id: 'a',
            channels: [],
          },
        ],
      },
    });
    CalendarAPI.prepareTemplateDrafts.mockRejectedValue(new Error('offline'));
    await wrapper.get('[data-testid="prepare-templates"]').trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith(en.CALENDAR_TEMPLATES.PREPARE_ERROR);
    CalendarAPI.updateReminderEnabled.mockRejectedValue(new Error('offline'));
    await wrapper.get('[role="switch"]').trigger('click');
    await flushPromises();
    expect(wrapper.findComponent(Switch).props('modelValue')).toBe(false);
    expect(useAlert).toHaveBeenCalledWith(
      en.CALENDAR_ACTIVATION_KIT.REMINDER_SAVE_ERROR
    );
  });
  it.each(['linked', 'legacy_by_name'])(
    'enables partial reminders via %s',
    async via => {
      const wrapper = await render({
        reminder: {
          destinations: [
            {
              waba_id: 'a',
              channels: [{ id: 10, name: 'Sales' }],
              state: 'usable',
              via,
            },
            {
              waba_id: 'b',
              channels: [{ id: 20, name: 'Support' }],
              state: 'pending_approval',
              via: 'none',
            },
          ],
        },
      });
      expect(wrapper.text()).toContain('Sales');
      expect(wrapper.text()).toContain('Support');
      expect(wrapper.text()).toContain('Partial availability');
      expect(
        wrapper.get('[role="switch"]').attributes('disabled')
      ).toBeUndefined();
    }
  );
  it('does not use obsolete aggregates to enable reminders', async () => {
    const wrapper = await render({
      reminder: { ...draft, approved: true, linked: true, destinations: [] },
    });
    expect(wrapper.get('[role="switch"]').attributes('disabled')).toBeDefined();
  });
  it('links the selected destination and displays a 422 reason on failure', async () => {
    const destination = {
      waba_id: 'a',
      channels: [{ id: 10, name: 'Sales' }],
      state: 'incompatible',
      reason: 'explicit_link_required',
      via: 'none',
    };
    const wrapper = await render({
      confirmation: { ...draft, destinations: [destination] },
    });
    const row = wrapper.get('[data-testid="destination-confirmation-a"]');
    expect(row.text()).toContain('Approved, awaiting link');
    CalendarAPI.linkTemplateDraft.mockRejectedValueOnce({
      response: { status: 422, data: { error: 'variables' } },
    });
    await row.get('button').trigger('click');
    await flushPromises();
    expect(CalendarAPI.linkTemplateDraft).toHaveBeenCalledWith({
      function: 'confirmation',
      draft_id: 31,
      channel_id: 10,
    });
    expect(row.get('[role="alert"]').text()).toContain('variables');
    CalendarAPI.linkTemplateDraft.mockResolvedValueOnce({
      data: {
        language: 'en',
        results: {
          confirmation: {
            ...draft,
            destinations: [
              { ...destination, state: 'usable', reason: null, via: 'linked' },
            ],
          },
        },
      },
    });
    await row.get('button').trigger('click');
    await flushPromises();
    expect(row.text()).toContain('Ready to use');
    expect(row.find('button').exists()).toBe(false);
  });
  it('offers explicit preparation in the effective language after a language change', async () => {
    const wrapper = await render();
    CalendarAPI.getTemplateDrafts.mockResolvedValueOnce({
      data: {
        language: 'es',
        prepared_language: 'es',
        effective_language: 'en',
        language_changed: true,
        results: {},
      },
    });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Refresh status')
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(
      'Prepared language: es. Account language: en.'
    );
    CalendarAPI.prepareTemplateDrafts.mockResolvedValueOnce({
      data: {
        language: 'en',
        prepared_language: 'en',
        effective_language: 'en',
        language_changed: false,
        results: {},
      },
    });
    await wrapper.get('[data-testid="prepare-language"]').trigger('click');
    await flushPromises();
    expect(CalendarAPI.prepareTemplateDrafts).toHaveBeenCalledWith('en');
    expect(wrapper.find('[data-testid="prepare-language"]').exists()).toBe(
      false
    );
  });
});
