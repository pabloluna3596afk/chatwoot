import { TemplateNormalizer } from 'dashboard/services/TemplateNormalizer';
import {
  PLATFORMS,
  WA_HEADER_FORMATS,
  WA_MEDIA_FORMATS,
} from 'dashboard/services/TemplateConstants';

// Missing example values show as [name] so the author sees what is still to be filled in.
export const fillVariables = (text, variables = {}) =>
  text
    ? text.replace(/\{\{([^}]+)\}\}/g, (match, name) =>
        variables[name] !== undefined && variables[name] !== ''
          ? variables[name]
          : `[${name}]`
      )
    : '';

// The example values a template already carries: positional [a, b] -> {1: a, 2: b}, named [{param_name, example}].
export const variablesFromTemplate = template => {
  const result = {};
  (template?.components || []).forEach(component => {
    if (component.type === 'BODY') {
      const example = component.example || {};
      (example.body_text?.[0] || []).forEach((value, index) => {
        result[index + 1] = value;
      });
      (example.body_text_named_params || []).forEach(param => {
        result[param.param_name] = param.example;
      });
    }
    if (component.type === 'HEADER' && component.format === 'TEXT') {
      const example = component.example || {};
      if (example.header_text?.[0]) result[1] = example.header_text[0];
      (example.header_text_named_params || []).forEach(param => {
        result[param.param_name] = param.example;
      });
    }
  });
  return result;
};

// A WhatsApp template (Meta shape) as the props of WhatsAppBubble.vue.
export const bubbleFromTemplate = (template, variables = {}) => {
  const normalized = TemplateNormalizer.normalize(template, PLATFORMS.WHATSAPP);
  const { header, footer } = normalized;
  return {
    header:
      header?.format === WA_HEADER_FORMATS.TEXT
        ? fillVariables(header.text, variables)
        : '',
    headerMedia:
      header && WA_MEDIA_FORMATS.includes(header.format) ? header.format : '',
    body: fillVariables(normalized.body?.text, variables),
    footer: fillVariables(footer?.text, variables),
    buttons: (normalized.buttons || []).map(button => ({
      text: fillVariables(button.text, variables),
      type: button.type,
    })),
  };
};
