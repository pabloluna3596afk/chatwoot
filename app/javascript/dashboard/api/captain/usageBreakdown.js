/* global axios */
import ApiClient from '../ApiClient';

class CaptainUsageBreakdown extends ApiClient {
  constructor() {
    super('captain/usage_breakdown', { accountScoped: true });
  }

  getUsageBreakdown() {
    return axios.get(this.url);
  }
}

export default new CaptainUsageBreakdown();
