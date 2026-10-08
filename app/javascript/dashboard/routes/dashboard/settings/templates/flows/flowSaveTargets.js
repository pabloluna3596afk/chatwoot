import {
  buildBindings,
  writableFor,
} from 'dashboard/helper/templateVariableBindings';

export const saveTargetLabel = (target, t) =>
  target.group === 'system'
    ? t(`WHATSAPP_FLOWS.EDITOR.TARGETS.${target.name}`)
    : target.label;

export const saveTargets = (block, attributes = []) =>
  buildBindings(
    attributes.filter(item => item.attribute_model === 'contact_attribute')
  ).filter(binding => writableFor(binding, block));
