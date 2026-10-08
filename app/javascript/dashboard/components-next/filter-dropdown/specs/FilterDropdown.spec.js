import { mount, flushPromises } from '@vue/test-utils';
import FilterDropdown from '../FilterDropdown.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const options = [
  { value: 'all', label: 'All states', count: 12 },
  { value: 'published', label: 'Published', count: 12 },
  { value: 'error', label: 'Error', count: 0 },
];
const mountFilter = (extra = {}) =>
  mount(FilterDropdown, {
    props: { modelValue: 'all', label: 'State', options, ...extra },
    attachTo: document.body,
  });

describe('FilterDropdown', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it.each([6, 7])(
    'automatically searches only above six options (%s)',
    async size => {
      const wrapper = mountFilter({
        options: Array.from({ length: size }, (_, value) => ({
          value,
          label: `Option ${value}`,
          count: value,
        })),
      });
      await wrapper.get('button').trigger('click');
      expect(wrapper.find('input[type="search"]').exists()).toBe(size > 6);
      if (size > 6) {
        await wrapper.get('input').setValue('Option 2');
        expect(wrapper.findAll('[role="dialog"] button')).toHaveLength(1);
      }
      wrapper.unmount();
    }
  );

  it('shows counts and the active check, leaves zero selectable, and omits counts on the trigger', async () => {
    const wrapper = mountFilter();
    expect(wrapper.get('button').text()).toBe('All states');
    await wrapper.get('button').trigger('click');
    const rows = wrapper.findAll('[role="dialog"] button');
    expect(rows.map(row => row.text())).toEqual([
      'All states12',
      'Published12',
      'Error0',
    ]);
    expect(rows[0].find('.i-lucide-check').exists()).toBe(true);
    expect(rows[0].find('[aria-current="true"]').exists()).toBe(true);
    expect(rows[2].find('[aria-current]').exists()).toBe(false);
    expect(rows[2].attributes('disabled')).toBeUndefined();
    expect(rows[2].find('.text-n-slate-11').exists()).toBe(true);
    await rows[2].trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([['error']]);
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(document.activeElement).toBe(wrapper.get('button').element);
    wrapper.unmount();
  });

  it('uses an optional short trigger label while retaining full menu labels, counts and selected titles', async () => {
    const longLabel =
      'Changes awaiting publication on the connected WhatsApp account';
    const wrapper = mountFilter({
      options: [
        {
          value: 'all',
          label: 'All states',
          triggerLabel: 'States',
          count: 12,
        },
        { value: 'changes', label: longLabel, count: 2 },
      ],
    });
    expect(wrapper.get('button').text()).toBe('States');
    expect(wrapper.get('button').attributes('title')).toBe('All states');
    await wrapper.get('button').trigger('click');
    expect(
      wrapper.findAll('[role="dialog"] button').map(row => row.text())
    ).toEqual(['All states12', `${longLabel}2`]);
    await wrapper.setProps({ modelValue: 'changes' });
    expect(wrapper.get('button').text()).toBe(longLabel);
    expect(wrapper.get('button').attributes('title')).toBe(longLabel);
    wrapper.unmount();
  });

  it('supports arrows, Home, End, Enter selection and Escape with focus restoration', async () => {
    const wrapper = mountFilter();
    await wrapper.get('button').trigger('keydown', { key: 'ArrowDown' });
    await flushPromises();
    const rows = wrapper.findAll('[role="dialog"] button');
    expect(document.activeElement).toBe(rows[0].element);
    await rows[0].trigger('keydown', { key: 'ArrowUp' });
    expect(document.activeElement).toBe(rows[2].element);
    await rows[2].trigger('keydown', { key: 'Home' });
    expect(document.activeElement).toBe(rows[0].element);
    await rows[0].trigger('keydown', { key: 'End' });
    expect(document.activeElement).toBe(rows[2].element);
    // Native buttons generate a click on Enter in the browser.
    await rows[2].trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([['error']]);
    await wrapper.get('button').trigger('keydown', { key: 'ArrowUp' });
    await flushPromises();
    await wrapper.get('[role="dialog"]').trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('false');
    expect(document.activeElement).toBe(wrapper.get('button').element);
    wrapper.unmount();
  });

  it('updates counts while open and closes when focus leaves the filter', async () => {
    const wrapper = mountFilter();
    await wrapper.get('button').trigger('click');
    await wrapper.setProps({
      options: options.map(option => ({ ...option, count: 0 })),
    });
    expect(
      wrapper
        .findAll('[role="dialog"] button')
        .every(row => row.text().endsWith('0'))
    ).toBe(true);
    await wrapper
      .get('[role="dialog"]')
      .trigger('focusout', { relatedTarget: document.body });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    wrapper.unmount();
  });
});
