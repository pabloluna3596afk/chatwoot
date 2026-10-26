import { mount } from '@vue/test-utils';
import ResizableEditorWrapper from '../ResizableEditorWrapper.vue';

describe('ResizableEditorWrapper', () => {
  it('emits collapse when the resize handle is dragged below its minimum', async () => {
    const wrapper = mount(ResizableEditorWrapper, {
      props: { containerHeight: 600 },
      attachTo: document.body,
      slots: { default: '<div>Reply editor</div>' },
    });

    await wrapper.get('.group').trigger('mousedown', { clientY: 100 });
    document.dispatchEvent(new MouseEvent('mousemove', { clientY: 164 }));

    expect(wrapper.emitted('collapse')).toHaveLength(1);
    wrapper.unmount();
  });
});
