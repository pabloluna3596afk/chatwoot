import { mount } from '@vue/test-utils';
import Copilot from './Copilot.vue';

vi.mock('dashboard/composables', () => ({ useTrack: vi.fn() }));

describe('Copilot', () => {
  it('shows minimize, new chat, and history actions without a close action', async () => {
    const wrapper = mount(Copilot, {
      props: { onSendMessage: vi.fn() },
      global: {
        mocks: { $t: key => key },
        stubs: {
          CopilotInput: true,
          CopilotLoader: true,
          CopilotAgentMessage: true,
          CopilotAssistantMessage: true,
          CopilotThinkingGroup: true,
          ToggleCopilotAssistant: true,
          CopilotEmptyState: true,
          CopilotActionCard: true,
        },
      },
    });

    expect(wrapper.findAll('header button')).toHaveLength(3);
    expect(wrapper.find('[aria-label="GENERAL.CLOSE"]').exists()).toBe(false);
    expect(
      wrapper.find('[aria-label="CAPTAIN.COPILOT.MINIMIZE"]').exists()
    ).toBe(true);

    await wrapper
      .find('[aria-label="CAPTAIN.COPILOT.MINIMIZE"]')
      .trigger('click');

    expect(wrapper.emitted('minimize')).toHaveLength(1);
    expect(wrapper.emitted('close')).toBeUndefined();
  });
});
