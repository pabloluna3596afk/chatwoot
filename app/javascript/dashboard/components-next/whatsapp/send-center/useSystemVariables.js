import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import VariablesAPI from 'dashboard/api/variables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';

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
  const options = computed(() =>
    catalog.value.map(binding => {
      const alias = `VARIABLE_PICKER.LABELS.${binding.name}`;
      const path = `VARIABLES.LABELS.${binding.reference.path}`;
      const result = resolved.value[binding.expression];
      let label = binding.label;
      if (te(path)) label = t(path);
      if (te(alias)) label = t(alias);
      return {
        ...binding,
        label,
        value: result?.value ?? '',
        disabled:
          !result ||
          result.status !== 'value' ||
          !String(result.value ?? '').trim(),
      };
    })
  );
  return { options, status };
};
