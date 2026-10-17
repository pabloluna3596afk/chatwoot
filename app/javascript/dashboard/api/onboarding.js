/* global axios */
import ApiClient from './ApiClient';

class OnboardingAPI extends ApiClient {
  constructor() {
    super('onboarding', { accountScoped: true });
  }

  update(data) {
    return axios.patch(this.url, data);
  }

  getHelpCenterGeneration() {
    return axios.get(`${this.url}/help_center_generation`);
  }

  getAssistant() {
    return axios.get(`${this.url}/assistant`);
  }

  saveAssistant(data) {
    return axios.post(`${this.url}/assistant`, data);
  }
}

export default new OnboardingAPI();
