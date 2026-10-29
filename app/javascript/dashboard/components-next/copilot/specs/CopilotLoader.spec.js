import { mount } from '@vue/test-utils';
import CopilotLoader from '../CopilotLoader.vue';

describe('CopilotLoader', () => {
  it('announces Copilot activity accessibly and respects reduced motion', () => {
    const wrapper = mount(CopilotLoader, {
      global: { mocks: { $t: key => key } },
    });

    expect(wrapper.find('[role="status"][aria-live="polite"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).toContain('CAPTAIN.COPILOT.LOADER');
    expect(wrapper.findAll('.motion-reduce\\:animate-none')).toHaveLength(3);
  });
});
