import { mount } from '@vue/test-utils';
import SnackbarContainer from './SnackbarContainer.vue';

describe('SnackbarContainer', () => {
  it('exposes toast messages through one polite status region', () => {
    const wrapper = mount(SnackbarContainer, {
      global: { mocks: { $t: key => key } },
    });

    const region = wrapper.get('[role="status"]');
    expect(region.attributes('aria-live')).toBe('polite');
    expect(region.attributes('aria-atomic')).toBe('true');
    expect(wrapper.findAll('[aria-live]')).toHaveLength(1);
    wrapper.unmount();
  });
});
