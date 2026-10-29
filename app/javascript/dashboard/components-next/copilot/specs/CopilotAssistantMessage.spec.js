import { mount } from '@vue/test-utils';
import CopilotAssistantMessage from '../CopilotAssistantMessage.vue';

const clipboard = vi.hoisted(() => ({ copy: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: clipboard.copy,
}));
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('shared/helpers/MessageFormatter.js', () => ({
  default: class {
    constructor(content) {
      this.formattedMessage = content;
    }
  },
}));

describe('CopilotAssistantMessage', () => {
  it('identifies Copilot and copies the response', async () => {
    clipboard.copy.mockResolvedValue(undefined);
    const wrapper = mount(CopilotAssistantMessage, {
      props: { message: { content: 'A **formatted** response' } },
      global: {
        mocks: { $t: key => key },
        directives: { 'dompurify-html': {} },
        stubs: {
          Button: {
            template:
              '<button @click="$emit(\'click\')"><slot />{{ label }}</button>',
            props: ['label'],
          },
        },
      },
    });

    expect(wrapper.text()).toContain('CAPTAIN.COPILOT.COPILOT_LABEL');
    await wrapper.find('button').trigger('click');
    expect(clipboard.copy).toHaveBeenCalledWith('A **formatted** response');
  });
});
