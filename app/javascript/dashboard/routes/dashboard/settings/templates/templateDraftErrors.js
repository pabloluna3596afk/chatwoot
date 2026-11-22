// Both entry points receive the same draft validation contract. Keep server
// attribute names out of the UI, including when only `details` is returned.
const FIELD_PATHS = {
  title: 'title',
  name: 'name',
  language: 'language',
  category: 'category',
  preferred_channel: 'inboxId',
  preferred_channel_id: 'inboxId',
  waba_id: 'inboxId',
  definition: 'body.text',
  parameter_format: 'body.text',
  variable_bindings: 'body.text',
  media: 'header.media',
};

export const templateDraftError = (error, t, te) => {
  const data = error?.response?.data;
  const fields = {};
  const identityConflict =
    data?.error === 'identity_conflict' ||
    (data?.error === 'invalid_draft' &&
      (data.details?.name || []).some(message =>
        /taken|already|exists|existe|uso|utilizado|ocupado/i.test(message)
      ));
  if (identityConflict) {
    const message = t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.IDENTITY_CONFLICT');
    return { message, fields: { name: message } };
  }
  if (data?.error === 'invalid_draft') {
    const messages = {
      title: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.FIELD_ERRORS.title'),
      name: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.FIELD_ERRORS.name'),
      language: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.FIELD_ERRORS.language'),
      category: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.FIELD_ERRORS.category'),
      inboxId: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.FIELD_ERRORS.inboxId'),
      'body.text': t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.FIELD_ERRORS.body.text'),
      'header.media': t(
        'WHATSAPP_TEMPLATE_MGMT.DRAFTS.FIELD_ERRORS.header.media'
      ),
    };
    Object.keys(data.details || {}).forEach(field => {
      const path = FIELD_PATHS[field];
      if (path) fields[path] = messages[path];
    });
    return {
      message:
        Object.values(fields).join(' ') ||
        t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.INVALID_DRAFT'),
      fields,
    };
  }
  const key = `WHATSAPP_TEMPLATE_MGMT.FORM.ERRORS.${data?.error?.toUpperCase()}`;
  return {
    message: te(key)
      ? // The server error code is translated only after checking the key exists.
        // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
        t(key)
      : data?.error_user_msg ||
        data?.message ||
        t('WHATSAPP_TEMPLATE_MGMT.FORM.SAVE_ERROR'),
    fields,
  };
};
