/* global axios */
import ApiClient from './ApiClient';

// Create, edit, delete and read the message templates of a WhatsApp Cloud inbox in Meta (administrators only).
class WhatsappTemplatesAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  path(inboxId, rest = '') {
    return `${this.url}/${inboxId}/whatsapp_templates${rest}`;
  }

  // What the channel can do (media headers need the app behind its token).
  capabilities(inboxId) {
    return axios.get(this.path(inboxId, '/capabilities'));
  }

  // The live state of a template: status and rejection reason.
  getTemplate(inboxId, templateId) {
    return axios.get(this.path(inboxId, `/${templateId}`));
  }

  createTemplate(inboxId, template) {
    return axios.post(this.path(inboxId), { template });
  }

  updateTemplate(inboxId, templateId, template) {
    return axios.patch(this.path(inboxId, `/${templateId}`), { template });
  }

  // Always by id (hsm_id) and name: the name alone would delete every language of the template.
  deleteTemplate(inboxId, templateId, name) {
    return axios.delete(this.path(inboxId, `/${templateId}`), {
      params: { name },
    });
  }

  // The example file of a media header; returns { handle, format, name }.
  uploadHeaderExample(inboxId, headerFormat, file) {
    const body = new FormData();
    body.append('header_format', headerFormat);
    body.append('file', file);
    return axios.post(this.path(inboxId, '/header_handle'), body);
  }
}

export default new WhatsappTemplatesAPI();
