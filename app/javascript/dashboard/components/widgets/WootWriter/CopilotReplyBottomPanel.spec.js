import { mount } from '@vue/test-utils';
import CopilotReplyBottomPanel from './CopilotReplyBottomPanel.vue';
import Button from 'dashboard/components-next/button/Button.vue';

describe('CopilotReplyBottomPanel', () => {
  it.each([true, false])(
    'allows discard while generating = %s',
    async isGeneratingContent => {
      const wrapper = mount(CopilotReplyBottomPanel, {
        props: { isGeneratingContent },
        global: { stubs: { NextButton: Button } },
      });
      const [discard, accept] = wrapper.findAll('button');
      expect(discard.isVisible()).toBe(true);
      expect(discard.element.disabled).toBe(false);
      expect(accept.element.disabled).toBe(isGeneratingContent);
      await discard.trigger('click');
      expect(wrapper.emitted('cancel')).toHaveLength(1);
      wrapper.unmount();
    }
  );
});
