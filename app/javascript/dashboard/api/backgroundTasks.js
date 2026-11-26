/* global axios */
import ApiClient from './ApiClient';

class BackgroundTasksAPI extends ApiClient {
  constructor() {
    super('background_tasks', { accountScoped: true });
  }

  get(accountId, config = {}) {
    return axios.get(`${this.apiVersion}/accounts/${accountId}/${this.resource}`, config);
  }
}

export default new BackgroundTasksAPI();
