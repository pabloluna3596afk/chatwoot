// A preset the CRM already suggested and the admin already accepted has
// nothing left to offer — re-showing it invites creating a second, redundant
// copy of the same rule. Mirrors businessRules/Index.vue's unusedPresets.
export const filterUnactivatedPresets = (presets, rules) =>
  (presets || []).filter(
    preset => !(rules || []).some(rule => rule.preset_id === preset.id)
  );
