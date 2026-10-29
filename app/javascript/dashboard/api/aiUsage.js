import ApiClient from './ApiClient';

class AiUsageAPI extends ApiClient {
  constructor() {
    super('ai_usage', { accountScoped: true });
  }
}

export default new AiUsageAPI();
