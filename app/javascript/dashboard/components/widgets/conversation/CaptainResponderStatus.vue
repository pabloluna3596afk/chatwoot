<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useCaptainState } from 'dashboard/composables/useCaptainState';

// Who is answering right now, pinned at the top of the contact panel so it is the first thing seen on opening a conversation.
const store = useStore();
const { isAiAttended, isEscalated, assistant, isWaitingForCustomer } =
  useCaptainState(computed(() => store.getters.getSelectedChat));
</script>

<template>
  <p
    v-if="isAiAttended || isEscalated"
    class="mx-3 mb-3 flex items-center gap-2 rounded-xl bg-n-alpha-1 px-3 py-2.5 text-xs font-medium text-n-slate-12"
    data-testid="responder-status"
  >
    <span
      class="i-woot-captain size-4 shrink-0"
      :class="isAiAttended ? 'text-n-teal-11' : 'text-n-amber-11'"
    />
    <span class="min-w-0">
      <template v-if="isAiAttended">
        {{
          $t('CONVERSATION_SIDEBAR.RESPONDER.ANSWERING', {
            name: assistant?.name || 'Captain',
          })
        }}
        <template v-if="isWaitingForCustomer">
          · {{ $t('CONVERSATION_SIDEBAR.RESPONDER.WAITING_CUSTOMER') }}
        </template>
      </template>
      <template v-else>
        {{ $t('CONVERSATION_SIDEBAR.RESPONDER.ESCALATED') }}
      </template>
    </span>
  </p>
</template>
