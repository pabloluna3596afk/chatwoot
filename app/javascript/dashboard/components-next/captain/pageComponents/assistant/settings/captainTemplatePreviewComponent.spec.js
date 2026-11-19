import { mount } from '@vue/test-utils';
import CaptainTemplatePreview from './CaptainTemplatePreview.vue';

describe('CaptainTemplatePreview', () => {
  const template = {
    name: 'pedido_listo',
    language: 'es',
    category: 'UTILITY',
    components: [{ type: 'BODY', text: 'Hola {{nombre}}' }],
  };
  const mountPreview = (props = {}) =>
    mount(CaptainTemplatePreview, {
      props: {
        template,
        params: { body: { nombre: '{{ contact.name }}' } },
        sources: { body: { nombre: 'binding' } },
        previewValues: { '{{ contact.name }}': 'Ana Pérez' },
        inboxName: 'Ventas',
        ...props,
      },
      global: {
        mocks: { $t: key => key },
        stubs: {
          SidePanel: {
            props: ['title', 'description'],
            template: '<aside><slot /></aside>',
          },
          WhatsAppBubble: {
            props: ['header', 'body', 'footer', 'buttons'],
            template: '<div data-testid="bubble">{{ body }}</div>',
          },
        },
      },
    });

  it('renders the message using assigned data and identifies its source', () => {
    const wrapper = mountPreview();

    expect(wrapper.get('[data-testid="bubble"]').text()).toBe('Hola Ana Pérez');
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.VARIABLES_TITLE'
    );
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.SOURCE_BINDING'
    );
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.INBOX'
    );
  });

  it.each([
    ['alias', 'SOURCE_ALIAS'],
    ['binding', 'SOURCE_BINDING'],
    ['assistant', 'SOURCE_ASSISTANT'],
    ['legacy', 'SOURCE_LEGACY'],
  ])(
    'labels the %s source and accepts catalog sample keys',
    (source, label) => {
      const wrapper = mountPreview({
        sources: { body: { nombre: source } },
        previewValues: { 'contact.name': 'Ana' },
      });
      expect(wrapper.text()).toContain(`PREVIEW_PANEL.${label}`);
      expect(wrapper.get('[data-testid="bubble"]').text()).toBe('Hola Ana');
    }
  );

  it('marks missing variables and hides a no longer approved template', () => {
    const incomplete = mountPreview({ params: { body: {} }, complete: false });
    expect(incomplete.get('[data-testid="bubble"]').text()).toBe(
      'Hola {{nombre}}'
    );
    expect(incomplete.text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.MISSING_VARIABLES'
    );

    const unavailable = mountPreview({ available: false });
    expect(unavailable.find('[data-testid="bubble"]').exists()).toBe(false);
    expect(unavailable.text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.TEMPLATE_UNAVAILABLE'
    );
  });
});
