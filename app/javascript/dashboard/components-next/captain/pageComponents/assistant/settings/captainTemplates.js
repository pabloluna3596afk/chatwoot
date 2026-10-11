export const templateKey = template => `${template.name}|${template.language}`;

const STATIC_BUTTONS = ['QUICK_REPLY', 'PHONE_NUMBER', 'URL'];

// Captain sends a template by filling its text variables only: no header file, no button that changes per customer
// (a dynamic link, a copy code, a Flow button) and no card or offer layouts.
export const isSupportedForCaptain = template =>
  (template.components || []).every(component => {
    if (component.type === 'BODY' || component.type === 'FOOTER') return true;
    if (component.type === 'HEADER') return component.format === 'TEXT';
    if (component.type === 'BUTTONS')
      return (component.buttons || []).every(
        button =>
          STATIC_BUTTONS.includes(button.type) &&
          !String(button.url || '').includes('{{')
      );
    return false;
  });

const VARIABLE = /\{\{\s*([^}\s]+)\s*\}\}/g;

// The variables of the body and of a text header: { component: 'body' | 'header', name }. Same rule as the server
// (Captain::TemplateMessage.variables), which is the one that decides what can be saved and sent.
export const templateVariables = template =>
  (template?.components || []).flatMap(component => {
    const kind = { BODY: 'body', HEADER: 'header' }[
      String(component.type).toUpperCase()
    ];
    if (!kind || (kind === 'header' && component.format !== 'TEXT')) return [];
    const names = [...String(component.text || '').matchAll(VARIABLE)].map(
      match => match[1]
    );
    return [...new Set(names)].map(name => ({ component: kind, name }));
  });

// Every variable has a text. (isWhatsAppComplete only looks at the ones already in the params, so an untouched
// template passes it; Captain cannot send with a variable that has no value.)
export const variablesFilled = (template, params) =>
  templateVariables(template).every(({ component, name }) =>
    String(params?.[component]?.[name] ?? '').trim()
  );
