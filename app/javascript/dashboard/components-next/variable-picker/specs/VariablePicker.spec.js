import { mount, flushPromises, config } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import VariablePicker from '../VariablePicker.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import VariablesAPI from 'dashboard/api/variables';
import { writableFor } from 'dashboard/helper/templateVariableBindings';
import en from 'dashboard/i18n/locale/en/variables.json';
import es from 'dashboard/i18n/locale/es/variables.json';
import catalog from './catalog.json';

vi.mock('dashboard/api/variables', () => ({ default: { catalog: vi.fn() } }));
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
const i18n = createI18n({ legacy: false, locale: 'en', messages: { en, es } });
config.global.plugins = [i18n];
let account = 1;
const wrappers = [];
const mountPicker = (props = {}, role = 'administrator', id = account) => {
  const store = createStore({
    getters: { getCurrentRole: () => role, getCurrentAccountId: () => id },
    actions: { 'attributes/get': vi.fn() },
  });
  const wrapper = mount(VariablePicker, {
    props,
    attachTo: document.body,
    global: { plugins: [store], stubs: { Teleport: true } },
  });
  wrappers.push(wrapper);
  return wrapper;
};
beforeEach(() => {
  account += 1;
  VariablesAPI.catalog.mockResolvedValue({ data: structuredClone(catalog) });
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  i18n.global.locale.value = 'en';
});

it('uses one shared request for the same account/surface and isolates other accounts and surfaces', async () => {
  mountPicker();
  mountPicker();
  mountPicker({ surface: 'automation' });
  mountPicker({}, 'agent', account + 1000);
  await flushPromises();
  expect(VariablesAPI.catalog).toHaveBeenCalledTimes(3);
  expect(VariablesAPI.catalog).toHaveBeenCalledWith(account, 'message');
  expect(VariablesAPI.catalog).toHaveBeenCalledWith(account, 'automation');
});
it('reads IDs and excludes unavailable contexts; read still includes managed attributes', async () => {
  const wrapper = mountPicker();
  await flushPromises();
  const combo = wrapper.getComponent(ComboBox);
  expect(combo.props('groups').map(group => group.key)).toEqual([
    'system',
    'contact',
    'conversation',
  ]);
  expect(combo.props('options')).toContainEqual({
    value: 'contact.custom_attribute:14',
    label: 'Nivel VIP',
    group: 'contact',
  });
  expect(
    combo
      .props('options')
      .some(option => option.value === 'contact.custom_attribute:13')
  ).toBe(true);
  expect(
    combo
      .props('options')
      .some(option => option.value.startsWith('appointment.'))
  ).toBe(false);
  expect(
    combo.props('options').some(option => option.value.startsWith('company.'))
  ).toBe(false);
});
it('writes only compatible unmanaged destinations and adapts legacy paths at the boundary', async () => {
  const wrapper = mountPicker({
    mode: 'write',
    valueFormat: 'path',
    scopes: ['system', 'contact'],
    filter: binding => writableFor(binding, { type: 'short_text' }),
    allowNone: true,
  });
  await flushPromises();
  const combo = wrapper.getComponent(ComboBox);
  expect(combo.props('options')).toContainEqual({
    value: 'contact.custom_attribute.nivel-vip',
    label: 'Nivel VIP',
    group: 'contact',
  });
  expect(
    combo.props('options').some(option => option.value.endsWith('.total'))
  ).toBe(false);
  expect(combo.props('options')[0]).toEqual({
    value: '',
    label: 'Do not save',
  });
});
it('shares translated labels and keys in English and neutral Spanish', async () => {
  expect(Object.keys(es.VARIABLE_PICKER)).toEqual(
    Object.keys(en.VARIABLE_PICKER)
  );
  expect(Object.keys(es.VARIABLE_PICKER.GROUPS)).toEqual(
    Object.keys(en.VARIABLE_PICKER.GROUPS)
  );
  i18n.global.locale.value = 'es';
  const wrapper = mountPicker({ valueFormat: 'alias' });
  await flushPromises();
  const combo = wrapper.getComponent(ComboBox);
  expect(combo.props('options')).toContainEqual({
    value: 'telefono',
    label: 'Teléfono (telefono)',
    group: 'system',
  });
  await combo.get('button').trigger('click');
  expect(combo.get('input[type="search"]').attributes('placeholder')).toBe(
    es.VARIABLE_PICKER.SEARCH
  );
});
it('searches and selects exact descriptor IDs', async () => {
  const wrapper = mountPicker();
  await flushPromises();
  const combo = wrapper.getComponent(ComboBox);
  await combo.get('button').trigger('click');
  await combo.get('input[type="search"]').setValue('Nivel VIP');
  expect(combo.findAll('[role="option"]')).toHaveLength(1);
  await combo.get('[role="option"]').trigger('click');
  expect(wrapper.emitted('update:modelValue')[0]).toEqual([
    'contact.custom_attribute:14',
  ]);
});
it('preserves an unknown mapping and diagnoses it after loading without emitting a change', async () => {
  const wrapper = mountPicker({ modelValue: 'contact.custom_attribute:999' });
  await flushPromises();
  expect(wrapper.text()).toContain(en.VARIABLE_PICKER.UNKNOWN);
  expect(wrapper.getComponent(ComboBox).get('button').text()).toContain(
    'contact.custom_attribute:999'
  );
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
});
it('shows loading, retries errors and preserves the selected value throughout', async () => {
  let reject;
  VariablesAPI.catalog.mockImplementationOnce(
    () =>
      new Promise((resolve, failure) => {
        reject = failure;
      })
  );
  const wrapper = mountPicker({ modelValue: 'contact.name' });
  expect(wrapper.text()).toContain(en.VARIABLE_PICKER.LOADING);
  reject(new Error('network'));
  await flushPromises();
  expect(wrapper.text()).toContain(en.VARIABLE_PICKER.ERROR);
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  await wrapper.get('[role="alert"] button').trigger('click');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  expect(wrapper.getComponent(ComboBox).props('modelValue')).toBe(
    'contact.name'
  );
});
it('shows the empty state and empty search results without changing values', async () => {
  VariablesAPI.catalog.mockResolvedValueOnce({ data: { variables: [] } });
  const wrapper = mountPicker();
  await flushPromises();
  const combo = wrapper.getComponent(ComboBox);
  await combo.get('button').trigger('click');
  expect(combo.text()).toContain(en.VARIABLE_PICKER.EMPTY);
  expect(combo.findAll('[role="option"]')).toHaveLength(0);
});
it('uses the existing attribute modal for admins, refreshes the shared catalog, hides CTA for agents', async () => {
  const wrapper = mountPicker();
  await flushPromises();
  const combo = wrapper.getComponent(ComboBox);
  await combo.get('button').trigger('click');
  await combo.get('[data-testid="variable-create-attribute"]').trigger('click');
  await flushPromises();
  await wrapper.getComponent({ name: 'AddAttribute' }).props('onClose')();
  expect(VariablesAPI.catalog).toHaveBeenCalledTimes(2);
  const agent = mountPicker({}, 'agent');
  await flushPromises();
  await agent.getComponent(ComboBox).get('button').trigger('click');
  expect(agent.find('[data-testid="variable-create-attribute"]').exists()).toBe(
    false
  );
});
