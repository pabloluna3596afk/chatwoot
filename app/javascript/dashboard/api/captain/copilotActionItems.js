/* global axios */
import ApiClient from '../ApiClient';

class CopilotActionItems extends ApiClient {
  constructor() {
    super('captain/copilot_action_items', { accountScoped: true });
  }

  get(threadId) {
    return axios.get(this.url, { params: { copilot_thread_id: threadId } });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { payload });
  }

  approve(id) {
    return axios.post(`${this.url}/${id}/approve`);
  }

  reject(id) {
    return axios.post(`${this.url}/${id}/reject`);
  }
}

export default new CopilotActionItems();
