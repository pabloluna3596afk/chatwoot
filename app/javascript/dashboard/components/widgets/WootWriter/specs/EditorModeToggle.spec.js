import { mount } from '@vue/test-utils';
import EditorModeToggle from '../EditorModeToggle.vue';

describe('editor mode toggle layout', () => {
  it('anchors the chip logically and exposes focus, disabled and reduced-motion states', async () => {
    const wrapper = mount(EditorModeToggle);
    expect(wrapper.classes()).toEqual(
      expect.arrayContaining([
        'shrink-0',
        'focus-visible:outline-2',
        'disabled:opacity-50',
        'motion-reduce:transition-none',
      ])
    );
    expect(wrapper.classes()).not.toContain('border');
    expect(wrapper.get('.absolute').classes()).toContain('start-1');
    expect(wrapper.get('.absolute').classes()).toContain(
      'motion-reduce:transition-none'
    );
    await wrapper.setProps({ disabled: true });
    await wrapper.trigger('click');
    expect(wrapper.emitted('toggleMode')).toBeUndefined();
    wrapper.unmount();
  });
});
