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
    global: {
      mocks: { $t: key => key },
      stubs: {
        Dialog: {
          name: 'Dialog',
          template: '<div />',
          methods: { open: vi.fn(), close: vi.fn() },
        },
      },
    },
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

  it('keeps editing actions and technical condition badges outside the customer preview', async () => {
    const wrapper = mountCanvas({ selected: 1 });
    expect(wrapper.find('[data-testid="flow-canvas-cond"]').exists()).toBe(
      false
    );
    expect(wrapper.findAll('button')).toHaveLength(0);
    expect(wrapper.find('[data-testid="flow-block-handle"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="flow-canvas-remove"]').exists()).toBe(
      false
    );
    expect(wrapper.findAll('h3')).toHaveLength(1);
    expect(wrapper.get('h3').text()).toBe('Tu cita');
    const selected = wrapper.findAll('[data-testid="flow-canvas-block"]')[1];
    expect(selected.classes()).toContain('border-n-brand');
    expect(selected.classes()).not.toContain('bg-n-brand/10');
    await selected.trigger('keydown', { key: 'Enter' });
    expect(wrapper.emitted('select')[0]).toEqual([1]);
  });

  it('shows a missing button error instead of inventing button text', () => {
    const wrapper = mountCanvas();

    expect(wrapper.get('[data-testid="flow-canvas-footer"]').text()).toBe(
      'WHATSAPP_FLOWS.ERRORS.button_required'
    );
    expect(wrapper.text()).not.toContain('WHATSAPP_FLOWS.EDITOR.BUTTON_LAST');
  });

  it('guides the user on an empty screen and supports selecting a block with Space', async () => {
    const empty = mountCanvas({
      definition: { screens: [{ title: 'Empty', button: 'Send', blocks: [] }] },
    });
    expect(empty.get('[data-testid="flow-canvas-empty"]').text()).toContain(
      'WHATSAPP_FLOWS.EDITOR.EMPTY_SCREEN_HINT'
    );
    const wrapper = mountCanvas();
    await wrapper.get('[data-testid="flow-canvas-block"]').trigger('keydown', {
      key: ' ',
    });
    expect(wrapper.emitted('select')[0]).toEqual([0]);
  });
});
