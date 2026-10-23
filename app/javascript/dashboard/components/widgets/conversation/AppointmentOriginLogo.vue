<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import Icon from 'next/icon/Icon.vue';
import Logo from 'next/icon/Logo.vue';
import googleLogo from 'dashboard/assets/images/integrations/google.svg';

// Where an appointment was born: the channel of its conversation, the CRM, or the external calendar.
const props = defineProps({
  origin: {
    type: Object,
    default: null,
  },
  size: {
    type: Number,
    default: 16,
  },
});

const { t } = useI18n();

const type = computed(() => props.origin?.type);
const label = computed(() => {
  if (type.value === 'conversation') {
    return props.origin.inbox_name
      ? t('CONVERSATION_SIDEBAR.CALENDAR.ORIGIN.CONVERSATION_INBOX', {
          inbox: props.origin.inbox_name,
        })
      : t('CONVERSATION_SIDEBAR.CALENDAR.ORIGIN.CONVERSATION');
  }
  if (type.value === 'crm')
    return t('CONVERSATION_SIDEBAR.CALENDAR.ORIGIN.CRM');
  return t('CONVERSATION_SIDEBAR.CALENDAR.ORIGIN.GOOGLE');
});
const byCaptain = computed(() => Boolean(props.origin?.by_captain));
const sizeStyle = computed(() => ({
  width: `${props.size}px`,
  height: `${props.size}px`,
}));
</script>

<template>
  <span v-if="type" class="inline-flex shrink-0 items-center gap-1">
    <span
      v-tooltip.top="label"
      class="inline-flex shrink-0 items-center justify-center"
      :style="sizeStyle"
      :aria-label="label"
      :data-testid="`appointment-origin-${type}`"
    >
      <ChannelIcon
        v-if="type === 'conversation' && origin.channel_type"
        :inbox="{ channel_type: origin.channel_type }"
        use-brand-icon
        class="size-full"
      />
      <Logo v-else-if="type === 'crm'" class="size-full object-contain" />
      <Icon
        v-else-if="type === 'conversation'"
        icon="i-lucide-message-circle"
        class="size-full text-n-slate-11"
      />
      <img v-else :src="googleLogo" alt="" class="size-full rounded-sm" />
    </span>
    <span
      v-if="byCaptain"
      v-tooltip.top="t('CONVERSATION_SIDEBAR.CALENDAR.ORIGIN.CAPTAIN')"
      class="i-woot-captain shrink-0 text-n-teal-11"
      :style="sizeStyle"
      :aria-label="t('CONVERSATION_SIDEBAR.CALENDAR.ORIGIN.CAPTAIN')"
      data-testid="appointment-origin-captain"
    />
  </span>
</template>
