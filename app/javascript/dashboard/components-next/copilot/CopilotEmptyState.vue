<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Icon from '../icon/Icon.vue';

defineProps({
  hasAssistants: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['useSuggestion']);
const { t } = useI18n();
const route = useRoute();

const promptOptions = computed(() => [
  {
    label: 'CAPTAIN.COPILOT.PROMPTS.OPEN_BY_AGENT.LABEL',
    prompt: 'CAPTAIN.COPILOT.PROMPTS.OPEN_BY_AGENT.CONTENT',
  },
  {
    label: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.LABEL',
    prompt: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.CONTENT',
  },
  {
    label: 'CAPTAIN.COPILOT.PROMPTS.VIP_CONTACTS.LABEL',
    prompt: 'CAPTAIN.COPILOT.PROMPTS.VIP_CONTACTS.CONTENT',
  },
  {
    label: 'CAPTAIN.COPILOT.PROMPTS.PROPOSE_URGENT.LABEL',
    prompt: 'CAPTAIN.COPILOT.PROMPTS.PROPOSE_URGENT.CONTENT',
  },
]);

const handleSuggestion = opt => {
  const message = t(opt.prompt);
  emit(
    'useSuggestion',
    opt.requestType ? { message, requestType: opt.requestType } : message
  );
};
</script>

<template>
  <div class="flex-1 flex flex-col gap-6 px-2">
    <div class="flex flex-col space-y-4 py-4">
      <div class="space-y-1">
        <h3 class="text-base font-medium text-n-slate-12 leading-8">
          {{ $t('CAPTAIN.COPILOT.PANEL_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 leading-6">
          {{ $t('CAPTAIN.COPILOT.KICK_OFF_MESSAGE') }}
        </p>
      </div>
    </div>
    <div v-if="!hasAssistants" class="w-full space-y-2">
      <p class="text-sm text-n-slate-11 leading-6">
        {{ $t('CAPTAIN.ASSISTANTS.NO_ASSISTANTS_AVAILABLE') }}
      </p>
      <router-link
        :to="{
          name: 'captain_assistants_create_index',
          params: {
            accountId: route.params.accountId,
          },
        }"
        class="text-n-slate-11 underline hover:text-n-slate-12"
      >
        {{ $t('CAPTAIN.ASSISTANTS.ADD_NEW') }}
      </router-link>
    </div>
    <div v-else class="w-full space-y-2">
      <span class="text-xs text-n-slate-10 block">
        {{ $t('CAPTAIN.COPILOT.TRY_THESE_PROMPTS') }}
      </span>
      <div class="space-y-1">
        <button
          v-for="prompt in promptOptions"
          :key="prompt.label"
          class="flex min-h-11 w-full items-center justify-between rounded-lg border border-n-weak bg-n-surface-2 px-3 py-2 text-start text-n-slate-12 transition-colors hover:bg-n-alpha-2"
          @click="handleSuggestion(prompt)"
        >
          <span>{{ t(prompt.label) }}</span>
          <Icon icon="i-lucide-chevron-right" />
        </button>
      </div>
    </div>
  </div>
</template>
