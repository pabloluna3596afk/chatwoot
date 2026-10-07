import { flushPromises, mount } from '@vue/test-utils';
import { h } from 'vue';
import ComboBox from '../ComboBox.vue';
import ComboBoxDropdown from '../ComboBoxDropdown.vue';
import TagMultiSelectComboBox from '../TagMultiSelectComboBox.vue';

const options = [
  { value: 7, label: 'Name', group: 'contact' },
  { value: 8, label: 'Identity', group: 'custom' },
];

describe('ComboBox', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('reserves space for an empty group above the footer in teleported menus', async () => {
    vi.stubGlobal('requestAnimationFrame', callback => {
      callback();
      return 0;
    });
    const wrapper = mount(ComboBox, {
      props: {
        options: options.slice(0, 1),
        teleport: true,
        groups: [{ key: 'custom', label: 'Custom' }],
      },
      slots: { footer: () => h('button', 'Create attribute') },
      global: { stubs: { Teleport: true } },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    const menu = wrapper.get('[data-combobox-dropdown]');
    expect(menu.element.style.maxHeight).not.toBe('');
    const before = parseFloat(menu.element.style.maxHeight);
    await wrapper.get('button').trigger('click');
    await wrapper.setProps({
      groups: [
        { key: 'custom', label: 'Custom', emptyState: 'No custom attributes' },
      ],
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    const resizedMenu = wrapper.get('[data-combobox-dropdown]');
    expect(parseFloat(resizedMenu.element.style.maxHeight)).toBeGreaterThan(
      before
    );
    expect(resizedMenu.text()).toContain('No custom attributes');
    expect(resizedMenu.text()).toContain('Create attribute');
    wrapper.unmount();
  });

  it('preserves flat options, numeric values and optional deselection', async () => {
    const wrapper = mount(ComboBox, { props: { options, modelValue: 7 } });
    await wrapper.get('button').trigger('click');
    expect(wrapper.findAll('[role="option"]')).toHaveLength(2);
    await wrapper.findAll('[role="option"]')[1].trigger('click');
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([8]);
    await wrapper.setProps({ modelValue: 8 });
    await wrapper.get('button').trigger('click');
    await wrapper.findAll('[role="option"]')[1].trigger('click');
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['']);
  });

  it('keeps required selections when the same option is clicked', async () => {
    const wrapper = mount(ComboBox, {
      props: { options, modelValue: 7, allowDeselect: false },
    });
    await wrapper.get('button').trigger('click');
    await wrapper.findAll('[role="option"]')[0].trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('false');
  });

  it('renders nonselectable groups, group empty states and an always-visible footer', async () => {
    const wrapper = mount(ComboBox, {
      props: {
        options,
        showSearch: true,
        groups: [
          { key: 'contact', label: 'Contact' },
          {
            key: 'custom',
            label: 'Custom',
            emptyState: 'No custom attributes',
          },
        ],
      },
      slots: {
        footer: ({ close }) =>
          h('button', { onClick: close }, 'Create attribute'),
      },
    });
    await wrapper.get('button').trigger('click');
    expect(wrapper.text()).toContain('Contact');
    expect(wrapper.text()).toContain('Custom');
    expect(wrapper.findAll('[role="option"]')).toHaveLength(2);
    expect(wrapper.text()).toContain('Create attribute');
    await wrapper.setProps({ options: options.slice(0, 1) });
    expect(wrapper.text()).toContain('No custom attributes');
    expect(wrapper.text()).toContain('Create attribute');
    await wrapper.get('input').setValue('Identity');
    expect(wrapper.text()).not.toContain('No custom attributes');
    expect(wrapper.findAll('[role="option"]')).toHaveLength(0);
    await wrapper.findAll('button').at(-1).trigger('click');
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('false');
  });

  it('supports multiple categories with a count and removes only the selected category', async () => {
    const wrapper = mount(ComboBox, {
      props: { options, multiple: true, modelValue: [7, 8] },
    });
    expect(wrapper.get('button').text()).toContain('Name +1');
    await wrapper.get('button').trigger('click');
    expect(
      wrapper.get('[role="listbox"]').attributes('aria-multiselectable')
    ).toBe('true');
    await wrapper.findAll('[role="option"]')[0].trigger('click');
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([[8]]);
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('true');
  });

  it('supports keyboard selection and Escape with focus returned to the trigger', async () => {
    const wrapper = mount(ComboBox, {
      props: { options },
      attachTo: document.body,
    });
    await wrapper.get('button').trigger('click');
    await wrapper
      .get('[data-combobox-dropdown]')
      .trigger('keydown', { key: 'ArrowDown' });
    expect(document.activeElement).toBe(
      wrapper.findAll('[role="option"]')[0].element
    );
    await wrapper
      .findAll('[role="option"]')[0]
      .trigger('keydown', { key: 'Enter' });
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([7]);
    await wrapper.get('button').trigger('click');
    await wrapper
      .get('[data-combobox-dropdown]')
      .trigger('keydown', { key: 'Escape' });
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('false');
    expect(document.activeElement).toBe(wrapper.get('button').element);
    wrapper.unmount();
  });

  it('keeps the shared dropdown contract for the existing tag multiselect consumer', () => {
    const wrapper = mount(TagMultiSelectComboBox, {
      props: { options, modelValue: [7] },
    });
    const dropdown = wrapper.findComponent(ComboBoxDropdown);
    dropdown.vm.$emit('select', options[1]);
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([[7, 8]]);
    dropdown.vm.$emit('select', options[0]);
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([[8]]);
  });
});
