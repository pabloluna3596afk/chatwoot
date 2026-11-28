import ConversationApi from '../../../../api/inbox/conversation';
import MessageApi from '../../../../api/inbox/message';

export default {
  async setConversationAutoTranslate(_, { conversationId, disabled }) {
    await ConversationApi.update(conversationId, {
      auto_translate_disabled: disabled,
    });
  },

  async translateMessage(_, { conversationId, messageId, targetLanguage }) {
    await MessageApi.translateMessage(
      conversationId,
      messageId,
      targetLanguage
    );
  },
};
