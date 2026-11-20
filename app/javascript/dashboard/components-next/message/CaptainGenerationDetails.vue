<script setup>
import { computed, h, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Icon from 'next/icon/Icon.vue';
import Popover from 'next/popover/Popover.vue';
import { useStore } from 'dashboard/composables/store';
import { useMessageContext } from './provider.js';
import CaptainDecisionContent from './CaptainDecisionContent.vue';

const props = defineProps({ messageId: { type: Number, required: true } });
const { t } = useI18n();
const route = useRoute();
const store = useStore();
const { conversationId, orientation } = useMessageContext();
const panelId = `captain-decision-${useId()}`;
const isOpen = ref(false);
const popoverRef = ref(null);
const lookup = computed(() => ({
  accountId: route.params.accountId,
  conversationId: conversationId.value,
  messageId: props.messageId,
}));
const entry = computed(() =>
  store.getters['captainDecisions/getEntry'](lookup.value)
);
const fetchDetails = async () => {
  try {
    return await store.dispatch('captainDecisions/fetch', lookup.value);
  } finally {
    await nextTick();
    const updatePosition = popoverRef.value?.updatePosition;
    if (typeof updatePosition === 'function') updatePosition();
  }
};

// The scoped component keeps the complete trigger between source and lock in
// MessageMeta without coupling that shared row to Captain's request lifecycle.
const Trigger = () =>
  h(
    Popover,
    {
      ref: popoverRef,
      align: orientation.value === 'left' ? 'start' : 'end',
      mobileSheet: true,
      focusContent: true,
      closeOnScroll: false,
      repositionOnScroll: true,
      ariaLabel: t('CONVERSATION.CAPTAIN_DECISION.TITLE'),
      onShow: () => {
        isOpen.value = true;
        fetchDetails();
      },
      onHide: () => {
        isOpen.value = false;
      },
    },
    {
      default: () =>
        h(
          'button',
          {
            type: 'button',
            class:
              'inline-flex size-6 shrink-0 items-center justify-center rounded-md border-0 bg-transparent p-0 text-n-blue-11 hover:bg-n-blue-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9',
            'aria-label': t('CONVERSATION.CAPTAIN_DECISION.OPEN'),
            'aria-expanded': isOpen.value,
            'aria-controls': panelId,
            'aria-haspopup': 'dialog',
          },
          [
            h(Icon, {
              icon: 'i-woot-captain',
              class: 'size-4',
              'aria-hidden': true,
            }),
          ]
        ),
      content: ({ hide, isMobile }) =>
        h(CaptainDecisionContent, {
          id: panelId,
          entry: entry.value,
          mobile: isMobile,
          onRetry: fetchDetails,
          onClose: hide,
        }),
    }
  );
</script>

<template>
  <slot name="meta" :trigger="Trigger"><Trigger /></slot>
</template>
