import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import VariablesAPI from 'dashboard/api/variables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';

// What the picker offers, in this order. Everything else stays in the catalog (emails and
// Captain use it) but is not useful when filling a WhatsApp template.
const GROUPS = [
  [
    'contact.name',
    'contact.first_name',
    'contact.last_name',
    'contact.phone',
    'contact.email',
    'contact.document_number',
    'contact.company_name',
    'contact.city',
    'contact.country_code',
  ],
  ['contact.custom_attribute'],
  ['conversation.display_id'],
  ['conversation.custom_attribute'],
  [
    'agent.name',
    'contact.assigned_agent.name',
    'inbox.name',
    'inbox.business_name',
    'account.name',
  ],
  ['date.today', 'date.tomorrow', 'date.yesterday'],
];
const rankOf = binding => {
  if (binding.reference?.kind === 'custom_attribute') {
    const scope = binding.reference.scope;
    const group = GROUPS.findIndex(paths =>
      paths.includes(`${scope}.custom_attribute`)
    );
    return group === -1 ? -1 : group * 100 + 50;
  }
  const path = binding.reference?.path;
  const group = GROUPS.findIndex(paths => paths.includes(path));
  return group === -1 ? -1 : group * 100 + GROUPS[group].indexOf(path);
};
const HTML_TAG = /<[a-z][\s\S]*>/i;
const isReadable = (binding, value) => {
  const text = String(value ?? '').trim();
  if (!text) return false;
  if (
    binding.reference?.kind !== 'custom_attribute' &&
    ['list', 'object'].includes(binding.type)
  )
    return false;
  if (/^[{[]/.test(text) && (text.includes('=>') || text.includes('":')))
    return false;
  return !HTML_TAG.test(text);
};
const normalizeName = label =>
  String(label || '')
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .trim()
    .toLowerCase();

export const useSystemVariables = (bindings, context, inboxId) => {
  const { t, te } = useI18n();
  const resolved = ref({});
  const status = ref('loading');
  const { run, abort } = useAbortableRequest();
  const catalog = computed(() =>
    bindings.value.filter(
      (item, index, all) =>
        all.findIndex(other => other.id === item.id) === index
    )
  );
  watch(
    [catalog, context, inboxId],
    async () => {
      abort();
      resolved.value = {};
      status.value = 'loading';
      const texts = catalog.value.map(item => item.expression);
      if (!texts.length) {
        status.value = 'ready';
        return;
      }
      const record = { inbox_id: Number(inboxId.value) };
      if (context.value.contact?.id)
        record.contact_id = context.value.contact.id;
      if (context.value.conversation?.id)
        record.conversation_id = context.value.conversation.id;
      try {
        const response = await run(async signal => {
          const batches = Array.from(
            { length: Math.ceil(texts.length / 100) },
            (_, index) => texts.slice(index * 100, (index + 1) * 100)
          );
          const responses = await Promise.all(
            batches.map(batch =>
              VariablesAPI.preview(
                { surface: 'message', contexts: [record], texts: batch },
                signal
              )
            )
          );
          return responses.flatMap(batch => batch.data.results[0]);
        });
        if (!response) return;
        resolved.value = Object.fromEntries(
          texts.map((text, index) => [text, response[index]])
        );
        status.value = 'ready';
      } catch {
        status.value = 'error';
      }
    },
    { immediate: true }
  );
  const options = computed(() => {
    const seen = new Set();
    return (
      catalog.value
        .map(binding => ({ binding, rank: rankOf(binding) }))
        .filter(({ rank }) => rank !== -1)
        .map(({ binding, rank }) => {
          const alias = `VARIABLE_PICKER.LABELS.${binding.name}`;
          const path = `VARIABLES.LABELS.${binding.reference?.path}`;
          const result = resolved.value[binding.expression];
          let label = binding.label;
          if (te(path)) label = t(path);
          if (te(alias)) label = t(alias);
          return {
            rank,
            option: {
              ...binding,
              label,
              value: result?.value ?? '',
              ready:
                result?.status === 'value' && isReadable(binding, result.value),
            },
          };
        })
        // A missing, empty or unreadable value is hidden, never shown disabled.
        .filter(({ option }) => option.ready)
        .sort(
          (a, b) =>
            a.rank - b.rank ||
            a.option.label.localeCompare(b.option.label, undefined, {
              sensitivity: 'base',
            })
        )
        // The same value may repeat, the variable name may not.
        .filter(({ option }) => {
          const key = normalizeName(option.label);
          if (seen.has(key)) return false;
          seen.add(key);
          return true;
        })
        .map(({ option }) => option)
    );
  });
  return { options, status };
};
