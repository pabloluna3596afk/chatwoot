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
        sources: { body: { nombre: 'inbox' } },
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

  it('shows the rendered WhatsApp message and variable details', () => {
    const wrapper = mountPreview();

    expect(wrapper.get('[data-testid="bubble"]').text()).toBe('Hola Ana Pérez');
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.VARIABLES_TITLE'
    );
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.ASSIGNED_HERE'
    );
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.ENVIOS.PREVIEW_PANEL.INBOX'
    );
  });

  it('shows missing-variable placeholders and hides the bubble for an unavailable template', () => {
    const incomplete = mountPreview({ params: { body: {} }, complete: false });
    expect(incomplete.get('[data-testid="bubble"]').text()).toBe(
      'Hola [nombre]'
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
