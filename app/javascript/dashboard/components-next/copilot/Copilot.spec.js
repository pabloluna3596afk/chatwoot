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

  it('scrolls to the latest restored message when the thread loads', async () => {
    const wrapper = mountWith({ messages: [] });
    const chat = wrapper.get('.overflow-y-auto').element;
    Object.defineProperties(chat, {
      scrollHeight: { configurable: true, value: 500 },
      clientHeight: { configurable: true, value: 200 },
    });

    await wrapper.setProps({
      messages: [
        {
          id: 1,
          message_type: 'assistant',
          created_at: 1,
          message: { content: 'Restored answer' },
        },
      ],
    });
    await wrapper.vm.$nextTick();

    expect(chat.scrollTop).toBe(500);
  });

  it('keeps the reader position when new messages arrive above the viewport', async () => {
    const wrapper = mountWith({
      messages: [
        {
          id: 1,
          message_type: 'assistant',
          created_at: 1,
          message: { content: 'Earlier answer' },
        },
      ],
    });
    const chat = wrapper.get('.overflow-y-auto').element;
    Object.defineProperties(chat, {
      scrollHeight: { configurable: true, value: 500 },
      clientHeight: { configurable: true, value: 200 },
    });
    await wrapper.vm.$nextTick();
    chat.scrollTop = 0;
    await wrapper.get('.overflow-y-auto').trigger('scroll');

    await wrapper.setProps({
      messages: [
        ...wrapper.props('messages'),
        {
          id: 2,
          message_type: 'assistant',
          created_at: 2,
          message: { content: 'New answer' },
        },
      ],
    });

    expect(chat.scrollTop).toBe(0);
    expect(wrapper.text()).toContain('CAPTAIN.COPILOT.NEW_MESSAGES');
  });
});
