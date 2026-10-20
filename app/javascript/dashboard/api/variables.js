/* global axios */
import ApiClient from './ApiClient';

class VariablesAPI extends ApiClient {
  constructor() {
    super('variables', { accountScoped: true });
  }

  catalog(accountId, surface) {
    return axios.get(`${this.apiVersion}/accounts/${accountId}/variables`, {
      params: { surface },
    });
  }

  preview(payload, signal) {
    return axios.post(`${this.url}/preview`, payload, { signal });
  }
}

export default new VariablesAPI();
