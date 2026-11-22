/* global axios */
import ApiClient from './ApiClient';

class WhatsappTemplateDraftsAPI extends ApiClient {
  constructor() {
    super('whatsapp_template_drafts', { accountScoped: true });
  }

  get(params = {}, config = {}) {
    return axios.get(this.url, { ...config, params });
  }

  create(draft) {
    return axios.post(this.url, { draft });
  }

  fromLibrary(attributes) {
    return axios.post(`${this.url}/from_library`, attributes);
  }

  fromBlueprint(blueprintId, channelId = null) {
    return axios.post(`${this.url}/from_blueprint`, {
      blueprint_id: blueprintId,
      channel_id: channelId,
    });
  }

  update(id, draft) {
    return axios.patch(`${this.url}/${id}`, { draft });
  }

  delete(id, revision) {
    return axios.delete(`${this.url}/${id}`, {
      data: { lock_version: revision },
    });
  }

  newVersion(channelId, remoteId) {
    return axios.post(`${this.url}/new_version`, {
      channel_id: channelId,
      remote_id: remoteId,
    });
  }

  duplicate(id, destination) {
    return axios.post(`${this.url}/${id}/duplicate`, { destination });
  }

  uploadMedia(id, revision, file) {
    const body = new FormData();
    body.append('file', file);
    body.append('lock_version', String(revision));
    return axios.post(`${this.url}/${id}/media`, body);
  }

  downloadMedia(id) {
    return axios.get(`${this.url}/${id}/media`, { responseType: 'blob' });
  }

  removeMedia(id, revision) {
    return axios.delete(`${this.url}/${id}/media`, {
      data: { lock_version: revision },
    });
  }

  submit(id, revision) {
    return axios.post(`${this.url}/${id}/submit`, { lock_version: revision });
  }

  reconcile(id, submissionId) {
    return axios.post(
      `${this.url}/${id}/submissions/${submissionId}/reconcile`
    );
  }
}

export default new WhatsappTemplateDraftsAPI();
