import { writableFor } from 'dashboard/helper/templateVariableBindings';

export const saveTargetLabel = (target, t) =>
  target.scope === 'system'
    ? t(`WHATSAPP_FLOWS.EDITOR.TARGETS.${target.name}`)
    : target.label;

export const saveTargets = (block, bindings = []) =>
  bindings.filter(binding => writableFor(binding, block));
