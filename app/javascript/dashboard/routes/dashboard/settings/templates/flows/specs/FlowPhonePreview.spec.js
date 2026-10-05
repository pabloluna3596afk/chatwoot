import { mount } from '@vue/test-utils';
import FlowPhonePreview from '../FlowPhonePreview.vue';

const definition = {
  schema_version: 1,
  screens: [
    {
      title: 'Tus datos',
      button: 'Continuar',
      blocks: [
        { type: 'heading', text: 'Hola' },
        {
          type: 'dropdown',
          key: 'tipo',
          label: 'Tipo',
          options: [
            { id: 'a', title: 'A' },
            { id: 'otro', title: 'Otro' },
          ],
        },
        {
          type: 'short_text',
          key: 'cual',
          label: '¿Cuál?',
          visible_when: { key: 'tipo', op: 'equals', value: 'otro' },
        },
      ],
    },
    {
      title: 'Adjuntos',
      button: 'Enviar',
      blocks: [
        { type: 'photo', key: 'foto', label: 'Foto' },
        {
          type: 'checkbox',
          key: 'temas',
          label: 'Temas',
          options: [{ id: 'x', title: 'X' }],
        },
      ],
    },
  ],
};

const mountPreview = () =>
  mount(FlowPhonePreview, {
    props: { definition },
    global: { mocks: { $t: key => key } },
  });

describe('FlowPhonePreview', () => {
  it('shows the first screen with its title, blocks and button', () => {
    const wrapper = mountPreview();

    expect(wrapper.text()).toContain('Tus datos');
    expect(wrapper.text()).toContain('Hola');
    expect(wrapper.get('[data-testid="flow-preview-footer"]').text()).toBe(
      'Continuar'
    );
    expect(wrapper.findAll('input')).toHaveLength(0);
    expect(wrapper.find('select').exists()).toBe(true);
  });

  it('shows a conditional block only when the answer it looks at matches', async () => {
    const wrapper = mountPreview();
    expect(wrapper.text()).not.toContain('¿Cuál?');

    await wrapper.get('select').setValue('otro');
    expect(wrapper.text()).toContain('¿Cuál?');

    await wrapper.get('select').setValue('a');
    expect(wrapper.text()).not.toContain('¿Cuál?');
  });

  it('goes to the next screen, finishes on the last one and can go back', async () => {
    const wrapper = mountPreview();

    await wrapper.get('[data-testid="flow-preview-footer"]').trigger('click');
    expect(wrapper.text()).toContain('Adjuntos');
    expect(wrapper.get('[data-testid="flow-preview-footer"]').text()).toBe(
      'Enviar'
    );
    expect(wrapper.text()).toContain('WHATSAPP_FLOWS.PREVIEW.ADD_PHOTO');

    await wrapper.get('[data-testid="flow-preview-footer"]').trigger('click');
    expect(wrapper.find('[data-testid="flow-preview-done"]').exists()).toBe(
      true
    );

    await wrapper.get('[data-testid="flow-preview-back"]').trigger('click');
    expect(wrapper.find('[data-testid="flow-preview-done"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain('Adjuntos');
  });

  it('lists the answers on the last screen', async () => {
    const wrapper = mountPreview();
    await wrapper.get('select').setValue('a');
    await wrapper.get('[data-testid="flow-preview-footer"]').trigger('click');
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('[data-testid="flow-preview-footer"]').trigger('click');

    expect(wrapper.get('[data-testid="flow-preview-done"]').text()).toContain(
      'tipo: a'
    );
    expect(wrapper.get('[data-testid="flow-preview-done"]').text()).toContain(
      'temas: x'
    );
  });

  it('jumps to a screen on request and shows one dot per screen', async () => {
    const wrapper = mountPreview();

    wrapper.vm.goTo(1);
    await wrapper.vm.$nextTick();

    expect(wrapper.text()).toContain('Adjuntos');
    expect(
      wrapper.findAll('[data-testid="flow-preview-dots"] button')
    ).toHaveLength(2);
  });

  it('stays on a screen that exists when screens are removed', async () => {
    const wrapper = mountPreview();
    wrapper.vm.goTo(1);
    await wrapper.vm.$nextTick();

    await wrapper.setProps({
      definition: { ...definition, screens: [definition.screens[0]] },
    });

    expect(wrapper.text()).toContain('Tus datos');
  });
});
