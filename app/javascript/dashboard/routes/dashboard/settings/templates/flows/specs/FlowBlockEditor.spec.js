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
  it('groups writable targets, saves the Liquid path and removes the optional mapping', async () => {
    const wrapper = mountBlock(1, {
      attributes: [
        {
          attribute_key: 'cedula',
          attribute_display_name: 'Cedula',
          attribute_model: 'contact_attribute',
          attribute_display_type: 'text',
        },
        {
          attribute_key: 'secret',
          attribute_model: 'conversation_attribute',
          attribute_display_type: 'text',
        },
      ],
    });
    const select = wrapper.get('[data-testid="flow-save-to"]');
    expect(select.findAll('optgroup')).toHaveLength(2);
    expect(select.html()).toContain('contact.custom_attribute.cedula');
    expect(select.html()).not.toContain('conversation.custom_attribute');
    expect(select.html()).not.toContain('contact.first_name');
    await select.setValue('contact.email');
    expect(lastUpdate(wrapper).save_to).toEqual({ target: 'contact.email' });
    await select.setValue('');
    expect(lastUpdate(wrapper)).not.toHaveProperty('save_to');
  });

  it('restricts optin to checkbox attributes and does not offer destinations for files', () => {
    const attributes = [
      {
        attribute_key: 'accept',
        attribute_model: 'contact_attribute',
        attribute_display_type: 'checkbox',
      },
    ];
    const optin = mountBlock(1, {
      modelValue: { type: 'optin', key: 'accept', label: 'Accept' },
      attributes,
    });
    expect(
      optin
        .findAll('[data-testid="flow-save-to"] option')
        .map(option => option.attributes('value'))
    ).toEqual(['', 'contact.custom_attribute.accept']);
    expect(
      mountBlock(1, {
        modelValue: { type: 'photo', key: 'photo', label: 'Photo' },
      })
        .find('[data-testid="flow-save-to"]')
        .exists()
    ).toBe(false);
  });
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

  describe('"Mostrar este campo" (the condition)', () => {
    const comboOf = (wrapper, testid) =>
      wrapper.findComponent(`[data-testid="${testid}"]`);

    it('offers "Siempre" and one "Solo si ..." per earlier pick-one question', () => {
      const wrapper = mountBlock(1);

      const options = comboOf(wrapper, 'flow-show').props('options');
      expect(options.map(option => option.value)).toEqual(['', 'tipo']);
      expect(options[0].label).toBe('WHATSAPP_FLOWS.EDITOR.SHOW_ALWAYS');
      expect(options[1].label).toBe('WHATSAPP_FLOWS.EDITOR.SHOW_IF');
      expect(wrapper.find('[data-testid="flow-condition-hint"]').exists()).toBe(
        false
      );
    });

    it('with no earlier pick-one question only offers "Siempre" and says what to add', () => {
      const wrapper = mountBlock(0);

      const options = comboOf(wrapper, 'flow-show').props('options');
      expect(options.map(option => option.value)).toEqual(['']);
      expect(wrapper.get('[data-testid="flow-condition-hint"]').text()).toBe(
        'WHATSAPP_FLOWS.EDITOR.SHOW_NEEDS_QUESTION'
      );
      expect(wrapper.find('[data-testid="flow-show-value"]').exists()).toBe(
        false
      );
    });

    it('does not offer a short text as the question of a condition', () => {
      const wrapper = mountBlock(1, {
        definition: {
          screens: [
            {
              blocks: [
                { type: 'short_text', key: 'nombre', label: 'Nombre' },
                { type: 'short_text', key: 'detalle', label: 'Detalle' },
              ],
            },
          ],
        },
      });

      expect(
        comboOf(wrapper, 'flow-show')
          .props('options')
          .map(option => option.value)
      ).toEqual(['']);
    });

    it('picking a question starts the condition with its first option and makes the field optional', async () => {
      const wrapper = mountBlock(1, {
        modelValue: { ...definition.screens[0].blocks[1], required: true },
      });

      comboOf(wrapper, 'flow-show').vm.$emit('update:modelValue', 'tipo');

      expect(lastUpdate(wrapper)).toMatchObject({
        required: false,
        visible_when: { key: 'tipo', op: 'equals', value: 'a' },
      });
    });

    it('shows the value select once a question is picked and writes the value', async () => {
      const wrapper = mountBlock(1, {
        modelValue: {
          ...definition.screens[0].blocks[1],
          visible_when: { key: 'tipo', op: 'equals', value: 'a' },
        },
      });

      expect(
        comboOf(wrapper, 'flow-show-value')
          .props('options')
          .map(option => option.value)
      ).toEqual(['a', 'otro']);
      comboOf(wrapper, 'flow-show-value').vm.$emit('update:modelValue', 'otro');
      expect(lastUpdate(wrapper).visible_when).toEqual({
        key: 'tipo',
        op: 'equals',
        value: 'otro',
      });
    });

    it('picking "Siempre" takes the condition away', async () => {
      const wrapper = mountBlock(1, {
        modelValue: {
          ...definition.screens[0].blocks[1],
          visible_when: { key: 'tipo', op: 'equals', value: 'a' },
        },
      });

      comboOf(wrapper, 'flow-show').vm.$emit('update:modelValue', '');

      expect(lastUpdate(wrapper)).not.toHaveProperty('visible_when');
    });
  });

  it('lets the helper of the answer name wrap instead of truncating it', () => {
    const wrapper = mountBlock(1);

    expect(
      wrapper.get('[data-testid="flow-key-help"]').classes()
    ).not.toContain('truncate');
  });

  it('is only the settings: no card header with the type name or move and remove buttons', () => {
    const wrapper = mountBlock(1);

    expect(wrapper.find('[data-testid="flow-block-remove"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).not.toContain('WHATSAPP_FLOWS.BLOCKS.');
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
