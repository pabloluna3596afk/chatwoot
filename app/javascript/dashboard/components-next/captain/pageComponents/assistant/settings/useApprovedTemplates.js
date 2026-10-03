import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

const templateKey = template => `${template.name}|${template.language}`;

// A picked template travels as { name, language, processed_params }; the select works with "name|language".
// `processed_params` is the text of each variable ({ body: { 1: '{{ contact.name }}' }, header: { ... } }), the same
// shape automations save.
export const templateFromValue = (value, processedParams = {}) => {
  if (!value) return null;
  const [name, language] = value.split('|');
  return { name, language, processed_params: processedParams };
};

export const templateToValue = template =>
  template?.name && template?.language ? templateKey(template) : '';

// Approved WhatsApp templates of the account's inboxes, for the template pickers of the Captain settings.
export function useApprovedTemplates() {
  const { t } = useI18n();
  const inboxes = useMapGetter('inboxes/getInboxes');

  const approvedTemplates = computed(() => {
    const seen = new Map();
    (inboxes.value || [])
      .filter(inbox => inbox.channel_type === 'Channel::Whatsapp')
      .forEach(inbox => {
        (inbox.message_templates || [])
          .filter(
            template => String(template.status).toLowerCase() === 'approved'
          )
          .forEach(template => {
            const key = templateKey(template);
            if (!seen.has(key)) {
              seen.set(key, {
                value: key,
                label: `${template.name} (${template.language})`,
                template,
              });
            }
          });
      });
    return [...seen.values()];
  });

  // The saved template stays in the list even when its inbox no longer reports it as approved.
  const templateOptions = current => {
    const known = approvedTemplates.value.some(item => item.value === current);
    const options =
      current && !known
        ? [
            ...approvedTemplates.value,
            { value: current, label: current.replace('|', ' (') + ')' },
          ]
        : approvedTemplates.value;
    return [
      {
        value: '',
        label: t('CAPTAIN.ASSISTANTS.FORM.TEMPLATE_PLACEHOLDER'),
      },
      ...options,
    ];
  };

  // The template (with its components) behind a "name|language" value, or undefined when no inbox has it approved.
  const templateEntry = value =>
    approvedTemplates.value.find(item => item.value === value)?.template;

  return { approvedTemplates, templateOptions, templateEntry };
}
