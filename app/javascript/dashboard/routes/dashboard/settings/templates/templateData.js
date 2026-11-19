// Eligibility and sources come from the WhatsApp payload, never from a local alias table.
export const templateDataEligible = template =>
  template?.status?.toUpperCase() === 'APPROVED' &&
  template.category?.toUpperCase() !== 'AUTHENTICATION';

export const templateVariables = template =>
  ['header', 'body'].flatMap(group => {
    const text =
      template?.components?.find(
        component => component.type?.toLowerCase() === group
      )?.text || '';
    // JSON object keys put numeric tokens first. Keep the order of the message
    // while leaving every source/eligibility decision to the server payload.
    const order = [...text.matchAll(/\{\{\s*([^}]+?)\s*\}\}/g)].map(
      ([, token]) => token
    );
    return Object.entries(template?.variable_sources?.[group] || {})
      .sort(([first], [second]) => order.indexOf(first) - order.indexOf(second))
      .map(([token, source]) => ({ token, group, ...source }));
  });

export const hasPendingVariables = template =>
  templateDataEligible(template) && Boolean(template.missing_variables?.length);

export const variableTokens = variables =>
  variables.map(token => `{{${token}}}`).join(', ');
