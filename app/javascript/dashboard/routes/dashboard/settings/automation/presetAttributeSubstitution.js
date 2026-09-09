// Walks schedule/conditions/actions and replaces every attribute_key that
// matches oldKey with newKey — the same placeholder (e.g. fecha_seguimiento)
// can appear in both the schedule and an action's params, and both must move
// together or the rule reads from one attribute and writes to another.
export const replaceAttributeKey = (node, oldKey, newKey) => {
  if (Array.isArray(node)) {
    node.forEach(item => replaceAttributeKey(item, oldKey, newKey));
    return;
  }
  if (!node || typeof node !== 'object') return;
  if (node.attribute_key === oldKey) node.attribute_key = newKey;
  Object.values(node).forEach(value =>
    replaceAttributeKey(value, oldKey, newKey)
  );
};
