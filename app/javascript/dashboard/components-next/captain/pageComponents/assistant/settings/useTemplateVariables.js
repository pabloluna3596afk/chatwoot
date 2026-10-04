import { useI18n } from 'vue-i18n';

const APPOINTMENT_KEYS = [
  'contact.name',
  'contact.first_name',
  'appointment.date',
  'appointment.time',
  'appointment.datetime',
  'appointment.title',
  'assistant.name',
];
const CONTACT_KEYS = [
  'contact.name',
  'contact.first_name',
  'assistant.name',
  'account.name',
];

// What a template variable is filled with by its name, so a template made with named variables
// ({{nombre}}, {{cita}}, {{fecha}}, {{hora}}) needs no setup when it is picked.
export const APPOINTMENT_DEFAULT_VALUES = {
  nombre: '{{ contact.name }}',
  cita: '{{ appointment.title }}',
  fecha: '{{ appointment.date }}',
  hora: '{{ appointment.time }}',
  asistente: '{{ assistant.name }}',
};
export const CONTACT_DEFAULT_VALUES = {
  nombre: '{{ contact.name }}',
  asistente: '{{ assistant.name }}',
  empresa: '{{ account.name }}',
};

// The variables the owner can put in the fields of a Captain template, with friendly labels, and a sample value of
// each for the preview. The key is the Liquid expression the backend renders when the message is sent
// (Captain::TemplateMessage.drops).
export function useTemplateVariables({ appointment }) {
  const { t } = useI18n();
  const keys = appointment ? APPOINTMENT_KEYS : CONTACT_KEYS;

  const variableOptions = keys.map(key => ({
    key,
    label: t(`CAPTAIN.ASSISTANTS.FORM.TEMPLATE_VARIABLES.LABELS.${key}`),
    description: t(`CAPTAIN.ASSISTANTS.FORM.TEMPLATE_VARIABLES.SAMPLES.${key}`),
  }));

  const previewValues = Object.fromEntries(
    keys.map(key => [
      key,
      t(`CAPTAIN.ASSISTANTS.FORM.TEMPLATE_VARIABLES.SAMPLES.${key}`),
    ])
  );

  return { variableOptions, previewValues };
}
