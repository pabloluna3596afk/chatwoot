// The WhatsApp template form (create / edit): its limits, validation, the payload for the API and the way back from a
// Meta template to a form. The limits are the ones Whatsapp::TemplateComponentsBuilder enforces on the server.

export const LIMITS = {
  body: 1024,
  headerText: 60,
  footer: 60,
  buttonText: 25,
  buttons: 10,
  urlButtons: 2,
  phoneButtons: 1,
};

export const CATEGORIES = ['UTILITY', 'MARKETING'];
export const HEADER_FORMATS = ['NONE', 'TEXT', 'IMAGE', 'VIDEO', 'DOCUMENT'];
export const MEDIA_FORMATS = ['IMAGE', 'VIDEO', 'DOCUMENT'];
export const BUTTON_TYPES = ['QUICK_REPLY', 'URL', 'PHONE_NUMBER'];
export const MEDIA_ACCEPT = {
  IMAGE: 'image/jpeg,image/png',
  VIDEO: 'video/mp4,video/3gpp',
  DOCUMENT: 'application/pdf',
};

const VARIABLE = /\{\{(\d+)\}\}/g;
const NAME_FORMAT = /^[a-z0-9_]{1,512}$/;
const URL_FORMAT = /^https?:\/\/\S+$/;
const PHONE_FORMAT = /^\+\d{6,18}$/;

export const emptyForm = () => ({
  inboxId: null,
  name: '',
  language: 'es',
  category: 'UTILITY',
  header: {
    format: 'NONE',
    text: '',
    examples: [''],
    handle: '',
    fileName: '',
  },
  body: { text: '', examples: [] },
  footer: { text: '' },
  buttons: [],
});

// "Recordatorio de cita" -> "recordatorio_de_cita"
export const toSnakeCase = value =>
  String(value || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');

// The variable numbers in a text, in order of appearance and without repeats: "{{1}} y {{2}} y {{1}}" -> [1, 2]
export const variableNumbers = text => {
  const numbers = [...String(text || '').matchAll(VARIABLE)].map(match =>
    Number(match[1])
  );
  return [...new Set(numbers)];
};

// How many examples a field needs: one per variable (header and URL have at most one).
export const bodyExampleCount = text => variableNumbers(text).length;

const hasVariableAtEdge = text => /^\{\{\d+\}\}|\{\{\d+\}\}$/.test(text.trim());
const isSequential = numbers => numbers.every((n, index) => n === index + 1);

const validateHeader = (header, errors) => {
  if (header.format === 'TEXT') {
    const text = header.text.trim();
    const numbers = variableNumbers(text);
    if (!text) errors['header.text'] = 'HEADER_TEXT_REQUIRED';
    else if (text.length > LIMITS.headerText)
      errors['header.text'] = 'HEADER_TEXT_TOO_LONG';
    else if (numbers.length > 1 || (numbers.length && numbers[0] !== 1))
      errors['header.text'] = 'HEADER_ONE_VARIABLE';
    else if (numbers.length && !String(header.examples?.[0] || '').trim())
      errors['header.example'] = 'EXAMPLE_REQUIRED';
  } else if (MEDIA_FORMATS.includes(header.format) && !header.handle) {
    errors['header.media'] = 'HEADER_MEDIA_REQUIRED';
  }
};

const validateBody = (body, errors) => {
  const text = body.text.trim();
  const numbers = variableNumbers(text);
  if (!text) {
    errors['body.text'] = 'BODY_REQUIRED';
  } else if (text.length > LIMITS.body) {
    errors['body.text'] = 'BODY_TOO_LONG';
  } else if (!isSequential(numbers)) {
    errors['body.text'] = 'VARIABLES_NOT_SEQUENTIAL';
  } else if (numbers.length && hasVariableAtEdge(text)) {
    errors['body.text'] = 'VARIABLE_AT_EDGE';
  } else if (
    numbers.some((_, index) => !String(body.examples?.[index] || '').trim())
  ) {
    errors['body.examples'] = 'EXAMPLE_REQUIRED';
  }
};

const validateFooter = (footer, errors) => {
  const text = footer.text.trim();
  if (text.length > LIMITS.footer) errors['footer.text'] = 'FOOTER_TOO_LONG';
  else if (variableNumbers(text).length)
    errors['footer.text'] = 'FOOTER_NO_VARIABLES';
};

const validateButton = (button, index, errors) => {
  const key = `buttons.${index}`;
  const text = button.text.trim();
  if (!text) errors[`${key}.text`] = 'BUTTON_TEXT_REQUIRED';
  else if (text.length > LIMITS.buttonText)
    errors[`${key}.text`] = 'BUTTON_TEXT_TOO_LONG';

  if (button.type === 'URL') {
    const url = button.url.trim();
    const numbers = variableNumbers(url);
    if (!URL_FORMAT.test(url)) errors[`${key}.url`] = 'URL_INVALID';
    else if (numbers.length > 1 || (numbers.length && !url.endsWith('{{1}}')))
      errors[`${key}.url`] = 'URL_VARIABLE_AT_END';
    else if (numbers.length && !String(button.examples?.[0] || '').trim())
      errors[`${key}.example`] = 'EXAMPLE_REQUIRED';
  } else if (
    button.type === 'PHONE_NUMBER' &&
    !PHONE_FORMAT.test(button.phoneNumber.trim())
  ) {
    errors[`${key}.phone`] = 'PHONE_INVALID';
  }
};

const validateButtons = (buttons, errors) => {
  if (buttons.length > LIMITS.buttons) errors.buttons = 'TOO_MANY_BUTTONS';
  buttons.forEach((button, index) => validateButton(button, index, errors));
  if (buttons.filter(b => b.type === 'URL').length > LIMITS.urlButtons)
    errors.buttons = 'TOO_MANY_URL_BUTTONS';
  if (
    buttons.filter(b => b.type === 'PHONE_NUMBER').length > LIMITS.phoneButtons
  )
    errors.buttons = 'TOO_MANY_PHONE_BUTTONS';
};

// Returns { 'field.path': 'ERROR_KEY' } (keys of WHATSAPP_TEMPLATE_MGMT.FORM.ERRORS); empty when the form is valid.
// `isEdit` skips the name and language (they cannot change once the template exists).
export const validateForm = (form, { isEdit = false } = {}) => {
  const errors = {};
  if (!isEdit) {
    if (!form.inboxId) errors.inboxId = 'CHANNEL_REQUIRED';
    if (!NAME_FORMAT.test(form.name)) errors.name = 'NAME_INVALID';
    if (!form.language) errors.language = 'LANGUAGE_REQUIRED';
  }
  if (!CATEGORIES.includes(form.category)) errors.category = 'CATEGORY_INVALID';
  validateHeader(form.header, errors);
  validateBody(form.body, errors);
  validateFooter(form.footer, errors);
  validateButtons(form.buttons, errors);
  return errors;
};

const buttonPayload = button => {
  if (button.type === 'URL') {
    return {
      type: 'URL',
      text: button.text.trim(),
      url: button.url.trim(),
      examples: variableNumbers(button.url).length ? [button.examples[0]] : [],
    };
  }
  if (button.type === 'PHONE_NUMBER') {
    return {
      type: 'PHONE_NUMBER',
      text: button.text.trim(),
      phone_number: button.phoneNumber.trim(),
    };
  }
  return { type: 'QUICK_REPLY', text: button.text.trim() };
};

// The body of POST / PATCH .../whatsapp_templates ({ template: ... }).
export const buildPayload = form => {
  const count = bodyExampleCount(form.body.text);
  return {
    name: form.name,
    language: form.language,
    category: form.category,
    header: {
      format: form.header.format,
      text: form.header.text.trim(),
      examples: variableNumbers(form.header.text).length
        ? [form.header.examples[0]]
        : [],
      handle: form.header.handle,
    },
    body: {
      text: form.body.text.trim(),
      examples: form.body.examples.slice(0, count),
    },
    footer: { text: form.footer.text.trim() },
    buttons: form.buttons.map(buttonPayload),
  };
};

// The template as Meta stores it (what the list returns), from the form: for the live preview.
export const previewTemplate = (form, headerPreviewUrl = '') => {
  const components = [];
  if (form.header.format === 'TEXT' && form.header.text.trim()) {
    components.push({
      type: 'HEADER',
      format: 'TEXT',
      text: form.header.text.trim(),
    });
  } else if (MEDIA_FORMATS.includes(form.header.format)) {
    components.push({
      type: 'HEADER',
      format: form.header.format,
      example: { header_handle: [headerPreviewUrl] },
    });
  }
  components.push({ type: 'BODY', text: form.body.text });
  if (form.footer.text.trim())
    components.push({ type: 'FOOTER', text: form.footer.text.trim() });
  if (form.buttons.length) {
    components.push({
      type: 'BUTTONS',
      buttons: form.buttons.map(button => ({
        type: button.type,
        text: button.text || '…',
        url: button.url,
        phone_number: button.phoneNumber,
      })),
    });
  }
  return {
    name: form.name || 'plantilla',
    language: form.language,
    category: form.category,
    status: 'APPROVED',
    components,
  };
};

// The values the preview shows in place of {{n}}.
export const previewVariables = form => {
  const variables = {};
  variableNumbers(form.body.text).forEach((number, index) => {
    variables[String(number)] = form.body.examples[index] || '';
  });
  if (variableNumbers(form.header.text).length)
    variables['1'] = form.header.examples[0] || variables['1'] || '';
  return variables;
};

// Whether a synced template can be edited here: only the kinds this form can express (text/media header, body,
// footer, quick reply / URL / phone buttons). Anything else (carousels, flow or copy-code buttons...) is managed in Meta.
export const isEditable = template => {
  const components = template?.components;
  if (!Array.isArray(components)) return false;

  return components.every(component => {
    if (component.type === 'HEADER')
      return ['TEXT', ...MEDIA_FORMATS].includes(component.format);
    if (component.type === 'BUTTONS')
      return (component.buttons || []).every(button =>
        BUTTON_TYPES.includes(button.type)
      );
    return ['BODY', 'FOOTER'].includes(component.type);
  });
};

// A form from a Meta template, to edit it. Media headers keep no handle: a new example file is needed to save.
export const formFromTemplate = (template, inboxId) => {
  const form = emptyForm();
  form.inboxId = inboxId;
  form.name = template.name;
  form.language = template.language;
  form.category = template.category || 'UTILITY';

  (template.components || []).forEach(component => {
    if (component.type === 'HEADER') {
      form.header.format = component.format;
      form.header.text = component.text || '';
      form.header.examples = [component.example?.header_text?.[0] || ''];
    } else if (component.type === 'BODY') {
      form.body.text = component.text || '';
      form.body.examples = [...(component.example?.body_text?.[0] || [])];
    } else if (component.type === 'FOOTER') {
      form.footer.text = component.text || '';
    } else if (component.type === 'BUTTONS') {
      form.buttons = (component.buttons || []).map(button => ({
        type: button.type,
        text: button.text || '',
        url: button.url || '',
        phoneNumber: button.phone_number || '',
        examples: [button.example?.[0] || ''],
      }));
    }
  });
  return form;
};

export const newButton = type => ({
  type,
  text: '',
  url: '',
  phoneNumber: '',
  examples: [''],
});

// Meta's rules for an edit, as a short list the form shows: what the status allows.
export const editRules = status => {
  const state = String(status || '').toUpperCase();
  return {
    // Meta only lets approved, rejected and paused templates be edited
    canEdit: ['APPROVED', 'REJECTED', 'PAUSED'].includes(state),
    categoryLocked: state === 'APPROVED',
  };
};
