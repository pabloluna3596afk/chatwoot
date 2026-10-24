import { mount } from '@vue/test-utils';
import Input from '../Input.vue';
import SearchInput from '../SearchInput.vue';

describe('SearchInput', () => {
  it.each(['ltr', 'rtl'])('reserves icon space in %s', direction => {
    const wrapper = mount(SearchInput, {
      props: { placeholder: 'Search' },
      attrs: { dir: direction },
    });
    const base = wrapper.getComponent(Input);
    const icon = wrapper.get('.i-lucide-search');
    expect(base.props('type')).toBe('search');
    expect(base.classes()).toContain('[&>input]:ltr:!pl-8');
    expect(base.classes()).toContain('[&>input]:rtl:!pr-8');
    expect(base.classes()).toContain('[&>input]:min-h-11');
    expect(base.classes()).toContain('md:[&>input]:min-h-0');
    expect(icon.classes()).toContain('start-2.5');
    expect(icon.classes()).toContain('group-focus-within:text-n-brand');
    expect(icon.attributes('aria-hidden')).toBe('true');
    expect(wrapper.attributes('dir')).toBe(direction);
  });

  it.each(['sm', 'md'])('passes size %s to Input', size => {
    const wrapper = mount(SearchInput, {
      props: { placeholder: 'Search', size },
    });
    expect(wrapper.getComponent(Input).props('size')).toBe(size);
  });

  it('uses the placeholder as the accessible name unless explicitly supplied', async () => {
    const wrapper = mount(SearchInput, {
      props: { placeholder: 'Search agents' },
    });
    expect(wrapper.get('input').attributes('aria-label')).toBe('Search agents');
    await wrapper.setProps({ ariaLabel: 'Filter agents by name' });
    expect(wrapper.get('input').attributes('aria-label')).toBe(
      'Filter agents by name'
    );
  });

  it('updates the model in both directions and forwards input events', async () => {
    const onInput = vi.fn();
    const wrapper = mount(SearchInput, {
      props: { placeholder: 'Search', modelValue: 'initial' },
      attrs: { onInput },
    });
    expect(wrapper.get('input').element.value).toBe('initial');
    await wrapper.get('input').setValue('María');
    expect(wrapper.emitted('update:modelValue')).toEqual([['María']]);
    expect(onInput).toHaveBeenCalledOnce();
    await wrapper.setProps({ modelValue: 'updated' });
    expect(wrapper.get('input').element.value).toBe('updated');
  });

  it('clears without submitting, hides the button and restores input focus', async () => {
    const wrapper = mount(SearchInput, {
      attachTo: document.body,
      props: {
        placeholder: 'Search',
        modelValue: 'query',
        clearable: true,
        'onUpdate:modelValue': value => wrapper.setProps({ modelValue: value }),
      },
    });
    const button = wrapper.get('button');
    expect(button.attributes('type')).toBe('button');
    expect(button.attributes('aria-label')).toBeTruthy();
    expect(button.classes()).toContain('size-11');
    expect(wrapper.getComponent(Input).classes()).toContain(
      '[&>input]:ltr:!pr-11'
    );
    await button.trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([['']]);
    expect(wrapper.get('input').element.value).toBe('');
    expect(wrapper.find('button').exists()).toBe(false);
    expect(document.activeElement).toBe(wrapper.get('input').element);
    wrapper.unmount();
  });

  it('only offers clearing when opted in and populated', async () => {
    const wrapper = mount(SearchInput, {
      props: { placeholder: 'Search', modelValue: 'query' },
    });
    expect(wrapper.find('button').exists()).toBe(false);
    await wrapper.setProps({ clearable: true, modelValue: '' });
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('disables the input and clear button together', async () => {
    const wrapper = mount(SearchInput, {
      props: {
        placeholder: 'Search',
        modelValue: 'query',
        clearable: true,
        disabled: true,
      },
    });
    expect(wrapper.get('input').element.disabled).toBe(true);
    expect(wrapper.get('button').element.disabled).toBe(true);
    await wrapper.get('button').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('keeps responsive widths on the container', () => {
    const wrapper = mount(SearchInput, {
      props: { placeholder: 'Search' },
      attrs: { class: 'sm:w-56' },
    });
    expect(wrapper.classes()).toContain('w-full');
    expect(wrapper.classes()).toContain('sm:w-56');
    expect(wrapper.get('input').classes()).not.toContain('sm:w-56');
  });
});
