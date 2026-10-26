<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  replyLabel: { type: String, required: true },
  canReply: { type: Boolean, default: true },
});

const emit = defineEmits(['open']);
const { t } = useI18n();
const actions = computed(() => [
  ...(props.canReply
    ? [
        {
          mode: REPLY_EDITOR_MODES.REPLY,
          icon: 'i-lucide-reply',
          label: props.replyLabel,
          shortcut: 'Alt+L',
        },
      ]
    : []),
  {
    mode: REPLY_EDITOR_MODES.NOTE,
    icon: 'i-lucide-lock',
    label: t('CONVERSATION.REPLYBOX.PRIVATE_NOTE'),
    shortcut: 'Alt+P',
  },
]);
</script>

<template>
  <div
    class="flex h-11 items-center gap-1 rounded-xl bg-n-slate-3/90 px-1.5 text-sm text-n-slate-11 shadow-md outline outline-1 -outline-offset-1 outline-n-weak backdrop-blur-xl"
  >
    <button
      v-for="action in actions"
      :key="action.mode"
      type="button"
      class="flex h-11 min-w-0 items-center gap-2 rounded-lg px-2.5 text-n-slate-12 transition-colors hover:bg-n-alpha-2 focus-visible:outline-none focus-visible:bg-n-alpha-2"
      @click="emit('open', action.mode)"
    >
      <Icon :icon="action.icon" class="size-4 shrink-0" />
      <span class="min-w-0 truncate">{{ action.label }}</span>
      <kbd
        class="shrink-0 rounded border border-n-strong px-1 font-sans text-xs tracking-wide text-n-slate-11"
      >
        {{ action.shortcut }}
      </kbd>
    </button>
  </div>
</template>
