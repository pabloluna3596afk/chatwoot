import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import CaptainInboxesAPI from 'dashboard/api/captain/inboxes';

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
export function useApprovedTemplates(assistantId) {
  const { t } = useI18n();
  const inboxes = useMapGetter('inboxes/getInboxes');
  const linkedInboxRecords = ref([]);
  const linkedInboxIds = computed(() =>
    linkedInboxRecords.value.map(inbox => inbox.id)
  );
  const inboxesLoading = ref(true);
  const inboxesFailed = ref(false);
  const linkedInboxes = computed(() =>
    linkedInboxRecords.value.map(inbox => ({
      ...(inboxes.value || []).find(item => item.id === inbox.id),
      ...inbox,
    }))
  );
  onMounted(async () => {
    if (!assistantId) {
      inboxesLoading.value = false;
      return;
    }
    try {
      const { data } = await CaptainInboxesAPI.get({
        assistantId,
      });
      linkedInboxRecords.value = data.payload || [];
    } catch {
      inboxesFailed.value = true;
    } finally {
      inboxesLoading.value = false;
    }
  });

  const approvedTemplates = computed(() => {
    const seen = new Map();
    const linkedIds = new Set(linkedInboxIds.value);
    (inboxes.value || [])
      .filter(inbox => linkedIds.has(inbox.id))
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
                label: '',
                template,
                inboxId: inbox.id,
                inboxNames: [inbox.name],
              });
            } else if (!seen.get(key).inboxNames.includes(inbox.name)) {
              seen.get(key).inboxNames.push(inbox.name);
            }
          });
      });
    return [...seen.values()].map(item => ({
      ...item,
      label: `${item.template.name} (${item.template.language}) · ${t(
        'CAPTAIN.ASSISTANTS.ENVIOS.APPROVED_IN',
        { inboxes: item.inboxNames.join(', ') }
      )}`,
    }));
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

  // The WhatsApp Cloud inbox that reports a "name|language" template as approved: the number that uploads the file of
  // its header (the sender uploads it again through the number it sends from).
  const templateInboxId = value => {
    const linkedIds = new Set(linkedInboxIds.value);
    const inbox = (inboxes.value || []).find(
      item =>
        linkedIds.has(item.id) &&
        item.channel_type === 'Channel::Whatsapp' &&
        item.provider === 'whatsapp_cloud' &&
        (item.message_templates || []).some(
          template =>
            templateKey(template) === value &&
            String(template.status).toLowerCase() === 'approved'
        )
    );
    return inbox?.id ?? null;
  };

  return {
    approvedTemplates,
    templateOptions,
    templateEntry,
    templateInboxId,
    linkedInboxes,
    linkedInboxRecords,
    inboxesLoading,
    inboxesFailed,
  };
}
