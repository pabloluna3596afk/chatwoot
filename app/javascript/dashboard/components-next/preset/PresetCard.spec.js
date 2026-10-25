import { mount } from '@vue/test-utils';
import PresetCard from './PresetCard.vue';

describe('PresetCard', () => {
  const props = {
    id: 'welcome',
    title: 'Welcome message',
    description: 'Greet a new customer',
    tags: [{ label: 'UTILITY', color: 'teal' }],
    actionLabel: 'Use example',
  };

  it('renders its content, tags and named slots', () => {
    const wrapper = mount(PresetCard, {
      props,
      slots: {
        preview: '<p>Preview text</p>',
        meta: '<p>Requires a WhatsApp inbox</p>',
      },
    });

    expect(wrapper.text()).toContain('Welcome message');
    expect(wrapper.text()).toContain('UTILITY');
    expect(wrapper.text()).toContain('Preview text');
    expect(wrapper.text()).toContain('Requires a WhatsApp inbox');
  });

  it('emits apply with its id from the primary action', async () => {
    const wrapper = mount(PresetCard, { props, attachTo: document.body });

    await wrapper.get('button').trigger('click');

    expect(wrapper.emitted('apply')).toEqual([['welcome']]);
    expect(wrapper.get('button').classes()).toContain('bg-n-brand');
    wrapper.unmount();
  });

  it('keeps the action keyboard reachable and disabled presets inert', async () => {
    const wrapper = mount(PresetCard, { props, attachTo: document.body });
    const button = wrapper.get('button');
    button.element.focus();

    expect(document.activeElement).toBe(button.element);
    expect(button.classes().join(' ')).toContain('focus-visible:ring-2');
    wrapper.unmount();

    const disabledWrapper = mount(PresetCard, {
      props: { ...props, disabled: true },
    });
    expect(disabledWrapper.get('button').attributes('disabled')).toBeDefined();
    await disabledWrapper.get('button').trigger('click');
    expect(disabledWrapper.emitted('apply')).toBeUndefined();
  });

  it('lets the parent replace the default action', () => {
    const wrapper = mount(PresetCard, {
      props,
      slots: { actions: '<button type="button">Activate</button>' },
    });

    expect(wrapper.text()).toContain('Activate');
    expect(wrapper.text()).not.toContain('Use example');
  });
});
