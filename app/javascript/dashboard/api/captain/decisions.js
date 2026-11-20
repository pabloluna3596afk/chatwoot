/* global axios */
import ApiClient from '../ApiClient';

class CaptainDecisions extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  getForMessage(conversationId, messageId) {
    return axios.get(`${this.url}/${conversationId}/captain_decisions`, {
      params: { message_id: messageId },
    });
  }
}

export default new CaptainDecisions();
