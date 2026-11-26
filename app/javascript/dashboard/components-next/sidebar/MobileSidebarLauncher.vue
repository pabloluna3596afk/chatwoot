<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import { useActivityIndicator } from 'dashboard/components-next/BackgroundTasks/useActivityIndicator';

defineProps({
  isMobileSidebarOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle']);
const { visible: activityVisible, statusTone } = useActivityIndicator();

const route = useRoute();

const isConversationRoute = computed(() => {
  const CONVERSATION_ROUTES = [
    'inbox_conversation',
    'conversation_through_inbox',
    'conversations_through_label',
    'team_conversations_through_label',
    'conversations_through_folders',
    'conversation_through_mentions',
    'conversation_through_unattended',
    'conversation_through_ai',
    'conversation_through_participating',
    'inbox_view_conversation',
  ];
  return CONVERSATION_ROUTES.includes(route.name);
});

const toggleSidebar = () => {
  emit('toggle');
};
</script>

<template>
  <div
    v-if="!isConversationRoute"
    id="mobile-sidebar-launcher"
    class="fixed bottom-4 ltr:left-4 rtl:right-4 z-40 transition-transform duration-200 ease-out block md:hidden"
    :class="[
      {
        'ltr:translate-x-48 rtl:-translate-x-48': isMobileSidebarOpen,
      },
    ]"
  >
    <ButtonGroup
      class="rounded-full bg-n-alpha-2 backdrop-blur-lg p-1 shadow hover:shadow-md"
    >
      <span class="relative flex">
        <Button
          icon="i-lucide-menu"
          no-animation
          class="!rounded-full !bg-n-solid-3 dark:!bg-n-alpha-2 !text-n-slate-12 text-xl transition-all duration-200 ease-out hover:brightness-110"
          lg
          @click="toggleSidebar"
        />
        <span
          v-if="activityVisible"
          class="absolute end-1 top-1 size-[9px] rounded-full border-2 border-n-background"
          :class="{
            'bg-n-brand': statusTone === 'active',
            'bg-n-slate-10': statusTone === 'waiting',
            'bg-n-teal-11': statusTone === 'success',
            'bg-n-ruby-11': statusTone === 'error',
          }"
          aria-hidden="true"
        />
      </span>
    </ButtonGroup>
  </div>
  <template v-else />
</template>
