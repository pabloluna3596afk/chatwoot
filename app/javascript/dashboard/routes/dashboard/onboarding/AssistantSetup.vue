<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import OnboardingAPI from 'dashboard/api/onboarding';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import CaptainInboxes from 'dashboard/api/captain/inboxes';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import AuthSplitLayout from 'v3/components/Auth/AuthSplitLayout.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const CURRENT_STEP = 4;
const TOTAL_STEPS = 5;
const EXAMPLE_IDS = [1, 2, 3];
const INPUT_CLASS =
  'reset-base m-0 w-full border-0 bg-n-solid-1 px-5 py-4 text-base text-n-slate-12 outline outline-1 outline-n-weak placeholder:text-n-slate-10 focus:outline-n-brand dark:bg-n-solid-3';
const BUTTON_CLASS =
  'flex min-h-14 w-full items-center justify-center gap-2 rounded-full bg-n-slate-12 px-6 py-3 text-base font-medium text-n-solid-1 hover:enabled:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60';
const { t, tm, rt } = useI18n();
const router = useRouter();
const store = useStore();
const { currentAccount, accountId, finishOnboarding } = useAccount();
const inboxes = useMapGetter('inboxes/getInboxes');
const assistant = ref(null);
const name = ref('');
const goal = ref('');
const tone = ref('friendly');
const loading = ref(true);
const loadError = ref(false);
const saving = ref(false);
const finishing = ref(false);
const editing = ref(true);
const errorMessage = ref('');
const messages = ref([]);
const question = ref('');
const sending = ref(false);
const chatError = ref('');
const pendingQuestion = ref('');
const businessType = computed(
  () => currentAccount.value?.custom_attributes?.business_type || 'other'
);
const toneOptions = computed(() => [
  { value: 'friendly', label: t('ONBOARDING_ASSISTANT.TONES.friendly') },
  {
    value: 'professional',
    label: t('ONBOARDING_ASSISTANT.TONES.professional'),
  },
  { value: 'brief', label: t('ONBOARDING_ASSISTANT.TONES.brief') },
]);
const examples = computed(() => {
  const messagesByType = tm('ONBOARDING_ASSISTANT.EXAMPLES');
  return EXAMPLE_IDS.map(id => rt(messagesByType[businessType.value][id]));
});
const whatsappInbox = computed(() =>
  inboxes.value.find(inbox => inbox.channel_type === INBOX_TYPES.WHATSAPP)
);
const busy = computed(() => saving.value || finishing.value || sending.value);
const valid = computed(() => name.value.trim() && goal.value.trim());
const active = computed(() => Boolean(assistant.value?.inbox_ids?.length));

const refreshAssistant = async () => {
  const { data } = await OnboardingAPI.getAssistant();
  assistant.value = data.assistant;
  return data.assistant;
};

const initialize = async () => {
  loading.value = true;
  loadError.value = false;
  try {
    // Wait for the account fetch before deriving the business name and examples.
    const [loadedAccount, loadedInboxes] = await Promise.all([
      store.dispatch('accounts/get'),
      store.dispatch('inboxes/get'),
      refreshAssistant(),
    ]);
    if (!loadedAccount || !loadedInboxes) {
      loadError.value = true;
      return;
    }
    name.value =
      assistant.value?.name ||
      t('ONBOARDING_ASSISTANT.DEFAULT_NAME', {
        business: currentAccount.value.name,
      });
    goal.value = assistant.value?.config.onboarding?.goal || '';
    tone.value = assistant.value?.config.onboarding?.tone || 'friendly';
    editing.value = !assistant.value;
  } catch {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(initialize);

const createAndTest = async () => {
  if (!valid.value || busy.value) return;
  saving.value = true;
  errorMessage.value = '';
  try {
    const { data } = await OnboardingAPI.saveAssistant({
      name: name.value.trim(),
      goal: goal.value.trim(),
      tone: tone.value,
    });
    assistant.value = data.assistant;
    editing.value = false;
    messages.value = [];
    chatError.value = '';
    pendingQuestion.value = '';
  } catch (error) {
    const data = error.response?.data;
    errorMessage.value =
      data?.error_code === 'assistant_limit'
        ? t('ONBOARDING_ASSISTANT.LIMIT_ERROR', { limit: data.limit })
        : t('ONBOARDING_ASSISTANT.CREATE_ERROR');
  } finally {
    saving.value = false;
  }
};

const keepEditing = () => {
  editing.value = true;
  errorMessage.value = '';
};

const sendQuestion = async (retry = false) => {
  const content = retry ? pendingQuestion.value : question.value.trim();
  if (!content || busy.value) return;
  sending.value = true;
  chatError.value = '';
  pendingQuestion.value = content;
  if (!retry) {
    messages.value.push({ role: 'user', content });
    question.value = '';
  }
  try {
    const latest = await refreshAssistant();
    if (latest.paused_reason) {
      chatError.value = t('ONBOARDING_ASSISTANT.AI_UNAVAILABLE');
      return;
    }
    const { data } = await CaptainAssistant.playground({
      assistantId: assistant.value.id,
      messageContent: content,
      messageHistory: [...messages.value],
    });
    if (data.error || !data.response) {
      chatError.value = t('ONBOARDING_ASSISTANT.CHAT_ERROR');
      return;
    }
    messages.value.push({
      role: 'assistant',
      content: data.response,
      ...(data.agent_name ? { agent_name: data.agent_name } : {}),
    });
    pendingQuestion.value = '';
  } catch {
    chatError.value = t('ONBOARDING_ASSISTANT.CHAT_ERROR');
  } finally {
    sending.value = false;
  }
};

const complete = async activate => {
  if (busy.value || (activate && !whatsappInbox.value)) return;
  finishing.value = true;
  errorMessage.value = '';
  try {
    if (activate && !active.value) {
      // Reconcile after a lost response or a failed completion before retrying.
      await refreshAssistant();
      if (!active.value) {
        await CaptainInboxes.create({
          assistantId: assistant.value.id,
          inboxId: whatsappInbox.value.id,
        });
        assistant.value.inbox_ids = [whatsappInbox.value.id];
      }
    }
    await finishOnboarding({ onboarding_step: 'assistant' });
    await store.dispatch('setUser');
    await router.push({ name: 'home', params: { accountId: accountId.value } });
  } catch {
    errorMessage.value = activate
      ? t('ONBOARDING_ASSISTANT.ACTIVATE_ERROR')
      : t('ONBOARDING_ASSISTANT.COMPLETION_ERROR');
  } finally {
    finishing.value = false;
  }
};
</script>

<template>
  <AuthSplitLayout
    :title="t('ONBOARDING_ASSISTANT.MARKETING.TITLE')"
    :subtitle="t('ONBOARDING_ASSISTANT.MARKETING.SUBTITLE')"
    scrollable
  >
    <header class="mb-6">
      <p class="mb-2 text-sm font-medium text-n-slate-11">
        {{
          t('ONBOARDING_NEXT.STEP', {
            current: CURRENT_STEP,
            total: TOTAL_STEPS,
          })
        }}
      </p>
      <div
        role="progressbar"
        :aria-label="t('ONBOARDING_NEXT.PROGRESS')"
        :aria-valuenow="CURRENT_STEP"
        :aria-valuemin="0"
        :aria-valuemax="TOTAL_STEPS"
        class="mb-6 flex gap-1.5"
      >
        <span
          v-for="step in TOTAL_STEPS"
          :key="step"
          class="h-1 flex-1 rounded-full"
          :class="step <= CURRENT_STEP ? 'bg-n-slate-12' : 'bg-n-slate-4'"
        />
      </div>
      <h2 class="text-3xl font-bold tracking-tight text-n-slate-12 xl:text-4xl">
        {{ t('ONBOARDING_ASSISTANT.TITLE') }}
      </h2>
      <p class="mt-3 mb-0 text-base leading-7 text-n-slate-11">
        {{ t('ONBOARDING_ASSISTANT.SUBTITLE') }}
      </p>
    </header>
    <Spinner v-if="loading" class="mx-auto" :size="32" />
    <div v-else-if="loadError" class="space-y-4">
      <p role="alert" class="text-sm text-n-ruby-11">
        {{ t('ONBOARDING_ASSISTANT.LOAD_ERROR') }}
      </p>
      <button type="button" :class="BUTTON_CLASS" @click="initialize">
        {{ t('ONBOARDING_ASSISTANT.RETRY') }}
      </button>
    </div>
    <form
      v-else-if="editing"
      id="assistant-form"
      class="space-y-5"
      @submit.prevent="createAndTest"
    >
      <div class="space-y-2">
        <label for="assistant-name" class="text-sm font-medium text-n-slate-12">
          {{ t('ONBOARDING_ASSISTANT.NAME') }}
        </label>
        <input
          id="assistant-name"
          v-model="name"
          required
          maxlength="120"
          :disabled="busy"
          class="rounded-full"
          :class="[INPUT_CLASS]"
        />
      </div>
      <div class="space-y-2">
        <label for="assistant-goal" class="text-sm font-medium text-n-slate-12">
          {{ t('ONBOARDING_ASSISTANT.GOAL') }}
        </label>
        <textarea
          id="assistant-goal"
          v-model="goal"
          required
          rows="4"
          maxlength="2000"
          :disabled="busy"
          class="resize-y rounded-2xl"
          :class="[INPUT_CLASS]"
        />
        <p class="mb-2 text-xs text-n-slate-11">
          {{ t('ONBOARDING_ASSISTANT.EXAMPLES_LABEL') }}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="example in examples"
            :key="example"
            type="button"
            class="rounded-2xl bg-n-slate-3 px-3 py-2 text-start text-xs leading-5 text-n-slate-11 hover:bg-n-slate-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
            :disabled="busy"
            data-testid="example"
            @click="goal = example"
          >
            {{ example }}
          </button>
        </div>
      </div>
      <fieldset>
        <legend class="mb-2 text-sm font-medium text-n-slate-12">
          {{ t('ONBOARDING_ASSISTANT.TONE') }}
        </legend>
        <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <label
            v-for="option in toneOptions"
            :key="option.value"
            class="relative flex cursor-pointer items-center justify-center gap-2 rounded-2xl px-4 py-4 text-sm text-n-slate-12 outline outline-1 focus-within:outline-2 focus-within:outline-n-brand"
            :class="
              tone === option.value
                ? 'bg-n-slate-3 outline-n-slate-12'
                : 'outline-n-weak'
            "
          >
            <input
              v-model="tone"
              type="radio"
              name="assistant-tone"
              :value="option.value"
              :disabled="busy"
              class="sr-only"
            />
            {{ option.label }}
          </label>
        </div>
      </fieldset>
    </form>
    <section
      v-else
      class="space-y-4"
      :aria-label="t('ONBOARDING_ASSISTANT.CHAT')"
    >
      <div class="rounded-2xl bg-n-slate-3 p-4">
        <p class="mb-1 break-words font-medium text-n-slate-12">
          {{ assistant.name }}
        </p>
        <p class="mb-0 text-sm leading-6 text-n-slate-11">
          {{
            active
              ? t('ONBOARDING_ASSISTANT.ACTIVE')
              : t('ONBOARDING_ASSISTANT.DRAFT')
          }}
        </p>
      </div>
      <h3 class="text-base font-semibold text-n-slate-12">
        {{ t('ONBOARDING_ASSISTANT.CHAT') }}
      </h3>
      <p
        v-if="assistant.paused_reason"
        role="status"
        class="text-sm text-n-slate-11"
      >
        {{ t('ONBOARDING_ASSISTANT.AI_UNAVAILABLE') }}
      </p>
      <button
        v-if="assistant.paused_reason && !chatError"
        type="button"
        class="rounded-full px-3 py-2 text-sm font-medium text-n-slate-12 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
        :disabled="busy"
        data-testid="ai-retry"
        @click="initialize"
      >
        {{ t('ONBOARDING_ASSISTANT.RETRY') }}
      </button>
      <div
        role="log"
        aria-live="polite"
        class="max-h-80 space-y-3 overflow-y-auto rounded-2xl bg-n-alpha-1 p-4"
      >
        <p
          v-if="!messages.length"
          class="mb-0 text-sm leading-6 text-n-slate-11"
        >
          {{ t('ONBOARDING_ASSISTANT.CHAT_EMPTY') }}
        </p>
        <div
          v-for="(message, index) in messages"
          :key="index"
          class="rounded-2xl p-3"
          :class="
            message.role === 'user' ? 'ms-5 bg-n-slate-3' : 'me-5 bg-n-solid-1'
          "
        >
          <p class="mb-1 text-xs font-medium text-n-slate-11">
            {{
              message.role === 'user'
                ? t('ONBOARDING_ASSISTANT.YOU')
                : assistant.name
            }}
          </p>
          <p
            class="mb-0 whitespace-pre-wrap break-words text-sm leading-6 text-n-slate-12"
          >
            {{ message.content }}
          </p>
        </div>
        <p v-if="sending" role="status" class="mb-0 text-sm text-n-slate-11">
          {{ t('ONBOARDING_ASSISTANT.THINKING') }}
        </p>
      </div>
      <div
        v-if="chatError"
        role="alert"
        class="space-y-2 text-sm text-n-ruby-11"
      >
        <p class="mb-0">{{ chatError }}</p>
        <button
          type="button"
          class="rounded-full px-3 py-2 font-medium underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
          :disabled="busy"
          @click="sendQuestion(true)"
        >
          {{ t('ONBOARDING_ASSISTANT.RETRY') }}
        </button>
      </div>
      <form class="space-y-3" @submit.prevent="sendQuestion()">
        <label
          for="assistant-question"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('ONBOARDING_ASSISTANT.QUESTION') }}
        </label>
        <input
          id="assistant-question"
          v-model="question"
          class="rounded-full"
          :class="[INPUT_CLASS]"
          :disabled="busy || Boolean(chatError)"
        />
        <button
          type="submit"
          :class="BUTTON_CLASS"
          :disabled="busy || !question.trim() || Boolean(chatError)"
        >
          {{ t('ONBOARDING_ASSISTANT.SEND') }}
        </button>
      </form>
    </section>
    <template #footer>
      <p v-if="errorMessage" role="alert" class="mb-3 text-sm text-n-ruby-11">
        {{ errorMessage }}
      </p>
      <template v-if="!loading && !loadError">
        <button
          v-if="editing"
          type="submit"
          form="assistant-form"
          :class="BUTTON_CLASS"
          :disabled="busy || !valid"
          :aria-busy="saving"
          data-testid="create"
        >
          <Spinner v-if="saving" :size="20" aria-hidden="true" />
          {{
            saving
              ? t('ONBOARDING_ASSISTANT.CREATING')
              : t('ONBOARDING_ASSISTANT.CREATE')
          }}
        </button>
        <template v-else>
          <button
            type="button"
            :class="BUTTON_CLASS"
            :disabled="busy || !whatsappInbox"
            :aria-busy="finishing"
            data-testid="activate"
            @click="complete(true)"
          >
            <Spinner v-if="finishing" :size="20" aria-hidden="true" />
            {{
              active
                ? t('ONBOARDING_ASSISTANT.CONTINUE')
                : t('ONBOARDING_ASSISTANT.ACTIVATE')
            }}
          </button>
          <p
            v-if="!whatsappInbox"
            class="mt-3 mb-0 text-center text-sm text-n-slate-11"
          >
            {{ t('ONBOARDING_ASSISTANT.CONNECT_REQUIRED') }}
            <RouterLink
              :to="{ name: 'onboarding_inbox_setup', params: { accountId } }"
              class="rounded font-medium text-n-slate-12 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            >
              {{ t('ONBOARDING_ASSISTANT.BACK_WHATSAPP') }}
            </RouterLink>
          </p>
          <button
            v-if="!active"
            type="button"
            class="mt-4 w-full rounded-full px-4 py-2 text-sm text-n-slate-12 underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
            :disabled="busy"
            data-testid="edit"
            @click="keepEditing"
          >
            {{ t('ONBOARDING_ASSISTANT.EDIT') }}
          </button>
        </template>
      </template>
      <button
        type="button"
        class="mt-4 w-full rounded-full px-4 py-2 text-sm text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
        :disabled="loading || busy"
        data-testid="skip"
        @click="complete(false)"
      >
        {{ t('ONBOARDING_ASSISTANT.SKIP') }}
      </button>
    </template>
  </AuthSplitLayout>
</template>
