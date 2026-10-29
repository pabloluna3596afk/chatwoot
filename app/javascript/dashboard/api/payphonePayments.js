/* global axios */
import ApiClient from './ApiClient';

class PayphonePaymentsAPI extends ApiClient {
  constructor() {
    super('payphone_payments', { accountScoped: true });
  }

  quote(data) {
    return axios.post(`${this.url}/quote`, data);
  }

  previewConfirm(id, status) {
    return axios.post(`${this.url}/${id}/preview_confirm`, { status });
  }
}

export default new PayphonePaymentsAPI();
