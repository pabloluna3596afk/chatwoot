<script setup>
// "Publicar": first asks for confirmation (the flow becomes available in every inbox of ChatHub and is sent to Meta on
// every WhatsApp Cloud account of this account), then shows the progress and the result per WABA, with Meta's errors.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import FlowPublicationBadges from './FlowPublicationBadges.vue';

const props = defineProps({
  rows: { type: Array, default: () => [] },
  // Meta is being asked right now (the request or the polling that follows it).
  busy: { type: Boolean, default: false },
});

const emit = defineEmits(['publish', 'retry']);
const { t } = useI18n();

const dialog = ref(null);
const started = ref(false);

const hasErrors = computed(() => props.rows.some(row => row.state === 'error'));
const title = computed(() =>
  started.value
    ? t('WHATSAPP_FLOWS.META.PUBLISH_PROGRESS_TITLE')
    : t('WHATSAPP_FLOWS.META.PUBLISH_TITLE')
);

const open = () => {
  started.value = false;
  dialog.value?.open();
};
const close = () => dialog.value?.close();
const confirm = () => {
  started.value = true;
  emit('publish');
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialog"
    width="lg"
    :title="title"
    :description="started ? '' : $t('WHATSAPP_FLOWS.META.PUBLISH_BODY')"
    data-testid="flow-publish-dialog"
  >
    <div v-if="!started" class="grid gap-3" data-testid="flow-publish-confirm">
      <ul class="grid gap-1 p-0 m-0 text-sm list-none text-n-slate-11">
        <li>{{ $t('WHATSAPP_FLOWS.META.PUBLISH_POINT_INBOXES') }}</li>
        <li>{{ $t('WHATSAPP_FLOWS.META.PUBLISH_POINT_META') }}</li>
        <li>{{ $t('WHATSAPP_FLOWS.META.PUBLISH_POINT_VERSION') }}</li>
      </ul>
      <FlowPublicationBadges :rows="rows" />
    </div>
    <div v-else class="grid gap-3" data-testid="flow-publish-progress">
      <p
        v-if="busy"
        class="flex items-center gap-2 m-0 text-sm text-n-slate-11"
        role="status"
      >
        <span class="i-lucide-loader-circle size-4 animate-spin" />
        {{ $t('WHATSAPP_FLOWS.META.PUBLISH_WORKING') }}
      </p>
      <p
        v-else-if="hasErrors"
        class="m-0 text-sm text-n-ruby-11"
        role="status"
        data-testid="flow-publish-failed"
      >
        {{ $t('WHATSAPP_FLOWS.META.PUBLISH_FAILED') }}
      </p>
      <p
        v-else
        class="m-0 text-sm text-n-teal-11"
        role="status"
        data-testid="flow-publish-done"
      >
        {{ $t('WHATSAPP_FLOWS.META.PUBLISH_DONE') }}
      </p>
      <FlowPublicationBadges
        :rows="rows"
        detailed
        :sending="busy"
        :can-retry="!busy"
        @retry="emit('retry', $event)"
      />
    </div>
    <template #footer>
      <div class="flex items-center justify-end gap-3">
        <Button
          type="button"
          slate
          faded
          :label="
            started
              ? $t('WHATSAPP_FLOWS.META.CLOSE')
              : $t('WHATSAPP_FLOWS.META.CANCEL')
          "
          data-testid="flow-publish-close"
          @click="close"
        />
        <Button
          v-if="!started"
          type="button"
          icon="i-lucide-send"
          :label="$t('WHATSAPP_FLOWS.META.PUBLISH_CONFIRM')"
          data-testid="flow-publish-confirm-button"
          @click="confirm"
        />
      </div>
    </template>
  </Dialog>
</template>
