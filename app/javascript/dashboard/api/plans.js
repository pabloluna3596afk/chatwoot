/* global axios */
import ApiClient from './ApiClient';

class PlansAPI extends ApiClient {
  constructor() {
    super('plans', { accountScoped: true });
  }

  get(accountId) {
    return axios.get(`${this.apiVersion}/accounts/${accountId}/plans`);
  }
}

export default new PlansAPI();
