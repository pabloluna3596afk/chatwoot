import { mount } from '@vue/test-utils';
import FlowBlockEditor from '../FlowBlockEditor.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false }),
}));

const definition = {
  screens: [
    {
      blocks: [
        {
          type: 'dropdown',
          key: 'tipo',
          label: 'Tipo',
          options: [
            { id: 'a', title: 'A' },
            { id: 'otro', title: 'Otro' },
          ],
        },
        { type: 'short_text', key: 'detalle', label: 'Detalle' },
      ],
    },
  ],
};

const mountBlock = (blockIndex, props = {}) =>
  mount(FlowBlockEditor, {
    props: {
      modelValue: definition.screens[0].blocks[blockIndex],
      definition,
      screenIndex: 0,
      blockIndex,
      ...props,
    },
    global: { mocks: { $t: key => key } },
  });

const lastUpdate = wrapper => wrapper.emitted('update:modelValue').at(-1)[0];

describe('FlowBlockEditor', () => {
  it('writes the name of the answer from the label until the name is set by hand', async () => {
    const wrapper = mountBlock(1, {
      modelValue: { type: 'short_text', key: 'short_text', label: '' },
    });

    await wrapper
      .get('[data-testid="flow-block-label"] input')
      .setValue('Número de cédula');
    expect(lastUpdate(wrapper)).toMatchObject({
      label: 'Número de cédula',
      key: 'numero_de_cedula',
    });

    const custom = mountBlock(1, {
      modelValue: { type: 'short_text', key: 'mi_dato', label: 'Detalle' },
    });
    await custom
      .get('[data-testid="flow-block-label"] input')
      .setValue('Detalle nuevo');
    expect(lastUpdate(custom)).toEqual({
      type: 'short_text',
      key: 'mi_dato',
      label: 'Detalle nuevo',
    });
  });

  it('gives an option its id from its title and adds and removes options', async () => {
    const wrapper = mountBlock(0);

    await wrapper
      .findAll('[data-testid="flow-options"] input')[0]
      .setValue('Sí, claro');
    expect(lastUpdate(wrapper).options[0]).toEqual({
      id: 'si_claro',
      title: 'Sí, claro',
    });

    await wrapper.get('[data-testid="flow-option-add"]').trigger('click');
    expect(lastUpdate(wrapper).options).toHaveLength(3);
  });

  it('turns a condition on with the first earlier answer and its first option, and off again', async () => {
    const wrapper = mountBlock(1);

    await wrapper.get('[data-testid="flow-condition-toggle"]').trigger('click');
    expect(lastUpdate(wrapper).visible_when).toEqual({
      key: 'tipo',
      op: 'equals',
      value: 'a',
    });

    const on = mountBlock(1, {
      modelValue: {
        ...definition.screens[0].blocks[1],
        visible_when: { key: 'tipo', op: 'equals', value: 'a' },
      },
    });
    expect(on.find('[data-testid="flow-condition"]').exists()).toBe(true);
    await on.get('[data-testid="flow-condition-toggle"]').trigger('click');
    expect(lastUpdate(on)).not.toHaveProperty('visible_when');
  });

  it('cannot start a condition with no earlier answer to look at', () => {
    const wrapper = mountBlock(0);

    expect(wrapper.text()).toContain(
      'WHATSAPP_FLOWS.EDITOR.CONDITION_NEEDS_ANSWER'
    );
  });

  it('asks the page to remove or move the block', async () => {
    const wrapper = mountBlock(1);

    await wrapper.get('[data-testid="flow-block-remove"]').trigger('click');
    expect(wrapper.emitted('remove')).toHaveLength(1);
  });

  it('edits a text block with its text only and shows the errors of the block', () => {
    const wrapper = mountBlock(0, {
      modelValue: { type: 'heading', text: 'Hola' },
      errors: [
        {
          code: 'text_too_long',
          path: 'screens.0.blocks.0.text',
          details: { limit: 80 },
        },
      ],
    });

    expect(wrapper.find('[data-testid="flow-block-label"]').exists()).toBe(
      false
    );
    expect(wrapper.find('textarea').element.value).toBe('Hola');
    expect(wrapper.text()).toContain('text_too_long');
  });
});
