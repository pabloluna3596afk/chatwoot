<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  inboxes: { type: Array, default: () => [] },
});

const { t } = useI18n();
</script>

<template>
  <section class="flex flex-col gap-3 rounded-xl border border-n-weak p-4">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.READINESS.TITLE') }}
    </h3>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.READINESS.SAVED_HELP') }}
    </p>
    <p v-if="!inboxes.length" class="mb-0 text-sm text-n-slate-11">
      {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.READINESS.NO_INBOXES') }}
    </p>
    <div
      v-for="inbox in inboxes"
      :key="inbox.inbox_id"
      :data-testid="`reminder-readiness-${inbox.inbox_id}`"
      class="flex min-w-0 flex-col gap-1 rounded-lg bg-n-alpha-1 p-3"
    >
      <span class="break-words text-sm font-medium text-n-slate-12">
        {{ inbox.inbox_name }}
      </span>
      <p class="mb-0 text-sm text-n-slate-12">
        {{
          t(
            `CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.READINESS.STATUS.${inbox.status}`
          )
        }}
      </p>
      <p
        v-if="inbox.missing.length"
        class="mb-0 break-words text-xs text-n-slate-11"
      >
        {{
          t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.READINESS.MISSING', {
            variables: inbox.missing.join(', '),
          })
        }}
      </p>
    </div>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('CAPTAIN.ASSISTANTS.FORM.APPOINTMENTS.READINESS.DELIVERY_HELP') }}
    </p>
    <router-link
      :to="{ name: 'captain_assistants_settings_paid_messages_index' }"
      class="w-fit text-sm font-medium text-n-brand hover:underline"
    >
      {{ t('CAPTAIN.ASSISTANTS.SETTINGS.PAID_MESSAGES.TITLE') }}
    </router-link>
  </section>
</template>
