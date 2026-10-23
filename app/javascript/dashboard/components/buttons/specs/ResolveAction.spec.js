import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import ResolveAction from '../ResolveAction.vue';
const state = vi.hoisted(() => ({ chat: null, change: vi.fn() }));
vi.mock('dashboard/composables/useConversationStatusActions', () => ({
  useConversationStatusActions: () => ({
    currentChat: ref(state.chat),
    isLoading: ref(false),
    resolveAttributesModalRef: ref(null),
    attemptStatusChange: state.change,
    handleResolveWithAttributes: vi.fn(),
  }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
vi.mock('dashboard/composables/emitter', () => ({ useEmitter: vi.fn() }));
describe('ResolveAction visible status', () => {
  it.each([
    [
      { status: 'pending', captain_state: 'ai' },
      'CONVERSATION.HEADER.RESOLVE_ACTION',
      'resolved',
    ],
    [
      { status: 'pending', display_status: 'open' },
      'CONVERSATION.HEADER.RESOLVE_ACTION',
      'resolved',
    ],
    [{ status: 'pending' }, 'CONVERSATION.HEADER.OPEN_ACTION', 'open'],
  ])('uses visible state for %j', async (chat, label, status) => {
    state.chat = chat;
    const wrapper = shallowMount(ResolveAction);
    const button = wrapper.findComponent({ name: 'Button' });
    expect(button.props('label')).toBe(label);
    await button.trigger('click');
    expect(state.change).toHaveBeenLastCalledWith(status);
  });
});
