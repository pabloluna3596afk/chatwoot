import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import TemplateVariableInput from '../TemplateVariableInput.vue';
import WhatsAppTemplateParser from '../../whatsapp/WhatsAppTemplateParser.vue';
import ContentTemplateParser from '../../content-templates/ContentTemplateParser.vue';
import VariablesAPI from 'dashboard/api/variables';
import catalog from '../../variable-picker/specs/catalog.json';
import en from 'dashboard/i18n/locale/en/variables.json';
import es from 'dashboard/i18n/locale/es/variables.json';

vi.mock('dashboard/api/variables', () => ({
  default: { catalog: vi.fn(), preview: vi.fn() },
}));
let wrapper;
let account = 5000;
beforeEach(() => {
  account += 1;
  VariablesAPI.catalog.mockResolvedValue({ data: structuredClone(catalog) });
});
afterEach(() => wrapper?.unmount());

it.each([
  [
    WhatsAppTemplateParser,
    {
      name: 'test',
      components: [
        { type: 'HEADER', format: 'TEXT', text: '{{title}}' },
        { type: 'BODY', text: '{{1}} / {{2}}' },
      ],
    },
    3,
  ],
  [ContentTemplateParser, { friendly_name: 'test', body: '{{1}} / {{2}}' }, 2],
])(
  'edits fields, opens the icon picker and inserts into only its field for %s',
  async (parser, template, count) => {
    wrapper = mount(parser, {
      props: { template },
      attachTo: document.body,
      global: {
        stubs: { Teleport: true },
        plugins: [
          createI18n({ legacy: false, locale: 'es', messages: { en, es } }),
          createStore({
            getters: {
              getCurrentAccountId: () => account,
              getCurrentRole: () => 'agent',
              'inboxes/getInboxById': () => () => null,
            },
          }),
        ],
      },
    });
    await flushPromises();
    const fields = wrapper.findAllComponents(TemplateVariableInput);
    expect(fields).toHaveLength(count);
    const field = fields[count - 2];
    const input = field.get('input[type="text"]');
    await input.setValue('Hola');
    const trigger = field.get('button[aria-haspopup="listbox"]');
    expect(trigger.attributes('aria-label')).toBe('Insertar variable');
    expect(field.get('[title]').attributes('title')).toBe('Insertar variable');
    expect(trigger.text()).toBe('');
    expect(trigger.attributes('aria-expanded')).toBe('false');
    await trigger.trigger('click');
    await flushPromises();
    expect(trigger.attributes('aria-expanded')).toBe('true');
    await field
      .get('[role="option"][title="Nombre del contacto"]')
      .trigger('click');
    await flushPromises();
    expect(input.element.value).toBe('Hola {{ contact.name }}');
    expect(trigger.attributes('aria-expanded')).toBe('false');
    expect(fields[count - 1].get('input[type="text"]').element.value).toBe('');
    await input.setValue('Ana');
    await fields[count - 1].get('input[type="text"]').setValue('Martes');
    if (count === 3) await fields[0].get('input[type="text"]').setValue('Cita');
    wrapper.vm.sendMessage();
    const params =
      wrapper.emitted('sendMessage')[0][0].templateParams.processed_params;
    expect(count === 3 ? params.body : params).toEqual({
      1: 'Ana',
      2: 'Martes',
    });
  }
);
