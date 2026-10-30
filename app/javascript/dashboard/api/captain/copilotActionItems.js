/* global axios */
import ApiClient from '../ApiClient';

class CopilotActionItems extends ApiClient {
  constructor() {
    super('captain/copilot_action_items', { accountScoped: true });
  }

  get(threadId) {
    return axios.get(this.url, { params: { copilot_thread_id: threadId } });
  }

  // The controller finds the item through its thread, so every call needs it.
  update(id, payload, threadId) {
    return axios.patch(
      `${this.url}/${id}`,
      { payload },
      { params: { copilot_thread_id: threadId } }
    );
  }

  approve(id, threadId) {
    return axios.post(`${this.url}/${id}/approve`, null, {
      params: { copilot_thread_id: threadId },
    });
  }

  reject(id, threadId) {
    return axios.post(`${this.url}/${id}/reject`, null, {
      params: { copilot_thread_id: threadId },
    });
  }
}

export default new CopilotActionItems();
