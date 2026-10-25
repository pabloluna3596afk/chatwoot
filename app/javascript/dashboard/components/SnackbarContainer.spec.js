import { mount } from '@vue/test-utils';
import SnackbarContainer from './SnackbarContainer.vue';
import { emitter } from 'shared/helpers/mitt';

describe('SnackbarContainer', () => {
  it('exposes toast messages through one polite status region', () => {
    const wrapper = mount(SnackbarContainer, {
      global: { mocks: { $t: key => key } },
    });

    const region = wrapper.get('[role="status"]');
    expect(region.attributes('aria-live')).toBe('polite');
    expect(region.attributes('aria-atomic')).toBe('false');
    expect(region.attributes('aria-relevant')).toBe('additions text');
    expect(wrapper.findAll('[aria-live]')).toHaveLength(1);
    wrapper.unmount();
  });

  it('does not make the status region repeat an earlier toast when another arrives', async () => {
    const wrapper = mount(SnackbarContainer, {
      global: { mocks: { $t: key => key } },
    });

    emitter.emit('newToastMessage', { message: 'First notice' });
    await wrapper.vm.$nextTick();
    emitter.emit('newToastMessage', { message: 'Second notice' });
    await wrapper.vm.$nextTick();

    const region = wrapper.get('[role="status"]');
    expect(region.attributes('aria-atomic')).toBe('false');
    expect(region.text()).toContain('First notice');
    expect(region.text()).toContain('Second notice');
    wrapper.unmount();
  });
});
