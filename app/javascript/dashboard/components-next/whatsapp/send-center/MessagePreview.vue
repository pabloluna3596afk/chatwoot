<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';
defineProps({
  header: { type: String, default: '' },
  body: { type: String, default: '' },
  footer: { type: String, default: '' },
  buttons: { type: Array, default: () => [] },
  flow: { type: Boolean, default: false },
});
</script>

<template>
  <div class="min-w-0 p-4 rounded-xl bg-n-solid-2">
    <p class="mb-3 text-xs text-n-slate-11">
      {{ $t('WHATSAPP_TEMPLATES.SEND_CENTER.PREVIEW') }}
    </p>
    <div
      class="overflow-hidden rounded-lg border border-n-weak shadow-sm bg-n-solid-1 text-n-slate-12"
      data-testid="send-center-preview"
    >
      <div class="p-3 flex flex-col gap-3 text-sm leading-6 break-words">
        <div v-if="header">
          <p class="mb-1 text-xs text-n-slate-10">
            {{ $t('WHATSAPP_TEMPLATES.SEND_CENTER.HEADER') }}
          </p>
          <p class="font-semibold whitespace-pre-wrap">{{ header }}</p>
        </div>
        <div>
          <p class="mb-1 text-xs text-n-slate-10">
            {{ $t('WHATSAPP_TEMPLATES.SEND_CENTER.BODY') }}
          </p>
          <p class="whitespace-pre-wrap">{{ body }}</p>
        </div>
        <div v-if="footer">
          <p class="mb-1 text-xs text-n-slate-10">
            {{ $t('WHATSAPP_TEMPLATES.SEND_CENTER.FOOTER') }}
          </p>
          <p class="text-xs whitespace-pre-wrap text-n-slate-11">
            {{ footer }}
          </p>
        </div>
      </div>
      <div
        v-for="(label, index) in buttons"
        :key="index"
        class="flex items-center justify-center gap-2 p-3 text-sm border-t border-n-weak text-n-teal-11"
      >
        <Icon v-if="flow" icon="i-lucide-workflow" class="size-4" />
        {{ label }}
      </div>
    </div>
  </div>
</template>
