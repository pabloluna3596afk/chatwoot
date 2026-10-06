import { buildBindings } from 'dashboard/helper/templateVariableBindings';

const WRITABLE = new Set([
  'contact.name',
  'contact.email',
  'contact.phone',
  'contact.company_name',
  'contact.city',
  'contact.document_number',
]);

export const saveTargets = (block, attributes = []) =>
  buildBindings(
    attributes.filter(item => item.attribute_model === 'contact_attribute')
  ).filter(binding => {
    const attribute = attributes.find(
      item =>
        item.attribute_model === 'contact_attribute' &&
        `contact.custom_attribute.${item.attribute_key}` === binding.key
    );
    if (!WRITABLE.has(binding.key) && binding.group !== 'contact') return false;
    if (attribute?.formula && Object.keys(attribute.formula).length)
      return false;
    const type = attribute?.attribute_display_type || 'text';
    switch (block.type) {
      case 'short_text':
        return (
          type === 'text' || (block.input === 'number' && type === 'number')
        );
      case 'long_text':
      case 'checkbox':
        return type === 'text';
      case 'date':
        return ['date', 'text'].includes(type);
      case 'optin':
        return type === 'checkbox';
      case 'dropdown':
      case 'radio':
        return (
          type === 'text' ||
          (type === 'list' &&
            (block.options || []).every(option =>
              (attribute.attribute_values || []).includes(option.id)
            ))
        );
      default:
        return false;
    }
  });
