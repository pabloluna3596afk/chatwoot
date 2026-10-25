import { mount } from '@vue/test-utils';
import LoadErrorNotice from './LoadErrorNotice.vue';

describe('LoadErrorNotice', () => {
  it('announces an error and emits retry', async () => {
    const wrapper = mount(LoadErrorNotice, {
      props: { title: 'Load failed', message: 'Network error' },
    });

    expect(wrapper.get('[role="alert"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Network error');
    await wrapper.get('button').trigger('click');
    expect(wrapper.emitted('retry')).toHaveLength(1);
  });

  it('marks a retrying button busy and renders compact mode', () => {
    const wrapper = mount(LoadErrorNotice, {
      props: { title: 'Load failed', retrying: true, compact: true },
    });

    expect(wrapper.get('[role="alert"]').classes()).toContain('bg-n-ruby-3');
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    expect(wrapper.get('button').attributes('aria-busy')).toBe('true');
  });
});
