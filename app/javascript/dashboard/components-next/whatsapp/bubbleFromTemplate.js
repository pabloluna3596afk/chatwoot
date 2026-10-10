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
