<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from './provider.js';
import { hasOneDayPassed } from 'shared/helpers/timeHelper';
import { ORIENTATION, MESSAGE_STATUS } from './constants';
import { parseExternalError } from './helpers/messageError';

const props = defineProps({
  error: { type: String, required: true },
  channelType: { type: String, default: '' },
});

const emit = defineEmits(['retry']);

const { orientation, status, createdAt, content, attachments } =
  useMessageContext();

const { t, te } = useI18n();
const tooltipError = computed(() => {
  const { code, key } = parseExternalError(props.error, props.channelType);
  // The provider code selects one of the channel-specific translation keys.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  const hasTranslation = code && te(key);
  if (!hasTranslation) return props.error;

  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return `${t(key)} (${code})`;
});

const canRetry = computed(() => {
  const hasContent = content.value !== null;
  const hasAttachments = attachments.value && attachments.value.length > 0;
  return !hasOneDayPassed(createdAt.value) && (hasContent || hasAttachments);
});
</script>

<template>
  <div class="text-xs text-n-ruby-11 flex items-center gap-1.5">
    <span>{{ t('CHAT_LIST.FAILED_TO_SEND') }}</span>
    <div class="relative group">
      <div
        class="bg-n-alpha-2 rounded-md size-5 grid place-content-center cursor-pointer"
      >
        <Icon
          icon="i-lucide-alert-triangle"
          class="text-n-ruby-11 size-[14px]"
        />
      </div>
      <div
        class="absolute bg-n-alpha-3 px-4 py-3 border rounded-xl border-n-strong text-n-slate-12 bottom-6 w-64 max-w-xs text-xs backdrop-blur-[100px] shadow-[0px_0px_24px_0px_rgba(0,0,0,0.12)] opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all break-words"
        :class="{
          'ltr:left-0 rtl:right-0': orientation === ORIENTATION.LEFT,
          'ltr:right-0 rtl:left-0': orientation === ORIENTATION.RIGHT,
        }"
      >
        {{ tooltipError }}
      </div>
    </div>
    <button
      v-if="canRetry"
      type="button"
      :disabled="status !== MESSAGE_STATUS.FAILED"
      class="bg-n-alpha-2 rounded-md size-5 grid place-content-center cursor-pointer"
      @click="emit('retry')"
    >
      <Icon icon="i-lucide-refresh-ccw" class="text-n-ruby-11 size-[14px]" />
    </button>
  </div>
</template>
