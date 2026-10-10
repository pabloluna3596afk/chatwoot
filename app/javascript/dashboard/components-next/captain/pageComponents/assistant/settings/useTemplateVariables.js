import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import {
  APPOINTMENT_BINDINGS,
  defaultValuesFor,
} from 'dashboard/helper/templateVariableBindings';

// What a template variable is filled with in a Captain message, from the same engine as the send dialog and the
// campaigns (templateVariableBindings): one table says which name means which value, so a template made in ChatHub
// ({{nombre}}, {{primer_nombre}}, {{correo}}...) fills itself in the same way here. Captain adds what only it knows:
// the assistant, the account and, for appointment messages, the appointment.
const ALWAYS = ['asistente', 'cuenta'];

// `variableOptions` are the variables the owner can insert in a field (with a sample value of each for the preview),
// `defaultValues` what a variable starts with by its name, `previewValues` the sample of each Liquid key.
export function useTemplateVariables({ appointment }) {
  const { t } = useI18n();
  const { bindings } = useTemplateBindings('message');

  const available = computed(() => {
    const extra = APPOINTMENT_BINDINGS.filter(
      binding => appointment || ALWAYS.includes(binding.name)
    );
    const names = new Set(extra.map(binding => binding.name));
    return [
      ...bindings.value.filter(binding => !names.has(binding.name)),
      ...extra,
    ];
  });

  const sample = key => {
    const path = `CAPTAIN.ASSISTANTS.FORM.TEMPLATE_VARIABLES.SAMPLES.${key}`;
    const text = t(path);
    return text === path ? '' : text;
  };

  // One option per value: two names for the same value ({{cita}} and {{tema}}) are offered once.
  const variableOptions = computed(() => {
    const options = new Map();
    available.value
      .filter(binding => binding.readable)
      .forEach(binding => {
        if (options.has(binding.key)) return;
        options.set(binding.key, {
          key: binding.key,
          label: binding.label || t(`VARIABLE_PICKER.LABELS.${binding.name}`),
          description: sample(binding.key) || binding.name,
        });
      });
    return [...options.values()];
  });

  const defaultValues = computed(() => defaultValuesFor(available.value));

  const previewValues = computed(() =>
    Object.fromEntries(
      variableOptions.value.map(option => [option.key, option.description])
    )
  );

  return { variableOptions, defaultValues, previewValues };
}
