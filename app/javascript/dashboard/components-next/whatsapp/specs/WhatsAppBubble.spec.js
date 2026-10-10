import { mount } from '@vue/test-utils';
import WhatsAppBubble from '../WhatsAppBubble.vue';
import {
  bubbleFromTemplate,
  fillVariables,
  variablesFromTemplate,
} from '../bubbleFromTemplate';

describe('WhatsAppBubble', () => {
  it('draws header, body with small gaps for blank lines, footer and typed buttons', () => {
    const wrapper = mount(WhatsAppBubble, {
      props: {
        header: 'Pedido',
        headerMedia: 'IMAGE',
        body: 'Hola\n\nTu pedido llegó',
        footer: 'Equipo',
        buttons: [
          { text: 'Ver', type: 'URL' },
          { text: 'Llamar', type: 'PHONE_NUMBER' },
          'Texto simple',
        ],
      },
    });
    expect(wrapper.find('[data-testid="bubble-media"]').exists()).toBe(true);
    const body = wrapper.get('[data-testid="send-center-preview-body"]');
    expect(body.findAll('p').map(p => p.text())).toEqual([
      'Hola',
      'Tu pedido llegó',
    ]);
    expect(
      body.findAll('div').filter(el => el.classes().includes('h-1.5'))
    ).toHaveLength(1);
    expect(wrapper.text()).toContain('Equipo');
    expect(wrapper.findAll('[data-testid="bubble-button"]')).toHaveLength(3);
    expect(wrapper.html()).toContain('i-lucide-external-link');
    expect(wrapper.html()).toContain('i-lucide-phone');
  });

  it('uses the Flow icon on every button when it is a Flow message', () => {
    const wrapper = mount(WhatsAppBubble, {
      props: { body: 'x', buttons: ['Abrir Flow'], flow: true },
    });
    expect(wrapper.html()).toContain('i-lucide-workflow');
  });
});

describe('bubbleFromTemplate', () => {
  const template = {
    name: 't',
    language: 'es',
    parameter_format: 'POSITIONAL',
    components: [
      { type: 'HEADER', format: 'TEXT', text: 'Hola {{1}}' },
      { type: 'BODY', text: 'Pedido {{1}}\n\nLlega {{2}}' },
      { type: 'FOOTER', text: 'Gracias' },
      {
        type: 'BUTTONS',
        buttons: [{ type: 'URL', text: 'Seguir', url: 'https://x/{{1}}' }],
      },
    ],
  };

  it('fills example values and keeps [name] for the missing ones', () => {
    expect(fillVariables('a {{1}} b {{2}}', { 1: 'Ana' })).toBe('a Ana b [2]');
  });

  it('maps a Meta template to the bubble props with footer and button types', () => {
    const props = bubbleFromTemplate(template, { 1: 'Ana', 2: 'viernes' });
    expect(props.header).toBe('Hola Ana');
    expect(props.body).toBe('Pedido Ana\n\nLlega viernes');
    expect(props.footer).toBe('Gracias');
    expect(props.buttons).toEqual([{ text: 'Seguir', type: 'URL' }]);
  });

  it('takes examples from the body and header, not from a button URL', () => {
    const variables = variablesFromTemplate({
      components: [
        {
          type: 'HEADER',
          format: 'TEXT',
          text: 'Hola {{1}}',
          example: { header_text: ['Ana'] },
        },
        {
          type: 'BODY',
          text: '{{1}} {{2}}',
          example: { body_text: [['uno', 'dos']] },
        },
        {
          type: 'BUTTONS',
          buttons: [
            {
              type: 'URL',
              text: 'Ver',
              url: 'https://x/{{2}}',
              example: ['https://x/123'],
            },
          ],
        },
      ],
    });
    expect(variables).toEqual({ 1: 'uno', 2: 'dos' });
  });

  it('flags a media header instead of printing its text', () => {
    const media = {
      ...template,
      components: [
        { type: 'HEADER', format: 'IMAGE', example: {} },
        { type: 'BODY', text: 'Hola' },
      ],
    };
    const props = bubbleFromTemplate(media);
    expect(props.headerMedia).toBe('IMAGE');
    expect(props.header).toBe('');
  });
});
