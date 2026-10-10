<script setup>
import { computed } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// One WhatsApp-style message bubble for everything ChatHub previews: the send center, the template list
// and the template form. Preview only: it never changes what is sent.
const props = defineProps({
  header: { type: String, default: '' },
  // IMAGE | VIDEO | DOCUMENT | LOCATION: drawn as a placeholder block above the text.
  headerMedia: { type: String, default: '' },
  body: { type: String, default: '' },
  footer: { type: String, default: '' },
  // Strings or { text, type } with type URL | PHONE_NUMBER | QUICK_REPLY | COPY_CODE | FLOW.
  buttons: { type: Array, default: () => [] },
  flow: { type: Boolean, default: false },
});

const MEDIA_ICONS = {
  IMAGE: 'i-lucide-image',
  VIDEO: 'i-lucide-video',
  DOCUMENT: 'i-lucide-file-text',
  LOCATION: 'i-lucide-map-pin',
};
const BUTTON_ICONS = {
  URL: 'i-lucide-external-link',
  PHONE_NUMBER: 'i-lucide-phone',
  QUICK_REPLY: 'i-lucide-reply',
  COPY_CODE: 'i-lucide-copy',
  FLOW: 'i-lucide-workflow',
};

// A blank line is a small gap, not a full empty line, so long messages stay compact.
const bodyLines = computed(() => props.body.split('\n'));
const items = computed(() =>
  props.buttons.map(button => {
    const { text, type } =
      typeof button === 'string' ? { text: button } : button;
    return { text, icon: props.flow ? BUTTON_ICONS.FLOW : BUTTON_ICONS[type] };
  })
);
</script>

<template>
  <div class="min-w-0" data-testid="send-center-preview">
    <div
      class="flex flex-col gap-1 p-3 rounded-xl bg-[#efeae2] dark:bg-[#0b141a]"
    >
      <div
        class="overflow-hidden rounded-lg rounded-tl-none shadow-sm bg-white dark:bg-[#202c33] text-[#111b21] dark:text-[#e9edef]"
      >
        <div
          v-if="headerMedia"
          class="flex items-center justify-center h-32 bg-[#e1e8ec] dark:bg-[#2a3942] text-[#667781] dark:text-[#8696a0]"
          data-testid="bubble-media"
        >
          <Icon
            :icon="MEDIA_ICONS[headerMedia] || MEDIA_ICONS.IMAGE"
            class="size-8"
          />
        </div>
        <div
          class="px-2.5 py-1.5 flex flex-col gap-1.5 text-sm leading-5 break-words"
        >
          <p v-if="header" class="font-semibold whitespace-pre-wrap">
            {{ header }}
          </p>
          <div data-testid="send-center-preview-body">
            <template v-for="(line, index) in bodyLines" :key="index">
              <p v-if="line" class="whitespace-pre-wrap">{{ line }}</p>
              <div v-else class="h-1.5" />
            </template>
          </div>
          <p
            v-if="footer"
            class="text-xs whitespace-pre-wrap text-[#667781] dark:text-[#8696a0]"
          >
            {{ footer }}
          </p>
        </div>
      </div>
      <div
        v-for="(item, index) in items"
        :key="index"
        class="flex items-center justify-center gap-2 px-3 py-1.5 text-sm rounded-lg shadow-sm bg-white dark:bg-[#202c33] text-[#027eb5] dark:text-[#53bdeb]"
        data-testid="bubble-button"
      >
        <Icon v-if="item.icon" :icon="item.icon" class="size-4" />
        {{ item.text }}
      </div>
    </div>
  </div>
</template>
