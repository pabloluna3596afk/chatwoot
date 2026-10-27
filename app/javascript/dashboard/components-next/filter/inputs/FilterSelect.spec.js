import { defineComponent, h, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import FilterSelect from './FilterSelect.vue';
import { provideDropdownTeleport } from 'dashboard/components-next/dropdown-menu/base/provider';

describe('FilterSelect inside a scrolling filter panel', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('renders its options outside the panel so they are not clipped', async () => {
    const selected = ref('equal_to');
    const FilterPanel = defineComponent({
      setup() {
        provideDropdownTeleport();
        return () =>
          h(
            'div',
            { class: 'max-h-20 overflow-y-auto', 'data-filter-panel': '' },
            [
              h(FilterSelect, {
                modelValue: selected.value,
                'onUpdate:modelValue': value => {
                  selected.value = value;
                },
                options: [
                  { value: 'equal_to', label: 'Equal to' },
                  { value: 'not_equal_to', label: 'Not equal to' },
                ],
              }),
            ]
          );
      },
    });
    const wrapper = mount(FilterPanel, {
      attachTo: document.body,
      global: {
        stubs: {
          TeleportWithDirection: {
            props: ['to'],
            template: '<Teleport :to="to"><div><slot /></div></Teleport>',
          },
        },
      },
    });

    await wrapper.get('button').trigger('click');
    await flushPromises();

    const menu = document.body.querySelector('[data-dropdown-menu]');
    expect(menu).not.toBeNull();
    expect(menu.closest('[data-filter-panel]')).toBeNull();
    expect(menu.textContent).toContain('Not equal to');
  });
});
