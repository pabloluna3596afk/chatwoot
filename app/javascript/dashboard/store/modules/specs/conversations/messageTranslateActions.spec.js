import ConversationApi from 'dashboard/api/inbox/conversation';
import actions from '../../conversations/actions/messageTranslateActions';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { update: vi.fn() },
}));

describe('setConversationAutoTranslate', () => {
  it.each([true, false])('sends the documented boolean %s', async disabled => {
    await actions.setConversationAutoTranslate(
      {},
      { conversationId: 42, disabled }
    );
    expect(ConversationApi.update).toHaveBeenCalledWith(42, {
      auto_translate_disabled: disabled,
    });
  });

  it('propagates a failed save to the menu', async () => {
    ConversationApi.update.mockRejectedValue(new Error('offline'));
    await expect(
      actions.setConversationAutoTranslate(
        {},
        { conversationId: 42, disabled: true }
      )
    ).rejects.toThrow('offline');
  });
});
