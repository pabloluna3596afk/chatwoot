import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { createStore } from 'vuex';
import Editor from './Editor.vue';
import TagTools from '../conversation/TagTools.vue';

vi.mock('@amplitude/analytics-browser', () => ({}));
vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({ captainTasksEnabled: ref(false) }),
}));
const rect = { top: 0, bottom: 0, left: 0, right: 0, width: 0, height: 0 };
Range.prototype.getClientRects = () => [rect];
Range.prototype.getBoundingClientRect = () => rect;
Element.prototype.scrollIntoView = () => {};

it('Escape closes only the nested Captain menu and preserves the editor content', async () => {
  const wrapper = mount(Editor, {
    props: { modelValue: 'Keep these instructions', enableCaptainTools: true },
    global: {
      plugins: [
        createStore({
          getters: {
            getUISettings: () => ({}),
            'captainTools/getRecords': () => [
              {
                id: 'availability',
                title: 'Availability',
                description: 'Calendar',
              },
            ],
          },
        }),
      ],
      stubs: { CopilotMenuBar: true },
    },
  });
  try {
    wrapper.vm.showToolsMenu = true;
    await flushPromises();
    expect(wrapper.findComponent(TagTools).exists()).toBe(true);
    const event = new KeyboardEvent('keydown', {
      key: 'Escape',
      bubbles: true,
      cancelable: true,
    });
    const stop = vi.spyOn(event, 'stopPropagation');
    expect(wrapper.vm.onKeydown(event)).toBe(true);
    await flushPromises();
    expect(event.defaultPrevented).toBe(true);
    expect(stop).toHaveBeenCalledOnce();
    expect(wrapper.findComponent(TagTools).exists()).toBe(false);
    expect(wrapper.get('[contenteditable]').text()).toBe(
      'Keep these instructions'
    );
  } finally {
    wrapper.unmount();
  }
});
