import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import AutomationActionWhatsAppTemplateInput from '../AutomationActionWhatsAppTemplateInput.vue';

const template = {
  id: 't1',
  name: 'confirmacion',
  language: 'es',
  parameter_format: 'NAMED',
  components: [{ type: 'BODY', text: 'Hola {{nombre}}' }],
};
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: name =>
    ref(
      {
        'inboxes/getWhatsAppInboxes': [{ id: 1, name: 'Soporte' }],
        'inboxes/getFilteredWhatsAppTemplates': () => [template],
        'attributes/getAttributes': [],
      }[name]
    ),
}));

const ParserStub = {
  name: 'WhatsAppTemplateParser',
  props: ['template', 'defaultValues', 'variableOptions'],
  template: '<div data-testid="parser" />',
};

describe('AutomationActionWhatsAppTemplateInput', () => {
  it('fills named variables by default and offers only what an automation can resolve', async () => {
    const wrapper = mount(AutomationActionWhatsAppTemplateInput, {
      props: {
        modelValue: { inbox_id: 1, name: 'confirmacion', language: 'es' },
      },
      global: {
        mocks: { $t: key => key },
        stubs: { WhatsAppTemplateParser: ParserStub, ComboBox: true },
      },
    });
    wrapper.vm.$.setupState.templateId = 't1';
    await wrapper.vm.$nextTick();
    const parser = wrapper.findComponent(ParserStub);
    expect(parser.exists()).toBe(true);
    expect(parser.props('defaultValues').nombre).toContain('contact.name');
    const keys = parser.props('variableOptions').map(option => option.key);
    expect(keys).toContain('contact.name');
    expect(keys.some(key => key.startsWith('appointment.'))).toBe(false);
    wrapper.unmount();
  });
});
