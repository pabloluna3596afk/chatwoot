/* global axios */
import ApiClient from './ApiClient';

class AutomationsAPI extends ApiClient {
  constructor() {
    super('automation_rules', { accountScoped: true });
  }

  clone(automationId) {
    return axios.post(`${this.url}/${automationId}/clone`);
  }

  // Validate a rule without saving it: impossible conditions and unknown
  // attributes come back as errors, conflicts with other rules as warnings.
  lint(payload) {
    return axios.post(`${this.url}/lint`, payload);
  }

  // Dry run against a real conversation. Executes nothing.
  simulate({ conversationDisplayId, eventName }) {
    return axios.post(`${this.url}/simulate`, {
      conversation_display_id: conversationDisplayId,
      event_name: eventName,
    });
  }
}

export default new AutomationsAPI();
