import { mount, flushPromises, config } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import VariablePicker from '../VariablePicker.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import { writableFor } from 'dashboard/helper/templateVariableBindings';
import en from 'dashboard/i18n/locale/en/variables.json';
import es from 'dashboard/i18n/locale/es/variables.json';

vi.mock(
  'dashboard/routes/dashboard/settings/attributes/AddAttribute.vue',
  () => ({
    __esModule: true,
    default: {
      name: 'AddAttribute',
      props: ['onClose', 'selectedAttributeModelTab'],
      template: '<div />',
    },
  })
);

const pickerI18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en, es },
});
config.global.plugins = [pickerI18n];

const attributes = [
  {
    attribute_key: 'plan',
    attribute_display_name: 'Plan',
    attribute_model: 'contact_attribute',
    attribute_display_type: 'text',
  },
  {
    attribute_key: 'total',
    attribute_display_name: 'Total',
    attribute_model: 'contact_attribute',
    formula: { op: 'sum' },
  },
  {
    attribute_key: 'stage',
    attribute_display_name: 'Stage',
    attribute_model: 'conversation_attribute',
  },
];

const mountPicker = (props = {}, role = 'administrator', refresh = vi.fn()) =>
  mount(VariablePicker, {
    props,
    global: {
      plugins: [
        createStore({
          getters: { getCurrentRole: () => role },
          modules: {
            attributes: {
              namespaced: true,
              getters: { getAttributes: () => attributes },
              actions: { get: refresh },
            },
          },
        }),
      ],
      stubs: { Teleport: true },
    },
  });

describe('VariablePicker', () => {
  it('renders neutral Spanish labels and search text without encoding loss', async () => {
    pickerI18n.global.locale.value = 'es';
    const wrapper = mountPicker();
    const combo = wrapper.getComponent(ComboBox);
    expect(combo.props('groups')[2].label).toBe('Atributos de la conversación');
    expect(combo.props('options')).toContainEqual({
      value: 'telefono',
      label: 'Teléfono (telefono)',
      group: 'system',
    });
    await combo.get('button').trigger('click');
    expect(combo.get('input[type="search"]').attributes('placeholder')).toBe(
      'Buscar variables…'
    );
    wrapper.unmount();
    pickerI18n.global.locale.value = 'en';
  });
  it('keeps en/es keys identical', () => {
    expect(Object.keys(es.VARIABLE_PICKER)).toEqual(
      Object.keys(en.VARIABLE_PICKER)
    );
    expect(Object.keys(es.VARIABLE_PICKER.GROUPS)).toEqual(
      Object.keys(en.VARIABLE_PICKER.GROUPS)
    );
    expect(Object.keys(es.VARIABLE_PICKER.LABELS)).toEqual(
      Object.keys(en.VARIABLE_PICKER.LABELS)
    );
  });

  it('reads aliases with human labels in the shared group order, including formulas', async () => {
    const wrapper = mountPicker();
    const combo = wrapper.getComponent(ComboBox);
    expect(combo.props('groups').map(group => group.key)).toEqual([
      'system',
      'contact',
      'conversation',
      'appointment',
    ]);
    expect(combo.props('options')).toContainEqual({
      value: 'plan',
      label: 'Plan (plan)',
      group: 'contact',
    });
    expect(
      combo.props('options').some(option => option.value === 'total')
    ).toBe(true);
    await combo.get('button').trigger('click');
    await combo.get('input[type="search"]').setValue('Appointment date');
    expect(
      combo.findAll('[role="option"]').map(option => option.text())
    ).toEqual(['Appointment date (fecha)']);
    await combo.get('[role="option"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([['fecha']]);
    await wrapper.setProps({ modelValue: 'fecha' });
    await combo.get('button').trigger('click');
    await combo.get('input[type="search"]').setValue('Appointment date');
    await combo.get('[role="option"]').trigger('click');
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['']);
    wrapper.unmount();
  });

  it('writes canonical paths and filters incompatible fields and formulas, with an optional empty value', () => {
    const wrapper = mountPicker({
      mode: 'write',
      scopes: ['system', 'contact'],
      filter: binding => writableFor(binding, { type: 'short_text' }),
      allowNone: true,
    });
    const combo = wrapper.getComponent(ComboBox);
    expect(combo.props('options')).toContainEqual({
      value: 'contact.custom_attribute.plan',
      label: 'Plan',
      group: 'contact',
    });
    expect(combo.props('options')[0]).toEqual({
      value: '',
      label: 'Do not save',
    });
    expect(
      combo.props('options').some(option => option.value.endsWith('.total'))
    ).toBe(false);
    combo.vm.$emit('update:modelValue', 'contact.email');
    expect(wrapper.emitted('update:modelValue')).toEqual([['contact.email']]);
    wrapper.unmount();
  });

  it('shows empty search results, forwards disabled/errors and floats instead of taking room in the form', async () => {
    const wrapper = mountPicker({ hasError: true });
    const combo = wrapper.getComponent(ComboBox);
    expect(combo.props('hasError')).toBe(true);
    expect(combo.props('teleport')).toBe(true);
    // A compact trigger (a small button) still opens a list wide enough to read the names.
    expect(combo.props('menuMinWidth')).toBe('17rem');
    // The list floats over the screen: no portal inside the form that would push the fields below it.
    expect(wrapper.find('[data-variable-picker-portal]').exists()).toBe(false);
    await combo.get('button').trigger('click');
    await combo.get('input[type="search"]').setValue('missing-variable');
    expect(combo.findAll('[role="option"]')).toHaveLength(0);
    expect(combo.text()).toContain('No variables found');
    await wrapper.setProps({ disabled: true });
    expect(combo.get('button').attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });

  it('opens the existing contact attribute modal only for admins and refreshes on close', async () => {
    const refresh = vi.fn();
    const wrapper = mountPicker({ attributes: [] }, 'administrator', refresh);
    const combo = wrapper.getComponent(ComboBox);
    await combo.get('button').trigger('click');
    await combo
      .get('[data-testid="variable-create-attribute"]')
      .trigger('click');
    await flushPromises();
    const modal = wrapper.getComponent({ name: 'AddAttribute' });
    expect(modal.props('selectedAttributeModelTab')).toBe(1);
    expect(combo.get('button').attributes('aria-expanded')).toBe('false');
    await modal.props('onClose')();
    expect(refresh).toHaveBeenCalledOnce();
    expect(wrapper.findComponent({ name: 'AddAttribute' }).exists()).toBe(
      false
    );
    wrapper.unmount();
    const agentPicker = mountPicker({}, 'agent');
    expect(
      agentPicker.find('[data-testid="variable-create-attribute"]').exists()
    ).toBe(false);
    agentPicker.unmount();
  });
});
