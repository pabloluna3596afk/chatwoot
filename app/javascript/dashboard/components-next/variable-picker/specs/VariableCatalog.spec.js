import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import VariablePicker from '../VariablePicker.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import VariablesAPI from 'dashboard/api/variables';
import en from 'dashboard/i18n/locale/en/variables.json';

vi.mock('dashboard/api/variables', () => ({ default: { catalog: vi.fn() } }));

const descriptor = (scope, key, id) => ({
  id: `${scope}.custom_attribute:${id}`,
  reference: { scope, kind: 'custom_attribute', definitionId: id },
  key,
  label: key,
  group: scope,
  type: 'text',
  options: [],
  aliases: [],
  legacyPaths: [`${scope}.custom_attribute.${key}`],
  expression: `{{ ${scope}.custom_attribute['${key}'] }}`,
  available: scope === 'contact',
  readable: true,
  writable: true,
  writeContexts: ['whatsapp_flow'],
  managedBy: null,
});

it('MV-08/09: offers exact keys by definition identity and never turns company into contact', async () => {
  VariablesAPI.catalog.mockResolvedValue({
    data: {
      variables: [
        descriptor('contact', 'nivel-vip', 1),
        descriptor('contact', 'nivel.vip', 2),
        descriptor('contact', 'categoría', 3),
        descriptor('company', 'empresa', 4),
      ],
    },
  });
  const wrapper = mount(VariablePicker, {
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        createStore({
          getters: {
            getCurrentAccountId: () => 841,
            getCurrentRole: () => 'agent',
            'attributes/getAttributes': () => [],
          },
          actions: { 'attributes/get': vi.fn() },
        }),
      ],
      stubs: { Teleport: true },
    },
  });
  await flushPromises();
  const combo = wrapper.getComponent(ComboBox);
  expect(combo.props('options').map(option => option.value)).toEqual([
    'contact.custom_attribute:1',
    'contact.custom_attribute:2',
    'contact.custom_attribute:3',
  ]);
  combo.vm.$emit('update:modelValue', 'contact.custom_attribute:1');
  expect(wrapper.emitted('select')[0][0].expression).toBe(
    "{{ contact.custom_attribute['nivel-vip'] }}"
  );
  wrapper.unmount();
});
