/* global axios */
import ApiClient from '../ApiClient';

class CaptainCustomTools extends ApiClient {
  constructor() {
    super('captain/custom_tools', { accountScoped: true });
  }

  get({ page = 1, searchKey, assistantId } = {}) {
    return axios.get(this.url, {
      params: { page, searchKey, assistant_id: assistantId },
    });
  }

  show({ id, assistantId }) {
    return axios.get(`${this.url}/${id}`, {
      params: { assistant_id: assistantId },
    });
  }

  create({ assistantId, ...data } = {}) {
    return axios.post(this.url, {
      assistant_id: assistantId,
      custom_tool: data,
    });
  }

  update(id, { assistantId, ...data } = {}) {
    return axios.put(`${this.url}/${id}`, {
      assistant_id: assistantId,
      custom_tool: data,
    });
  }

  delete({ id, assistantId }) {
    return axios.delete(`${this.url}/${id}`, {
      params: { assistant_id: assistantId },
    });
  }

  test({ assistantId, ...data } = {}) {
    return axios.post(`${this.url}/test`, {
      assistant_id: assistantId,
      custom_tool: data,
    });
  }
}

export default new CaptainCustomTools();
