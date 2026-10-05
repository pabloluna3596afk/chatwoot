/* global axios */
import ApiClient from './ApiClient';

// The forms ("flows") built in ChatHub: drafts in the neutral format, checked and exported to Meta's Flow JSON.
// Everyone in the account reads them; only administrators change them.
class WhatsappFlowsAPI extends ApiClient {
  constructor() {
    super('whatsapp_flows', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(flow) {
    return axios.post(this.url, { whatsapp_flow: flow });
  }

  update(id, flow) {
    return axios.patch(`${this.url}/${id}`, { whatsapp_flow: flow });
  }

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // The mistakes of a definition that is still being edited, or its Flow JSON; nothing is saved.
  validate(definition, config = {}) {
    return axios.post(`${this.url}/validate`, { definition }, config);
  }
}

export default new WhatsappFlowsAPI();
