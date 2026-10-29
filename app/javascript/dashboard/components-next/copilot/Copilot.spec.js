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

  const mountWith = props =>
    mount(Copilot, {
      props: { onSendMessage: vi.fn(), ...props },
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

  it('does not show the typing state when the last item is an action card', () => {
    const wrapper = mountWith({
      messages: [
        {
          id: 1,
          message_type: 'user',
          created_at: 1,
          message: { content: 'hola' },
        },
        {
          id: 2,
          message_type: 'assistant',
          created_at: 2,
          message: { content: 'listo' },
        },
      ],
      actionItems: [{ id: 9, created_at: 3, status: 'pending' }],
    });

    expect(wrapper.text()).toContain('CAPTAIN.COPILOT.ONLINE');
    expect(wrapper.findComponent({ name: 'CopilotLoader' }).exists()).toBe(
      false
    );
  });

  it('shows the typing state while the last item is the agent message', () => {
    const wrapper = mountWith({
      messages: [
        {
          id: 1,
          message_type: 'user',
          created_at: 1,
          message: { content: 'hola' },
        },
      ],
    });

    expect(wrapper.text()).toContain('CAPTAIN.COPILOT.TYPING');
  });
});
