import { flushPromises, mount } from '@vue/test-utils';
import AssistantFollowupForm from './AssistantFollowupForm.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import { nextTick } from 'vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

const { inboxes } = vi.hoisted(() => ({ inboxes: { value: [] } }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => inboxes,
}));

const mountForm = (config = {}) =>
  mount(AssistantFollowupForm, {
    props: { assistant: { config: { response_window: 'always', ...config } } },
    global: {
      mocks: { $t: key => key },
      stubs: { InsertVariableButton: true },
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

  it('is on by default: one nudge after 30 minutes, closing 2 hours later, no re-engagement', async () => {
    const wrapper = mountForm();
    expect(wrapper.find('[data-testid="followup-fields"]').exists()).toBe(true);

    await save(wrapper);

    expect(submitted(wrapper)).toEqual({
      response_window: 'always',
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

  it('shows the saved values', () => {
    const wrapper = mountForm({
      followup: {
        inactivity_enabled: true,
        inactivity_after_minutes: 60,
        max_nudges: 2,
        close_after_minutes: 240,
      },
    });

    expect(select(wrapper, 'followup-after').props('modelValue')).toBe(60);
    expect(select(wrapper, 'followup-nudges').props('modelValue')).toBe(2);
    expect(select(wrapper, 'followup-close').props('modelValue')).toBe(240);
  });

  it('keeps a saved value that is not one of the options', () => {
    const wrapper = mountForm({ followup: { inactivity_after_minutes: 25 } });

    expect(select(wrapper, 'followup-after').props('modelValue')).toBe(25);
  });

  it('saves numeric values and 0 nudges', async () => {
    const wrapper = mountForm();
    select(wrapper, 'followup-after').vm.$emit('update:modelValue', 15);
    await nextTick();
    select(wrapper, 'followup-nudges').vm.$emit('update:modelValue', 0);
    await nextTick();
    select(wrapper, 'followup-close').vm.$emit('update:modelValue', 60);
    await nextTick();

    await save(wrapper);

    expect(submitted(wrapper).followup).toMatchObject({
      inactivity_after_minutes: 15,
      max_nudges: 0,
      close_after_minutes: 60,
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

  describe('re-engagement', () => {
    const enable = wrapper =>
      wrapper
        .get('[data-testid="followup-reengagement-enabled"] input')
        .setValue(true);

    it('is off by default', () => {
      const wrapper = mountForm();

      expect(
        wrapper.get('[data-testid="followup-reengagement-enabled"] input')
          .element.checked
      ).toBe(false);
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
      expect(submitted(wrapper).allow_paid_templates).toBe(true);
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
});
