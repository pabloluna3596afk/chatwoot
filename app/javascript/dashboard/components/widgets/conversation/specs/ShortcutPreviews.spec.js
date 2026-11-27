import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import CannedResponse from '../CannedResponse.vue';
import CannedResponsesPicker from '../CannedResponses/CannedResponsesPicker.vue';
import ShortcutPreview from 'dashboard/components-next/preview-picker/ShortcutPreview.vue';
import CaretAnchoredPicker from 'dashboard/components-next/preview-picker/CaretAnchoredPicker.vue';
import es from 'dashboard/i18n/locale/es/conversation.json';

const content =
  'Hola **{{contact.name}}**\n{{agent.name}}\n\n- *Detalle*\n- `código`\n\n{{conversation.custom_attribute.monto}} {{missing}}';
const response = { id: 1, short_code: 'hola', content };
const variables = {
  'contact.name': 'Ana',
  'agent.name': 'Luis',
  'conversation.custom_attribute.monto': 0,
};
let wrapper;
afterEach(() => wrapper?.unmount());

it.each([CannedResponse, CannedResponsesPicker])(
  'resolves preview and list reactively without changing selection content: $name',
  async component => {
    const store = createStore({
      getters: { getCannedResponses: () => [response], getUIFlags: () => ({}) },
      actions: { getCannedResponse: vi.fn() },
    });
    wrapper = mount(component, {
      props: { variables },
      global: {
        plugins: [
          store,
          VueDOMPurifyHTML,
          createI18n({
            legacy: false,
            locale: 'es',
            messages: { es },
            missingWarn: false,
            fallbackWarn: false,
          }),
        ],
        stubs: {
          CaretAnchoredPicker: {
            props: ['items'],
            template:
              '<div><span class="snippet" v-dompurify-html="items[0]?.subtitle"/><slot name="preview" :item="items[0]"/></div>',
          },
        },
      },
    });
    const preview = wrapper.getComponent(ShortcutPreview);
    expect(preview.get('strong').text()).toBe('Ana');
    expect(preview.get('em').text()).toBe('Detalle');
    expect(preview.findAll('li')).toHaveLength(2);
    expect(preview.find('br').exists()).toBe(true);
    expect(preview.text()).toContain('0 sin valor');
    expect(preview.findAll('code').map(node => node.text())).toEqual([
      'código',
      'sin valor',
    ]);
    expect(preview.classes()).toContain('[overflow-wrap:anywhere]');
    expect(preview.classes()).toContain('prose-code:bg-n-alpha-black2');
    const snippet = component === CannedResponse ? '.snippet' : 'p.truncate';
    expect(wrapper.get(snippet).text()).toContain('Ana');
    expect(wrapper.get(snippet).text()).toContain('sin valor');
    await wrapper.setProps({
      variables: { ...variables, 'contact.name': 'Bea' },
    });
    expect(preview.get('strong').text()).toBe('Bea');
    expect(wrapper.get(snippet).text()).toContain('Bea');
    if (component === CannedResponse) {
      const picker = wrapper.getComponent(CaretAnchoredPicker);
      picker.vm.$emit('select', picker.props('items')[0]);
      expect(wrapper.emitted('replace')).toEqual([[content]]);
    } else {
      expect(wrapper.find('.sm\\:flex-row').classes()).toContain('flex-col');
      expect(wrapper.get('p.truncate').classes()).toContain('truncate');
      await wrapper.get('button.text-start').trigger('click');
      expect(wrapper.emitted('onSelect')).toEqual([[response]]);
    }
  }
);

it('sanitizes malicious Markdown and HTML, and bounds long text and code', () => {
  wrapper = mount(ShortcutPreview, {
    props: {
      content:
        '<img src=x onerror=alert(1)>\n\n[attack](javascript:alert(1))\n\n```\n' +
        'x'.repeat(1000) +
        '\n```',
    },
    global: { plugins: [VueDOMPurifyHTML] },
  });
  expect(wrapper.find('img').exists()).toBe(false);
  expect(wrapper.find('[href^="javascript:"]').exists()).toBe(false);
  expect(wrapper.find('[onerror]').exists()).toBe(false);
  expect(wrapper.get('pre').text()).toContain('x'.repeat(1000));
  expect(wrapper.classes()).toContain('prose-pre:overflow-x-auto');
  expect(wrapper.classes()).toContain('min-w-0');
});
