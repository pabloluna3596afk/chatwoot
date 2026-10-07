/* global axios */
import ApiClient from './ApiClient';

// The forms ("flows") built in ChatHub: drafts in the neutral format, checked and exported to Meta's Flow JSON.
// Everyone in the account reads them; only administrators change them.
class WhatsappFlowsAPI extends ApiClient {
  constructor() {
    super('whatsapp_flows', { accountScoped: true });
  }

  list(params = {}, { signal } = {}) {
    return axios.get(this.url, { params, signal });
  }

  conversationFlows(conversationId, config = {}) {
    return axios.get(
      `${this.baseUrl()}/conversations/${conversationId}/whatsapp_flows`,
      config
    );
  }

  sendToConversation(conversationId, payload) {
    return axios.post(
      `${this.baseUrl()}/conversations/${conversationId}/whatsapp_flows`,
      payload
    );
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

  // Sent to Meta on every WhatsApp Cloud WABA of the account, in the background (202); poll publicationStatus.
  publish(id) {
    return axios.post(`${this.url}/${id}/publish`);
  }

  // { flow_id, wabas: [{ waba_id, channel_id, phone_number }], publications: [{ waba_id, status, meta_flow_id,
  // validation_errors, published_version, published_at }] }
  publicationStatus(id, params = {}, { signal } = {}) {
    return axios.get(`${this.url}/${id}/publication_status`, {
      params,
      signal,
    });
  }

  // "Probar": sends the flow to a phone number through one Cloud channel, without publishing it.
  test(id, { channelId, phoneNumber }) {
    return axios.post(`${this.url}/${id}/test`, {
      channel_id: channelId,
      phone_number: phoneNumber,
    });
  }

  retryPublication(id, wabaId) {
    return axios.post(`${this.url}/${id}/publications/${wabaId}/retry`);
  }

  // The mistakes of a definition that is still being edited, or its Flow JSON; nothing is saved.
  validate(definition, config = {}) {
    return axios.post(`${this.url}/validate`, { definition }, config);
  }
}

export default new WhatsappFlowsAPI();
