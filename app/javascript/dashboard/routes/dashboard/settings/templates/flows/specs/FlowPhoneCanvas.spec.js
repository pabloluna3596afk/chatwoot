import { mount } from '@vue/test-utils';
import FlowPhoneCanvas from '../FlowPhoneCanvas.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, args) => (args ? `${key} ${JSON.stringify(args)}` : key),
    te: () => false,
  }),
}));

const definition = {
  screens: [
    {
      title: 'Tu cita',
      button: '',
      blocks: [
        { type: 'heading', text: 'Hola' },
        {
          type: 'radio',
          key: 'necesitas',
          label: '¿Qué necesitas?',
          required: true,
          options: [
            { id: 'consulta', title: 'Consulta' },
            { id: 'otro', title: 'Otro' },
          ],
        },
        {
          type: 'long_text',
          key: 'mas',
          label: 'Cuéntanos más',
          visible_when: { key: 'necesitas', op: 'equals', value: 'otro' },
        },
      ],
    },
  ],
};

const mountCanvas = (props = {}) =>
  mount(FlowPhoneCanvas, {
    props: { definition, screenIndex: 0, ...props },
    global: { mocks: { $t: key => key } },
  });

describe('FlowPhoneCanvas', () => {
  it('draws the blocks compactly: no header row with the type name', () => {
    const wrapper = mountCanvas();

    const blocks = wrapper.findAll('[data-testid="flow-canvas-block"]');
    expect(blocks).toHaveLength(3);
    expect(blocks[0].text()).toBe('Hola');
    expect(blocks[1].text()).toContain('¿Qué necesitas? *');
    expect(blocks[1].text()).toContain('Consulta');
    expect(wrapper.text()).not.toContain('WHATSAPP_FLOWS.BLOCKS.');
  });

  it('outlines only the selected block and tells the page when one is clicked', async () => {
    const wrapper = mountCanvas({ selected: 1 });
    const blocks = wrapper.findAll('[data-testid="flow-canvas-block"]');

    expect(blocks[1].attributes('data-selected')).toBe('true');
    expect(blocks[0].attributes('data-selected')).toBe('false');

    await blocks[2].trigger('click');
    expect(wrapper.emitted('select')[0]).toEqual([2]);
  });

  it('marks a conditional block with the question and the answer it depends on', () => {
    const wrapper = mountCanvas();

    const chip = wrapper.get('[data-testid="flow-canvas-cond"]');
    expect(chip.text()).toContain('ONLY_IF');
    expect(chip.text()).toContain('¿Qué necesitas?');
    expect(chip.text()).toContain('Otro');
  });

  it('shows move and remove on the selected block only', async () => {
    const none = mountCanvas();
    expect(none.find('[data-testid="flow-canvas-remove"]').exists()).toBe(
      false
    );

    const wrapper = mountCanvas({ selected: 1 });
    await wrapper.get('[data-testid="flow-canvas-up"]').trigger('click');
    await wrapper.get('[data-testid="flow-canvas-remove"]').trigger('click');
    expect(wrapper.emitted('move')[0]).toEqual([1, -1]);
    expect(wrapper.emitted('remove')[0]).toEqual([1]);
  });

  it('uses Enviar on the last screen when the screen has no button text', () => {
    const wrapper = mountCanvas();

    expect(wrapper.text()).toContain('WHATSAPP_FLOWS.EDITOR.BUTTON_LAST');
  });
});
