<script setup>
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

defineProps({ content: { type: String, default: '' } });
const { formatMessage } = useMessageFormatter();
</script>

<template>
  <div
    v-dompurify-html="formatMessage(content)"
    class="min-w-0 max-w-full text-sm text-n-slate-12 prose prose-bubble !max-w-none [overflow-wrap:anywhere] prose-a:text-n-brand prose-pre:max-w-full prose-pre:overflow-x-auto prose-code:bg-n-alpha-black2 prose-code:text-n-slate-11"
  />
</template>
