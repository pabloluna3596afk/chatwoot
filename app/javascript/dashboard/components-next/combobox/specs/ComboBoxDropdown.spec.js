import { mount } from '@vue/test-utils';
import { h } from 'vue';
import ComboBoxDropdown from '../ComboBoxDropdown.vue';
import ComboBox from '../ComboBox.vue';
import ReorderableMultiSelect from '../ReorderableMultiSelect.vue';
import TagMultiSelectComboBox from '../TagMultiSelectComboBox.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const options = [
  { value: 'es', label: 'Español' },
  { value: 'en', label: 'English' },
];

describe('ComboBoxDropdown adapter', () => {
  it.each(['ltr', 'rtl'])(
    'preserves the app %s direction in body portals',
    direction => {
      const app = document.createElement('div');
      app.id = 'app';
      app.dir = direction;
      document.body.appendChild(app);
      const wrapper = mount(ComboBoxDropdown, {
        props: { open: true, options, portal: true },
      });
      try {
        expect(wrapper.getComponent(DropdownMenu).attributes('dir')).toBe(
          direction
        );
      } finally {
        wrapper.unmount();
        app.remove();
      }
    }
  );

  it('renders the real DropdownMenu panel, with listbox semantics and selected checks', async () => {
    const wrapper = mount(ComboBoxDropdown, {
      props: {
        open: true,
        options,
        selectedValues: ['es'],
        multiple: true,
        portal: true,
      },
    });
    try {
      const menu = wrapper.getComponent(DropdownMenu);
      expect(menu.element).toBe(wrapper.element);
      expect(menu.props('portal')).toBe(true);
      expect(menu.props('listbox')).toBe(true);
      expect(menu.props('multiple')).toBe(true);
      expect(menu.props('autoFocus')).toBe(false);
      expect(menu.props('showSectionDividers')).toBe(false);
      expect(menu.classes()).toContain('fixed');
      expect(
        menu.get('[role="listbox"]').attributes('aria-multiselectable')
      ).toBe('true');
      expect(
        menu.findAll('[role="option"]')[0].attributes('aria-selected')
      ).toBe('true');
      expect(
        menu.findAll('[role="option"]')[0].find('.i-lucide-check').exists()
      ).toBe(true);
      await menu.findAll('[role="option"]')[1].trigger('click');
      expect(wrapper.emitted('select')).toEqual([[options[1]]]);
    } finally {
      wrapper.unmount();
    }
  });

  it('uses native search, resets it from the public model and forwards server results unchanged', async () => {
    const wrapper = mount(ComboBoxDropdown, {
      props: { open: true, options, searchValue: 'initial', loading: true },
    });
    try {
      const menu = wrapper.getComponent(DropdownMenu);
      expect(menu.props('disableLocalFiltering')).toBe(true);
      expect(menu.get('input').element.value).toBe('initial');
      expect(menu.findComponent({ name: 'Spinner' }).exists()).toBe(true);
      await menu.get('input').setValue('no local label match');
      expect(wrapper.emitted('search').at(-1)).toEqual([
        'no local label match',
      ]);
      expect(wrapper.emitted('update:searchValue').at(-1)).toEqual([
        'no local label match',
      ]);
      expect(menu.findAll('[role="option"]')).toHaveLength(2);
      await wrapper.setProps({ searchValue: '' });
      expect(menu.get('input').element.value).toBe('');
      await wrapper.setProps({
        options: [],
        emptyState: 'No compatible results',
      });
      expect(menu.text()).toContain('No compatible results');
    } finally {
      wrapper.unmount();
    }
  });

  it('maps groups to native menu sections and preserves an undivided, closable footer', async () => {
    const wrapper = mount(ComboBoxDropdown, {
      props: {
        open: true,
        options: options.map(option => ({ ...option, group: 'languages' })),
        groups: [
          { key: 'languages', label: 'Languages' },
          { key: 'custom', label: 'Custom', emptyState: 'No attributes' },
        ],
      },
      slots: {
        footer: ({ close }) =>
          h(
            'button',
            { onClick: close, 'data-testid': 'create-attribute' },
            'Create attribute'
          ),
      },
    });
    try {
      const menu = wrapper.getComponent(DropdownMenu);
      expect(menu.props('menuSections').map(section => section.title)).toEqual([
        'Languages',
        'Custom',
      ]);
      expect(menu.text()).toContain('No attributes');
      expect(menu.get('p').classes()).toEqual(
        expect.arrayContaining(['sticky', 'uppercase'])
      );
      expect(
        menu
          .findAll('[class]')
          .some(element =>
            element
              .classes()
              .some(token => /^(border-[bt]|divide-|h-px)/.test(token))
          )
      ).toBe(false);
      await menu.get('[data-testid="create-attribute"]').trigger('click');
      expect(wrapper.emitted('close')).toHaveLength(1);
      await wrapper.setProps({ searchValue: 'searching', options: [] });
      expect(menu.text()).not.toContain('No attributes');
      expect(menu.text()).toContain('COMBOBOX.EMPTY_STATE');
    } finally {
      wrapper.unmount();
    }
  });

  it.each([
    { name: 'ComboBox', component: ComboBox, trigger: 'button' },
    {
      name: 'TagMultiSelectComboBox',
      component: TagMultiSelectComboBox,
      trigger: '.flex-wrap.cursor-pointer',
    },
    {
      name: 'ReorderableMultiSelect',
      component: ReorderableMultiSelect,
      trigger: 'button',
    },
  ])(
    'preserves the real $name consumer selection contract',
    async ({ component, trigger }) => {
      const wrapper = mount(component, {
        props: {
          options,
          ...(component === ComboBox ? { modelValue: '' } : { modelValue: [] }),
        },
      });
      try {
        await wrapper.get(trigger).trigger('click');
        const menu = wrapper
          .findComponent(ComboBoxDropdown)
          .getComponent(DropdownMenu);
        await menu.get('[role="option"]').trigger('click');
        expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
          component === ComboBox ? 'es' : ['es'],
        ]);
      } finally {
        wrapper.unmount();
      }
    }
  );
});
