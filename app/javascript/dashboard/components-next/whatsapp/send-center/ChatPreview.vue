<script setup>
import { ref } from 'vue';
import { useScroll, useResizeObserver } from '@vueuse/core';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MessagePreview from '../WhatsAppBubble.vue';

defineProps({
  fieldHint: { type: String, default: '' },
  messages: { type: Array, default: () => [] },
  header: { type: String, default: '' },
  headerMedia: { type: String, default: '' },
  body: { type: String, default: '' },
  footer: { type: String, default: '' },
  buttons: { type: Array, default: () => [] },
});
const PREVIEW_TIME = '12:30';
const DELIVERY_MARKS = '✓✓';
const viewport = ref(null);
const message = ref(null);
const { arrivedState, measure } = useScroll(viewport);
useResizeObserver([viewport, message], measure);
</script>

<template>
  <div
    class="relative flex min-h-0 flex-1 flex-col motion-safe:animate-[fade-in-up_150ms_ease-out]"
    data-template-preview
  >
    <div
      ref="viewport"
      class="flex min-h-0 flex-1 flex-col overflow-y-auto overscroll-contain rounded-xl bg-[#efeae2] p-3 pb-12 dark:bg-[#0b141a]"
      data-testid="chat-preview-scroll"
    >
      <div ref="message" class="my-auto w-full shrink-0">
        <MessagePreview
          class="mx-auto w-full max-w-[22.5rem] [&>div]:p-0 [&>div>div]:w-full [&>div>div]:overflow-visible [&_[data-testid=bubble-media]]:w-full [&_[data-testid=bubble-media]]:object-cover [&_[data-testid=bubble-media]]:aspect-video [&_[data-testid=bubble-media]]:h-auto [&_[data-testid=bubble-media]]:max-h-36 [&_[data-template-field]]:scroll-mt-16"
          :header="header"
          :body="body"
          :buttons="buttons"
          :header-media="headerMedia"
        >
          <template #header>
            <slot name="header">
              <p v-if="header" class="font-semibold whitespace-pre-wrap">
                {{ header }}
              </p>
            </slot>
          </template>
          <template #body>
            <slot>
              <p class="whitespace-pre-wrap">{{ body }}</p>
            </slot>
            <p
              v-if="footer"
              class="mt-2 whitespace-pre-wrap text-xs text-n-slate-11"
            >
              {{ footer }}
            </p>
            <p
              aria-hidden="true"
              class="mt-1 text-end text-xxs text-n-slate-11"
            >
              {{ PREVIEW_TIME }}
              <span class="text-n-blue-11">{{ DELIVERY_MARKS }}</span>
            </p>
          </template>
        </MessagePreview>
        <p
          class="mx-auto mt-2 h-10 w-full max-w-[22.5rem] overflow-y-auto text-xs text-n-slate-11"
          aria-live="polite"
          aria-atomic="true"
          data-testid="preview-field-hint"
        >
          {{ fieldHint }}
        </p>
        <p
          v-for="messageText in messages"
          :key="messageText"
          class="mx-auto mt-2 flex w-full max-w-[22.5rem] items-start gap-1 text-xs text-n-slate-11"
          role="status"
          data-testid="preview-help"
        >
          <Icon icon="i-lucide-info" class="mt-0.5 size-3 shrink-0" />
          {{ messageText }}
        </p>
      </div>
    </div>
    <div
      v-if="!arrivedState.top"
      class="pointer-events-none absolute inset-x-0 top-0 h-3 rounded-t-xl bg-gradient-to-b from-n-slate-12/10 to-transparent"
      data-testid="chat-preview-shadow-top"
    />
    <div
      v-if="!arrivedState.bottom"
      class="pointer-events-none absolute inset-x-0 bottom-0 h-3 rounded-b-xl bg-gradient-to-t from-n-slate-12/10 to-transparent"
      data-testid="chat-preview-shadow-bottom"
    />
  </div>
</template>
