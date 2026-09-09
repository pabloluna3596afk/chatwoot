/* global axios */
import ApiClient from './ApiClient';

class AgentBotsAPI extends ApiClient {
  constructor() {
    super('agent_bots', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, data, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, data, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  deleteAgentBotAvatar(botId) {
    return axios.delete(`${this.url}/${botId}/avatar`);
  }

  resetAccessToken(botId) {
    return axios.post(`${this.url}/${botId}/reset_access_token`);
  }

  resetSecret(botId) {
    return axios.post(`${this.url}/${botId}/reset_secret`);
  }

  fetchPanelAiSummary(botId) {
    return axios.get(`${this.url}/${botId}/panel_ai_summary`);
  }

  // The inherited delete() now deactivates server-side (see
  // AgentBotsController#destroy) rather than deleting — this just
  // re-activates a bot that was previously deactivated.
  activate(botId) {
    return axios.post(`${this.url}/${botId}/activate`);
  }
}

export default new AgentBotsAPI();
