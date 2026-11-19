import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, h, inject, reactive } from 'vue';
import ResizableEditorWrapper from '../ResizableEditorWrapper.vue';
import CopilotEditorSection from '../CopilotEditorSection.vue';

describe('Copilot editor height', () => {
  afterEach(() => vi.restoreAllMocks());

  it('keeps the chosen height through loading, long suggestions and follow-ups', async () => {
    // jsdom has no layout: supply a long suggestion and 100px of panel chrome.
    vi.spyOn(HTMLElement.prototype, 'scrollHeight', 'get').mockReturnValue(
      10000
    );
    vi.spyOn(HTMLElement.prototype, 'offsetHeight', 'get').mockImplementation(
      function measureHeight() {
        return this.classList.contains('resizable-editor-wrapper')
          ? Number.parseFloat(this.style.getPropertyValue('--editor-height')) +
              100
          : 40;
      }
    );
    let requestHeight;
    const HeightRequester = defineComponent({
      setup() {
        requestHeight = inject('requestEditorHeight');
        return () => h('div');
      },
    });
    const sectionProps = reactive({
      showCopilotEditor: true,
      isGeneratingContent: false,
      generatedContent: '',
    });
    const wrapper = mount(ResizableEditorWrapper, {
      props: { containerHeight: 600 },
      slots: {
        default: () => [
          h(HeightRequester),
          h(CopilotEditorSection, sectionProps),
        ],
      },
      global: {
        directives: {
          dompurifyHtml: (el, binding) => {
            el.textContent = binding.value;
          },
        },
      },
    });
    const initialHeight =
      wrapper.element.style.getPropertyValue('--editor-height');
    sectionProps.isGeneratingContent = true;
    await flushPromises();
    Object.assign(sectionProps, {
      isGeneratingContent: false,
      generatedContent: 'Long reply\n'.repeat(1000),
    });
    await flushPromises();
    expect(wrapper.element.style.getPropertyValue('--editor-height')).toBe(
      initialHeight
    );
    expect(wrapper.get('.copilot-suggestion').classes()).toContain(
      'overflow-y-auto'
    );
    requestHeight(10000);
    await flushPromises();
    expect(wrapper.element.style.getPropertyValue('--editor-height')).toBe(
      '300px'
    );
    await wrapper.setProps({ containerHeight: 350 });
    expect(wrapper.element.style.getPropertyValue('--editor-height')).toBe(
      '50px'
    );
    sectionProps.isGeneratingContent = true;
    await flushPromises();
    Object.assign(sectionProps, {
      isGeneratingContent: false,
      generatedContent: 'Refined reply',
    });
    await flushPromises();
    expect(wrapper.element.style.getPropertyValue('--editor-height')).toBe(
      '50px'
    );
    wrapper.unmount();
  });
});
