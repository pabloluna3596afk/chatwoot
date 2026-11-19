import { TemplateNormalizer } from 'dashboard/services/TemplateNormalizer';
import {
  PLATFORMS,
  WA_HEADER_FORMATS,
} from 'dashboard/services/TemplateConstants';
import {
  bubbleFromTemplate,
  fillVariables,
} from 'dashboard/components-next/whatsapp/bubbleFromTemplate';

const sampleValue = (value, previewValues) => {
  if (typeof value !== 'string') return '';
  return value.replace(
    /\{\{\s*[^}]+\s*\}\}/g,
    expression =>
      previewValues[expression] ||
      previewValues[expression.slice(2, -2).trim()] ||
      expression
  );
};

export const previewVariables = (
  template,
  processedParams = {},
  previewValues = {}
) => {
  const values = { body: {}, header: {} };
  const normalized = TemplateNormalizer.normalize(template, PLATFORMS.WHATSAPP);
  const groups = [
    ['body', normalized.body?.text || ''],
    [
      'header',
      normalized.header?.format === WA_HEADER_FORMATS.TEXT
        ? normalized.header.text || ''
        : '',
    ],
  ];

  groups.forEach(([group, text]) => {
    const params = processedParams[group] || {};
    [...text.matchAll(/\{\{\s*([^}]+?)\s*\}\}/g)].forEach(([, name]) => {
      const binding = params[name];
      values[group][name] =
        typeof binding === 'string' && binding.trim()
          ? sampleValue(binding, previewValues)
          : '';
    });
  });

  return values;
};

export const bubbleForCaptain = (template, processedParams, previewValues) => {
  const variables = previewVariables(template, processedParams, previewValues);
  const bubble = bubbleFromTemplate(template, variables.body);
  const normalized = TemplateNormalizer.normalize(template, PLATFORMS.WHATSAPP);

  if (normalized.header?.format === WA_HEADER_FORMATS.TEXT) {
    bubble.header = fillVariables(normalized.header.text, variables.header);
  }

  return { bubble, variables };
};
