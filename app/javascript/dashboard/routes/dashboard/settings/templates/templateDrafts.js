import {
  emptyForm,
  previewTemplate,
  variableTokens,
  hasNamedVariables,
} from './templateForm';

export const LOCAL_STATUSES = [
  'draft',
  'submitting',
  'reconciling',
  'failed',
  'submitted',
];
export const META_STATUSES = [
  'PENDING',
  'APPROVED',
  'REJECTED',
  'PAUSED',
  'DISABLED',
  'IN_APPEAL',
];

export const currentSubmission = draft =>
  draft?.submissions?.find(item => item.revision === draft.lock_version);

export const draftDestination = (inboxId, inboxes) => {
  const inbox = inboxes.find(item => item.id === inboxId);
  return {
    preferred_channel_id: inbox?.channel_id ?? null,
    waba_id: inbox?.provider_config?.business_account_id ?? null,
  };
};

// Local definitions retain whitespace, incomplete fields and all opaque components.
// No remote handle belongs in a draft's editable definition.
export const draftFromForm = (form, inboxes) => ({
  title: form.title || '',
  name: form.name || null,
  language: form.language || null,
  category: form.category || null,
  parameter_format: form.parameterFormat || 'NAMED',
  ...draftDestination(form.inboxId, inboxes),
  ...(!form.inboxId ? { waba_id: form.wabaId } : {}),
  definition: {
    header: {
      format: form.header.format,
      text: form.header.text,
      examples: [...form.header.examples],
    },
    body: { text: form.body.text, examples: [...form.body.examples] },
    footer: { text: form.footer.text },
    buttons: form.buttons.map(button => ({
      type: button.type,
      text: button.text,
      ...(button.type === 'URL'
        ? { url: button.url, examples: [...button.examples] }
        : {}),
      ...(button.type === 'PHONE_NUMBER'
        ? { phone_number: button.phoneNumber }
        : {}),
      ...(button.type === 'COPY_CODE' ? { code: button.code } : {}),
    })),
    preserved: JSON.parse(JSON.stringify(form.preserved)),
  },
  variable_bindings: { ...form.variableBindings },
});

export const formFromDraft = (draft, inboxes) => {
  const form = emptyForm();
  const definition = draft.definition;
  const texts = [definition.header?.text, definition.body?.text];
  const hasNumberedVariables = texts.some(text =>
    variableTokens(text).some(token => /^\d+$/.test(token))
  );
  const parameterFormat =
    draft.parameter_format ||
    (!hasNamedVariables(...texts) && hasNumberedVariables
      ? 'POSITIONAL'
      : 'NAMED');
  Object.assign(form, {
    title: draft.title,
    wabaId: draft.waba_id,
    name: draft.name || '',
    language: draft.language || '',
    category: draft.category || '',
    parameterFormat,
    inboxId:
      inboxes.find(item => item.channel_id === draft.preferred_channel_id)
        ?.id ?? null,
    variableBindings: { ...draft.variable_bindings },
  });
  Object.assign(form.header, definition.header);
  form.header.handle = draft.media ? 'local_attachment' : '';
  form.header.fileName = draft.media?.filename || '';
  Object.assign(form.body, definition.body);
  Object.assign(form.footer, definition.footer);
  form.buttons = (definition.buttons || []).map(button => ({
    type: button.type,
    text: button.text || '',
    url: button.url || '',
    phoneNumber: button.phone_number || '',
    code: button.code || '',
    examples: [...(button.examples || [''])],
  }));
  form.preserved = {
    components: [],
    buttons: [],
    ...JSON.parse(JSON.stringify(definition.preserved || {})),
  };
  return form;
};

export const hasOpaqueComponents = form =>
  form.category === 'AUTHENTICATION' ||
  Object.values(form.preserved).some(items => items.length);

export const draftVariableNamesValid = form =>
  [form.header.text, form.body.text].every(text =>
    variableTokens(text).every(
      token => /^\d+$/.test(token) || /^[a-z_]+$/.test(token)
    )
  );

export const draftRow = (draft, inboxes) => {
  const form = formFromDraft(draft, inboxes);
  const owners = inboxes.filter(inbox =>
    draft.waba_id
      ? inbox.provider_config?.business_account_id === draft.waba_id
      : false
  );
  return {
    ...previewTemplate(form),
    ...draft,
    key: `draft-${draft.id}`,
    isLocalDraft: true,
    inboxes: owners,
    inboxNames: owners.map(inbox => inbox.name).join(', '),
    lastUpdatedAt: draft.updated_at,
    searchableContent: JSON.stringify(draft.definition),
    remoteStatus: currentSubmission(draft)?.remote_status,
  };
};
