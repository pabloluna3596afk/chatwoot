<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  title: { type: String, required: true },
  message: { type: String, default: '' },
  retryLabel: { type: String, default: '' },
  retrying: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});
defineEmits(['retry']);
const { t } = useI18n();
const resolvedRetryLabel = computed(
  () => props.retryLabel || t('COMPONENTS.LOAD_ERROR_NOTICE.RETRY')
);
</script>

<template>
  <!-- First-load failures replace content; refresh failures keep prior data visible. -->
  <section
    role="alert"
    class="flex gap-3"
    :class="
      compact
        ? 'items-center rounded-lg bg-n-ruby-3 p-3 text-n-ruby-11'
        : 'flex-col items-center justify-center p-8 text-center text-n-slate-12'
    "
  >
    <Icon icon="i-lucide-circle-alert" class="size-5 shrink-0" />
    <div class="min-w-0 flex-1" :class="{ 'text-center': !compact }">
      <h2 class="text-sm font-medium">{{ title }}</h2>
      <p v-if="message" class="mt-1 text-sm text-n-slate-11">{{ message }}</p>
    </div>
    <Button
      faded
      slate
      :label="resolvedRetryLabel"
      :disabled="retrying"
      :aria-busy="retrying"
      @click="$emit('retry')"
    />
  </section>
</template>
