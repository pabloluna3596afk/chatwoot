import catalog from 'dashboard/components-next/variable-picker/specs/catalog.json';
import { flushPromises, mount } from '@vue/test-utils';
import AssistantFollowupForm from './AssistantFollowupForm.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import DurationSelect from './DurationSelect.vue';
import { nextTick } from 'vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

const { inboxes, getCaptainInboxes } = vi.hoisted(() => ({
  inboxes: { value: [] },
  getCaptainInboxes: vi.fn(async () => ({ data: { payload: inboxes.value } })),
}));

vi.mock('dashboard/api/variables', () => ({
  default: {
    catalog: vi.fn(async () => ({
      data: {
        variables: catalog.variables
          .filter(item => item.reference.kind === 'system')
          .map(item => ({ ...item, available: item.group !== 'company' })),
      },
    })),
  },
}));
vi.mock('vue-i18n', () => ({
  I18nT: { template: '<p><slot name="link" /></p>' },
  useI18n: () => ({
    te: () => false,
    t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1', assistantId: '2' } }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: name =>
    name === 'attributes/getAttributes' ? { value: [] } : inboxes,
}));
vi.mock('dashboard/api/captain/inboxes', () => ({
  default: { get: getCaptainInboxes },
}));

const mountForm = (config = {}) =>
  mount(AssistantFollowupForm, {
    props: {
      assistant: { id: 2, config: { response_window: 'always', ...config } },
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        InsertVariableButton: true,
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });

const select = (wrapper, testId) =>
  wrapper
    .findAllComponents(ComboBox)
    .find(component => component.attributes('data-testid') === testId);
const save = wrapper =>
  wrapper.get('[data-testid="followup-save"]').trigger('click');
const submitted = wrapper => wrapper.emitted('submit')[0][0].config;

describe('AssistantFollowupForm', () => {
  beforeEach(() => {
    inboxes.value = [];
  });

  it('saves only follow-up fields without forwarding messaging or closure settings', async () => {
    const wrapper = mountForm({
      messaging: { version: 2, revision: 4 },
      auto_resolve_after: 120,
      completion_signal_enabled: true,
    });
    await save(wrapper);
    expect(Object.keys(submitted(wrapper))).toEqual(['followup']);
    expect(submitted(wrapper)).not.toHaveProperty('messaging');
  });

  it('warns about a saved non-utility template without offering it', async () => {
    inboxes.value = [
      {
        id: 1,
        name: 'Ventas',
        channel_type: 'Channel::Whatsapp',
        message_templates: [
          {
            name: 'promo',
            language: 'es',
            status: 'APPROVED',
            category: 'MARKETING',
          },
        ],
      },
    ];
    const wrapper = mountForm({
      allow_paid_templates: true,
      followup: {
        reengagement_enabled: true,
        reengagement_template: { name: 'promo', language: 'es' },
      },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('MARKETING_NOT_ALLOWED');
    expect(
      select(wrapper, 'followup-template')
        .props('options')
        .map(option => option.value)
    ).toEqual(['']);
  });

  it('is on by default with one unified timer and no re-engagement', async () => {
    const wrapper = mountForm();
    expect(wrapper.find('[data-testid="followup-fields"]').exists()).toBe(true);

    await save(wrapper);

    expect(submitted(wrapper)).toEqual({
      followup: {
        inactivity_enabled: true,
        inactivity_after_minutes: 30,
        max_nudges: 1,
        close_after_minutes: 120,
        reengagement_enabled: false,
        reengagement_template: null,
      },
    });
  });

  it('matches the approved block order and exposes only one timer and two message counts', () => {
    const wrapper = mountForm();
    const html = wrapper.html();

    expect(html.indexOf('closure-summary')).toBeLessThan(
      html.indexOf('followup-fields')
    );
    expect(html.indexOf('followup-fields')).toBeLessThan(
      html.indexOf('followup-reengagement')
    );

    expect(wrapper.findAllComponents(DurationSelect)).toHaveLength(0);
    expect(select(wrapper, 'followup-close')).toBeUndefined();
    expect(select(wrapper, 'followup-nudges').props('options')).toHaveLength(2);
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.GOODBYE_LINK'
    );
  });

  it('shows the saved mode, inactivity timer and follow-up values', () => {
    const wrapper = mountForm({
      auto_resolve_mode: 'legacy',
      auto_resolve_after: 90,
      followup: {
        inactivity_enabled: true,
        inactivity_after_minutes: 60,
        max_nudges: 2,
        close_after_minutes: 240,
      },
    });

    expect(select(wrapper, 'followup-after').props('modelValue')).toBe(60);
    expect(select(wrapper, 'followup-nudges').props('modelValue')).toBe(2);
    expect(wrapper.get('[data-testid="closure-summary"]').text()).toContain(
      '90'
    );
    expect(select(wrapper, 'followup-close')).toBeUndefined();
  });

  it('keeps a saved value that is not one of the options', () => {
    const wrapper = mountForm({ followup: { inactivity_after_minutes: 25 } });

    expect(select(wrapper, 'followup-after').props('modelValue')).toBe(25);
  });

  it('saves numeric values and one or two messages', async () => {
    const wrapper = mountForm();
    select(wrapper, 'followup-after').vm.$emit('update:modelValue', 15);
    await nextTick();
    select(wrapper, 'followup-nudges').vm.$emit('update:modelValue', 2);
    await nextTick();
    await save(wrapper);

    expect(submitted(wrapper).followup).toMatchObject({
      inactivity_after_minutes: 15,
      max_nudges: 2,
      close_after_minutes: 120,
    });
  });

  it('hides the fields and saves it off when switched off', async () => {
    const wrapper = mountForm();

    await wrapper.get('button[role="switch"]').trigger('click');

    expect(wrapper.find('[data-testid="followup-fields"]').exists()).toBe(
      false
    );
    await save(wrapper);
    expect(submitted(wrapper).followup.inactivity_enabled).toBe(false);
  });

  it('does not validate the ask time when follow-up is off', async () => {
    const wrapper = mountForm({
      auto_resolve_after: 30,
      followup: { inactivity_after_minutes: 30 },
    });

    await wrapper.get('button[role="switch"]').trigger('click');
    await save(wrapper);

    expect(wrapper.find('[data-testid="followup-after-error"]').exists()).toBe(
      false
    );
    expect(wrapper.emitted('submit')).toBeDefined();
  });

  describe('re-engagement', () => {
    const enable = wrapper =>
      wrapper
        .get('[data-testid="followup-reengagement"] button[role="switch"]')
        .trigger('click');

    it('is off by default', () => {
      const wrapper = mountForm();

      expect(
        wrapper
          .get('[data-testid="followup-reengagement"] button[role="switch"]')
          .attributes('aria-checked')
      ).toBe('false');
      expect(wrapper.find('[data-testid="followup-template"]').exists()).toBe(
        false
      );
    });

    it('points to the paid messages switch while it is off', async () => {
      const wrapper = mountForm();
      await enable(wrapper);

      expect(wrapper.get('[data-testid="followup-paid-hint"]').text()).toBe(
        'CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.PAID_HINT'
      );
      expect(wrapper.find('[data-testid="followup-template"]').exists()).toBe(
        false
      );
    });

    const volver = {
      name: 'volver',
      language: 'es',
      status: 'approved',
      category: 'UTILITY',
      components: [{ type: 'BODY', text: 'Hola {{1}}, soy {{2}}.' }],
    };
    const parser = wrapper => wrapper.findComponent(WhatsAppTemplateParser);
    const fill = async (wrapper, values) => {
      const inputs = parser(wrapper).findAll('input[type="text"]');
      for (let index = 0; index < values.length; index += 1) {
        // eslint-disable-next-line no-await-in-loop
        await inputs[index].setValue(values[index]);
      }
    };
    const withTemplates = templates => {
      inboxes.value = [
        { channel_type: 'Channel::Whatsapp', message_templates: templates },
      ];
    };

    it('lists the approved templates once paid messages are on and saves the pick with the text of each variable', async () => {
      withTemplates([
        volver,
        { ...volver, name: 'borrador', status: 'pending' },
      ]);
      const wrapper = mountForm({ allow_paid_templates: true });
      await enable(wrapper);

      const options = select(wrapper, 'followup-template')
        .props('options')
        .map(option => option.value);
      expect(options).toEqual(['', 'volver|es']);

      select(wrapper, 'followup-template').vm.$emit(
        'update:modelValue',
        'volver|es'
      );
      await nextTick();
      await fill(wrapper, ['{{ contact.name }}', 'Soy {{ assistant.name }}']);
      await save(wrapper);

      expect(submitted(wrapper).followup).toMatchObject({
        reengagement_enabled: true,
        reengagement_template: {
          name: 'volver',
          language: 'es',
          processed_params: {
            body: { 1: '{{ contact.name }}', 2: 'Soy {{ assistant.name }}' },
          },
        },
      });
      expect(submitted(wrapper)).not.toHaveProperty('allow_paid_templates');
    });

    it('offers only what the customer and the assistant can fill in, with samples for the preview', async () => {
      withTemplates([volver]);
      const wrapper = mountForm({ allow_paid_templates: true });
      await enable(wrapper);
      select(wrapper, 'followup-template').vm.$emit(
        'update:modelValue',
        'volver|es'
      );
      await nextTick();

      expect(
        parser(wrapper)
          .props('variableOptions')
          .map(option => option.key)
      ).toEqual([
        'contact.name',
        'contact.first_name',
        'contact.last_name',
        'contact.email',
        'contact.phone',
        'contact.company_name',
        'contact.city',
        'contact.country_code',
        'contact.document_number',
        'agent.name',
        'conversation.id',
        'assistant.name',
        'account.name',
      ]);
      expect(Object.keys(parser(wrapper).props('previewValues'))).toContain(
        'assistant.name'
      );
    });

    it('cannot be saved with a variable left empty, and says so', async () => {
      withTemplates([volver]);
      const wrapper = mountForm({ allow_paid_templates: true });
      await enable(wrapper);
      select(wrapper, 'followup-template').vm.$emit(
        'update:modelValue',
        'volver|es'
      );
      await nextTick();
      await fill(wrapper, ['{{ contact.name }}']);

      await save(wrapper);

      expect(wrapper.emitted('submit')).toBeUndefined();
      expect(
        wrapper.get('[data-testid="followup-template-error"]').text()
      ).toBe('CAPTAIN.ASSISTANTS.FORM.TEMPLATE_VARIABLES.ERROR');
    });

    it('shows the saved texts and saves them again as they were', async () => {
      withTemplates([volver]);
      const saved = {
        name: 'volver',
        language: 'es',
        processed_params: {
          body: { 1: '{{ contact.name }}', 2: '{{ assistant.name }}' },
        },
      };
      const wrapper = mountForm({
        allow_paid_templates: true,
        followup: { reengagement_enabled: true, reengagement_template: saved },
      });
      await flushPromises();

      expect(
        parser(wrapper)
          .findAll('input[type="text"]')
          .map(input => input.element.value)
      ).toEqual(['{{ contact.name }}', '{{ assistant.name }}']);

      await save(wrapper);

      expect(submitted(wrapper).followup.reengagement_template).toEqual(saved);
    });
  });
  it('rejects asking at or after the unified inactivity timer', async () => {
    const wrapper = mountForm({ auto_resolve_after: 30 });
    await save(wrapper);

    expect(wrapper.emitted('submit')).toBeUndefined();
    expect(wrapper.get('[data-testid="followup-after-error"]').text()).toBe(
      'CAPTAIN.ASSISTANTS.FORM.FOLLOWUP.AFTER_ERROR'
    );
  });

  it('hides the timer in wait-for-customer mode and does not validate against it', async () => {
    const wrapper = mountForm({
      auto_resolve_mode: 'disabled',
      auto_resolve_after: 30,
    });
    expect(wrapper.findComponent(DurationSelect).exists()).toBe(false);
    await save(wrapper);
    expect(wrapper.emitted('submit')).toBeDefined();
  });

  it('treats saved zero messages as off and preserves zero until the switch is enabled', async () => {
    const wrapper = mountForm({
      followup: { inactivity_enabled: true, max_nudges: 0 },
    });
    expect(wrapper.find('[data-testid="followup-fields"]').exists()).toBe(
      false
    );
    expect(
      wrapper.get('button[role="switch"]').attributes('aria-checked')
    ).toBe('false');

    await save(wrapper);
    expect(submitted(wrapper).followup.max_nudges).toBe(0);

    await wrapper.get('button[role="switch"]').trigger('click');
    expect(select(wrapper, 'followup-nudges').props('modelValue')).toBe(1);
  });
});
