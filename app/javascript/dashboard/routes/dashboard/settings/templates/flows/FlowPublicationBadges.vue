<script setup>
// What Meta says about a flow, one badge per WhatsApp Cloud WABA: green published, amber draft in Meta, red error or
// refused by Meta (with Meta's reason: where and what), grey never sent or retired. Only the WhatsApp ones carry the
// small WhatsApp icon. "Reintentar" is offered on errors.
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  // rows of useFlowPublications
  rows: { type: Array, default: () => [] },
  // Show the errors Meta gave under the badge (the list shows only the badge).
  detailed: { type: Boolean, default: false },
  canRetry: { type: Boolean, default: false },
  // The flow is being sent right now: a draft is on its way, not waiting.
  sending: { type: Boolean, default: false },
});

const emit = defineEmits(['retry']);
const { t } = useI18n();

const TONES = {
  published: 'bg-n-teal-3 text-n-teal-11',
  draft: 'bg-n-amber-3 text-n-amber-11',
  error: 'bg-n-ruby-3 text-n-ruby-11',
  blocked: 'bg-n-ruby-3 text-n-ruby-11',
  throttled: 'bg-n-ruby-3 text-n-ruby-11',
  deprecated: 'bg-n-alpha-2 text-n-slate-11 line-through',
  none: 'bg-n-alpha-2 text-n-slate-11',
};

const tone = row => TONES[row.state] || TONES.none;
// Meta's reason as plain text, the same lines the editor shows; the list has no room for them, so it is a tooltip.
const reason = row =>
  row.errors
    .map(error =>
      error.path ? `${error.path}: ${error.message}` : error.message
    )
    .join('\n');
const label = (row, sending) =>
  row.state === 'draft' && sending
    ? t('WHATSAPP_FLOWS.META.STATE.sending')
    : t(`WHATSAPP_FLOWS.META.STATE.${row.state}`);
</script>

<template>
  <ul class="flex flex-col gap-2 p-0 m-0 list-none" data-testid="flow-meta">
    <li
      v-for="row in rows"
      :key="row.wabaId"
      class="flex flex-col gap-1.5"
      data-testid="flow-meta-row"
    >
      <div class="flex flex-wrap items-center gap-2">
        <span
          class="inline-flex items-center gap-1.5 px-2.5 py-0.5 text-xs font-semibold rounded-full"
          :class="tone(row)"
          :data-state="row.state"
          :title="!detailed && row.errors.length ? reason(row) : undefined"
          data-testid="flow-meta-badge"
        >
          <span class="i-woot-whatsapp size-3.5" aria-hidden="true" />
          {{ label(row, sending) }}
          <span
            v-if="!detailed && row.errors.length"
            class="i-lucide-info size-3.5"
            role="img"
            :aria-label="reason(row)"
            data-testid="flow-meta-hint"
          />
        </span>
        <span class="text-xs text-n-slate-11" data-testid="flow-meta-number">
          {{ row.phoneNumber }}
        </span>
        <Button
          v-if="canRetry && row.state === 'error'"
          type="button"
          xs
          slate
          icon="i-lucide-rotate-cw"
          :label="$t('WHATSAPP_FLOWS.META.RETRY')"
          data-testid="flow-meta-retry"
          @click="emit('retry', row.wabaId)"
        />
      </div>
      <ul
        v-if="detailed && row.errors.length"
        class="grid gap-1 p-0 m-0 text-xs list-none text-n-ruby-11"
        data-testid="flow-meta-errors"
      >
        <li v-for="(error, index) in row.errors" :key="index">
          <code v-if="error.path" class="font-mono">{{ error.path }}</code>
          <span v-if="error.path">: </span>{{ error.message }}
        </li>
      </ul>
    </li>
  </ul>
</template>
