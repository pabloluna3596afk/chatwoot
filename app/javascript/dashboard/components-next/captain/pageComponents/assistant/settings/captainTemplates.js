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
