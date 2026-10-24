import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import Button from '../Button.vue';
import Checkbox from '../../checkbox/Checkbox.vue';
import PaginationFooter from '../../pagination/PaginationFooter.vue';
import TabsItem from '../../../components/ui/Tabs/TabsItem.vue';
import CalendarWeek from '../../../components/ui/DatePicker/components/CalendarWeek.vue';

describe('shared touch controls', () => {
  it.each(['xs', 'sm', 'md', 'lg'])(
    'keeps the mobile target for %s buttons, links and icons',
    size => {
      [
        { label: 'Save' },
        { icon: 'i-lucide-plus' },
        { label: 'Details', variant: 'link' },
      ].forEach(props => {
        const wrapper = mount(Button, {
          props: { ...props, size },
          attrs: { class: '!h-6 !w-8' },
        });
        expect(wrapper.classes()).toContain('max-sm:!min-h-11');
        expect(wrapper.classes()).toContain('max-sm:!min-w-11');
        expect(wrapper.classes()).toContain('focus-visible:ring-2');
        expect(
          wrapper.classes().some(name => /^focus:|^ring-/.test(name))
        ).toBe(false);
        expect(wrapper.classes().some(name => /^min-[hw]-11$/.test(name))).toBe(
          false
        );
      });
    }
  );

  it('preserves native disabled buttons and loading content', async () => {
    const wrapper = mount(Button, {
      props: { label: 'Save', isLoading: true },
      attrs: { disabled: true },
    });
    await wrapper.trigger('click');
    expect(wrapper.emitted('click')).toBeUndefined();
    expect(wrapper.text()).toBe('Save');
    expect(wrapper.find('svg').exists()).toBe(true);
  });

  it('uses a valid checkbox border while preserving selection and indeterminate state', async () => {
    const wrapper = mount(Checkbox, { props: { indeterminate: true } });
    const input = wrapper.get('input');
    expect(input.classes()).toContain('dark:border-n-slate-6');
    expect(input.element.indeterminate).toBe(true);
    await input.setValue(true);
    expect(wrapper.emitted('update:modelValue')[0]).toEqual([true]);
    expect(wrapper.emitted('change')).toHaveLength(1);
  });

  it('wraps the footer on mobile and preserves page and page-size events', async () => {
    const wrapper = mount(PaginationFooter, {
      props: {
        currentPage: 2,
        totalItems: 96,
        itemsPerPage: 16,
        perPageOptions: [16, 32],
      },
    });
    expect(wrapper.classes()).toContain('flex-col');
    expect(wrapper.classes()).toContain('sm:flex-row');
    const buttons = wrapper.findAllComponents(Button);
    await buttons[2].trigger('click');
    expect(wrapper.emitted('update:currentPage')[0]).toEqual([3]);
    const option = wrapper
      .findAll('button')
      .find(button => button.text() === '32');
    await option.trigger('click');
    expect(wrapper.emitted('update:itemsPerPage')[0]).toEqual([32]);
    await wrapper.setProps({ currentPage: 1 });
    expect(buttons[0].attributes('disabled')).toBeDefined();
    await wrapper.setProps({ currentPage: 6 });
    expect(buttons[3].attributes('disabled')).toBeDefined();
  });

  it('keeps compact tabs touchable and preserves tab selection', async () => {
    const updateActiveIndex = vi.fn();
    const wrapper = mount(TabsItem, {
      props: { name: 'Tasks', index: 1, isCompact: true },
      global: { provide: { activeIndex: ref(0), updateActiveIndex } },
    });
    expect(wrapper.get('a').classes()).toContain('max-sm:min-h-11');
    await wrapper.get('a').trigger('click');
    expect(updateActiveIndex).toHaveBeenCalledWith(1);
  });

  it('fits seven touchable days and six weeks without a fixed mobile height', async () => {
    const date = new Date(2026, 7, 15);
    const wrapper = mount(CalendarWeek, {
      props: {
        currentDate: date,
        startCurrentDate: date,
        endCurrentDate: date,
      },
    });
    const days = wrapper.findAll('.cursor-pointer');
    expect(days).toHaveLength(42);
    expect(wrapper.classes()).toContain('lg:max-h-[19.5rem]');
    expect(days[0].classes()).toContain('w-11');
    expect(days[0].classes()).toContain('h-11');
    const day = days.find(item => item.text() === '15');
    await day.trigger('click');
    expect(wrapper.emitted('selectDate')[0][0].getDate()).toBe(15);
  });
});
