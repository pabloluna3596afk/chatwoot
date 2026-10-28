<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from '../icon/Icon.vue';

const props = defineProps({
  messages: { type: Array, required: true },
  defaultCollapsed: { type: Boolean, default: false },
});
const { t } = useI18n();
const isExpanded = ref(!props.defaultCollapsed);
const trigger = ref(null);
const stepsPanelId = computed(
  () => `copilot-thinking-steps-${props.messages[0]?.id || 'latest'}`
);
const steps = computed(() => {
  const result = [];
  props.messages.forEach(message => {
    const data = message.message || {};
    const toolName = data.function_name;
    const content = data.content || '';
    const savedStatus = ['in_progress', 'completed', 'empty', 'error'].includes(
      data.tool_status
    );
    let status = savedStatus ? data.tool_status : 'in_progress';
    if (!savedStatus) {
      if (/^(Completed|Completed with errors)\b/i.test(content)) {
        status = /errors/i.test(content) ? 'error' : 'completed';
      } else if (/\b(error|failed|failure)\b/i.test(content)) {
        status = 'error';
      }
    }
    const previous = [...result]
      .reverse()
      .find(
        step => step.functionName === toolName && step.status === 'in_progress'
      );
    if (previous && status !== 'in_progress') {
      previous.status = status;
      previous.message = content;
      previous.createdAt = message.created_at || previous.createdAt;
      return;
    }
    result.push({
      id: message.id,
      functionName: toolName,
      status,
      message: content,
      createdAt: message.created_at,
    });
  });
  return result;
});
const isWorking = computed(() =>
  steps.value.some(step => step.status === 'in_progress')
);
const duration = computed(() => {
  const timestamps = props.messages
    .map(message => Number(message.created_at))
    .filter(Boolean);
  if (timestamps.length < 2) return null;
  const seconds = Math.max(...timestamps) - Math.min(...timestamps);
  return seconds < 60
    ? { value: Math.max(1, seconds), unit: 'seconds' }
    : { value: Math.round(seconds / 60), unit: 'minutes' };
});
const summary = computed(() => {
  const count =
    steps.value.length === 1
      ? t('CAPTAIN.COPILOT.STEPS_SUMMARY_ONE')
      : t('CAPTAIN.COPILOT.STEPS_SUMMARY', { count: steps.value.length });
  if (!duration.value) return count;
  const durationLabel =
    duration.value.unit === 'seconds'
      ? t('CAPTAIN.COPILOT.STEPS_DURATION_seconds', {
          duration: duration.value.value,
        })
      : t('CAPTAIN.COPILOT.STEPS_DURATION_minutes', {
          duration: duration.value.value,
        });
  return `${count} ${durationLabel}`;
});
const conversationId = message => message.match(/#(\d+)/)?.[1] || '';
const labelFor = step => {
  const key = `CAPTAIN.COPILOT.TOOLS.${step.functionName}`;
  // Tool names are supplied by the server and unknown names use a safe fallback.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  const translation = t(key, { id: conversationId(step.message) });
  return translation === key ? t('CAPTAIN.COPILOT.TOOLS.generic') : translation;
};
const iconFor = name =>
  ({
    search_conversation: 'i-lucide-search',
    get_conversation: 'i-lucide-message-square-text',
    search_contacts: 'i-lucide-users-round',
    get_contact: 'i-lucide-user-round',
    get_data: 'i-lucide-chart-no-axes-column-increasing',
    list_labels: 'i-lucide-tags',
    describe_schema: 'i-lucide-database',
    search_articles: 'i-lucide-book-open',
    get_article: 'i-lucide-book-open-check',
    search_documentation: 'i-lucide-book-open',
    search_linear_issues: 'i-lucide-list-checks',
    propose_action: 'i-lucide-sparkles',
  })[name] || 'i-lucide-search';
const humanStatusMessage = step => {
  const value = step.message.toLowerCase();
  if (
    step.status === 'empty' ||
    /no results|no records|empty|not found/.test(value)
  )
    return t('CAPTAIN.COPILOT.STEP_EMPTY');
  return t('CAPTAIN.COPILOT.STEP_ERROR');
};
watch(
  () => props.defaultCollapsed,
  value => {
    isExpanded.value = !value;
  }
);
watch(isExpanded, async expanded => {
  if (expanded) {
    await nextTick();
    trigger.value?.focus();
  }
});
</script>

<template>
  <section class="rounded-xl border border-n-weak bg-n-surface-2 px-3 py-2">
    <button
      ref="trigger"
      type="button"
      class="group flex min-h-9 w-full items-center gap-2 text-start text-xs font-medium text-n-slate-11 transition-colors hover:text-n-slate-12"
      :aria-expanded="isExpanded"
      :aria-controls="stepsPanelId"
      @click="isExpanded = !isExpanded"
    >
      <Icon
        :icon="isExpanded ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
        class="size-4 shrink-0"
        aria-hidden="true"
      />
      <span class="flex-1">{{ summary }}</span>
      <Icon
        v-if="isWorking"
        icon="i-lucide-loader-circle"
        class="size-4 animate-spin text-n-blue-9 motion-reduce:animate-none"
        aria-hidden="true"
      />
    </button>
    <Transition
      enter-active-class="transition duration-150 ease-out motion-reduce:transition-none"
      enter-from-class="-translate-y-1 opacity-0"
      enter-to-class="translate-y-0 opacity-100"
      leave-active-class="transition duration-100 ease-in motion-reduce:transition-none"
      leave-from-class="translate-y-0 opacity-100"
      leave-to-class="-translate-y-1 opacity-0"
    >
      <ol
        v-if="isExpanded"
        :id="stepsPanelId"
        class="flex flex-col gap-2 pb-1 ps-1 pt-2"
        role="list"
        aria-live="polite"
        :aria-label="t('CAPTAIN.COPILOT.STEPS_LABEL')"
      >
        <li
          v-for="step in steps"
          :key="step.id"
          class="flex items-start gap-2 text-sm text-n-slate-12"
          :role="step.status === 'in_progress' ? 'status' : null"
        >
          <Icon
            :icon="
              step.status === 'error'
                ? 'i-lucide-triangle-alert'
                : step.status === 'empty'
                  ? 'i-lucide-circle-minus'
                  : iconFor(step.functionName)
            "
            class="mt-0.5 size-4 shrink-0"
            :class="{
              'animate-spin text-n-blue-9 motion-reduce:animate-none':
                step.status === 'in_progress',
              'text-n-teal-10': step.status === 'completed',
              'text-n-amber-10': step.status === 'error',
              'text-n-slate-10': step.status === 'empty',
            }"
            aria-hidden="true"
          />
          <span class="min-w-0 break-words">
            <span>{{ labelFor(step) }}</span>
            <span
              v-if="step.status === 'error' || step.status === 'empty'"
              class="block text-xs text-n-amber-11"
            >
              {{ humanStatusMessage(step) }}
            </span>
          </span>
          <Icon
            v-if="step.status === 'completed'"
            icon="i-lucide-check"
            class="ms-auto mt-0.5 size-4 shrink-0 text-n-teal-10"
            aria-hidden="true"
          />
        </li>
      </ol>
    </Transition>
  </section>
</template>
