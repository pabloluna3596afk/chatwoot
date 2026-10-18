<script setup>
import { computed, onMounted, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import OnboardingAPI from 'dashboard/api/onboarding';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import {
  PLAYGROUND_MESSAGE_LIMIT,
  usePlaygroundUsage,
} from 'dashboard/components-next/captain/assistant/usePlaygroundUsage';
import CaptainInboxes from 'dashboard/api/captain/inboxes';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import AuthSplitLayout from 'v3/components/Auth/AuthSplitLayout.vue';
import AssistantAvatar from './AssistantAvatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AuthStepHeader from 'v3/components/Auth/AuthStepHeader.vue';
import AuthField from 'v3/components/Auth/AuthField.vue';
import AuthButton from 'v3/components/Auth/AuthButton.vue';
import AuthChoiceCard from 'v3/components/Auth/AuthChoiceCard.vue';
import AuthFeedback from 'v3/components/Auth/AuthFeedback.vue';
import {
  AUTH_FIELD_CLASS,
  AUTH_LINK_CLASS,
} from 'v3/components/Auth/authStyles';

const CURRENT_STEP = 4;
const EXAMPLE_IDS = [1, 2, 3];
const GOAL_MAX_LENGTH = 2000;
const AVATAR_MAX_BYTES = 2 * 1024 * 1024;
const AVATAR_TYPES = ['image/png', 'image/jpeg', 'image/webp'];
const { t, tm, rt } = useI18n();
const {
  remaining,
  errorCode,
  label: usageLabel,
  update: updateUsage,
  handleError: usageError,
} = usePlaygroundUsage();
const router = useRouter();
const store = useStore();
const { currentAccount, accountId, finishOnboarding } = useAccount();
const inboxes = useMapGetter('inboxes/getInboxes');
const assistant = ref(null);
const avatarInput = ref(null);
const avatarFile = ref(null);
const avatarPreview = ref('');
const avatarError = ref('');
const avatarUploading = ref(false);
const savedAvatar = computed(() => {
  const url = assistant.value?.avatar_url || '';
  return /\/captain\/avatar-(light|dark)\.svg$/.test(url) ? '' : url;
});
const avatarUrl = computed(() => avatarPreview.value || savedAvatar.value);
const clearAvatarPreview = () => {
  if (avatarPreview.value) URL.revokeObjectURL(avatarPreview.value);
  avatarPreview.value = '';
  avatarFile.value = null;
};
onBeforeUnmount(clearAvatarPreview);

const uploadAvatar = async () => {
  avatarUploading.value = true;
  try {
    const { data } = await CaptainAssistant.updateAvatar(
      assistant.value.id,
      avatarFile.value
    );
    assistant.value = { ...assistant.value, ...data };
  } catch {
    avatarError.value = t('ONBOARDING_ASSISTANT.PHOTO.UPLOAD_ERROR');
  } finally {
    clearAvatarPreview();
    avatarUploading.value = false;
  }
};
const selectAvatar = async event => {
  const [file] = event.target.files;
  event.target.value = '';
  if (!file) return;
  avatarError.value = '';
  if (!AVATAR_TYPES.includes(file.type)) {
    avatarError.value = t('ONBOARDING_ASSISTANT.PHOTO.FORMAT_ERROR');
    return;
  }
  if (file.size > AVATAR_MAX_BYTES) {
    avatarError.value = t('ONBOARDING_ASSISTANT.PHOTO.SIZE_ERROR');
    return;
  }
  clearAvatarPreview();
  avatarFile.value = file;
  avatarPreview.value = URL.createObjectURL(file);
  if (assistant.value) await uploadAvatar();
};
const removeAvatar = async () => {
  avatarError.value = '';
  if (!assistant.value) {
    clearAvatarPreview();
    return;
  }
  avatarUploading.value = true;
  try {
    const { data } = await CaptainAssistant.deleteAvatar(assistant.value.id);
    assistant.value = { ...assistant.value, ...data };
  } catch {
    avatarError.value = t('ONBOARDING_ASSISTANT.PHOTO.REMOVE_ERROR');
  } finally {
    avatarUploading.value = false;
  }
};
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
const chatLog = ref(null);
const pendingQuestion = ref('');
const businessType = computed(
  () => currentAccount.value?.custom_attributes?.business_type || 'other'
);
const toneOptions = computed(() => [
  {
    value: 'friendly',
    label: t('ONBOARDING_ASSISTANT.TONES.friendly'),
    description: t('ONBOARDING_ASSISTANT.TONE_DESCRIPTIONS.friendly'),
    icon: 'i-lucide-smile',
  },
  {
    value: 'professional',
    label: t('ONBOARDING_ASSISTANT.TONES.professional'),
    description: t('ONBOARDING_ASSISTANT.TONE_DESCRIPTIONS.professional'),
    icon: 'i-lucide-briefcase',
  },
  {
    value: 'brief',
    label: t('ONBOARDING_ASSISTANT.TONES.brief'),
    description: t('ONBOARDING_ASSISTANT.TONE_DESCRIPTIONS.brief'),
    icon: 'i-lucide-zap',
  },
]);
const examples = computed(() => {
  const messagesByType = tm('ONBOARDING_ASSISTANT.EXAMPLES');
  return EXAMPLE_IDS.map(id => rt(messagesByType[businessType.value][id]));
});
const exampleLabels = computed(() => {
  const labelsByType = tm('ONBOARDING_ASSISTANT.EXAMPLE_LABELS');
  return EXAMPLE_IDS.map(id => rt(labelsByType[businessType.value][id]));
});
watch(
  () => [messages.value.length, sending.value],
  () => {
    if (chatLog.value) chatLog.value.scrollTop = chatLog.value.scrollHeight;
  },
  { flush: 'post' }
);
const whatsappInbox = computed(() =>
  inboxes.value.find(inbox => inbox.channel_type === INBOX_TYPES.WHATSAPP)
);
const busy = computed(
  () =>
    saving.value || finishing.value || sending.value || avatarUploading.value
);
const valid = computed(() => name.value.trim() && goal.value.trim());
const active = computed(() => Boolean(assistant.value?.inbox_ids?.length));

const refreshAssistant = async () => {
  const { data } = await OnboardingAPI.getAssistant();
  assistant.value = data.assistant;
  return data.assistant;
};

const refreshUsage = async () => {
  if (!assistant.value) return;
  const { data } = await CaptainAssistant.playgroundUsage(assistant.value.id);
  updateUsage(data);
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
    await refreshUsage();
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
    if (avatarFile.value) await uploadAvatar();
    await refreshUsage();
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
    updateUsage(data);
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
  } catch (error) {
    chatError.value = usageError(error) || t('ONBOARDING_ASSISTANT.CHAT_ERROR');
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
const onQuestionKeydown = event => {
  if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
  event.preventDefault();
  sendQuestion();
};
</script>

<template>
  <AuthSplitLayout
    :title="t('ONBOARDING_ASSISTANT.MARKETING.TITLE')"
    :subtitle="t('ONBOARDING_ASSISTANT.MARKETING.SUBTITLE')"
    onboarding
    scrollable
  >
    <AuthStepHeader
      :title="t('ONBOARDING_ASSISTANT.TITLE')"
      :subtitle="t('ONBOARDING_ASSISTANT.SUBTITLE')"
      :step-name="t('ONBOARDING_ASSISTANT.TITLE')"
      :current="CURRENT_STEP"
      :back-to="{ name: 'onboarding_inbox_setup', params: { accountId } }"
      :back-disabled="busy || loading"
    >
      <template #brand>
        <AssistantAvatar :src="avatarUrl" class="size-10" />
      </template>
    </AuthStepHeader>
    <div v-if="!loading && !loadError" class="mb-4 space-y-2">
      <p
        id="assistant-photo-label"
        class="m-0 text-sm font-medium text-n-slate-12"
      >
        {{ t('ONBOARDING_ASSISTANT.PHOTO.LABEL') }}
      </p>
      <div class="flex items-center gap-3">
        <AssistantAvatar :src="avatarUrl" class="size-10" />
        <input
          id="assistant-photo"
          ref="avatarInput"
          type="file"
          accept="image/png,image/jpeg,image/webp"
          class="sr-only"
          tabindex="-1"
          :disabled="busy"
          aria-labelledby="assistant-photo-label"
          :aria-describedby="
            avatarError
              ? 'assistant-photo-hint assistant-photo-error'
              : 'assistant-photo-hint'
          "
          @change="selectAvatar"
        />
        <div class="flex min-w-0 flex-1 flex-wrap items-center gap-3">
          <AuthButton
            variant="secondary"
            class="!w-auto"
            :disabled="busy"
            :loading="avatarUploading"
            data-testid="upload-avatar"
            @click="avatarInput.click()"
          >
            {{ t('ONBOARDING_ASSISTANT.PHOTO.UPLOAD') }}
          </AuthButton>
          <button
            v-if="avatarUrl"
            type="button"
            :class="AUTH_LINK_CLASS"
            :disabled="busy"
            data-testid="remove-avatar"
            @click="removeAvatar"
          >
            {{ t('ONBOARDING_ASSISTANT.PHOTO.REMOVE') }}
          </button>
        </div>
      </div>
      <p
        id="assistant-photo-hint"
        class="m-0 text-sm leading-6 text-n-slate-11"
      >
        {{ t('ONBOARDING_ASSISTANT.PHOTO.HINT') }}
      </p>
      <AuthFeedback v-if="avatarError" id="assistant-photo-error" error>
        {{ avatarError }}
      </AuthFeedback>
    </div>
    <div
      v-if="loading"
      role="status"
      :aria-label="t('ONBOARDING_AUTH.LOADING')"
      class="space-y-4"
      data-testid="assistant-skeleton"
    >
      <span class="sr-only">{{ t('ONBOARDING_AUTH.LOADING') }}</span>
      <div
        class="h-12 rounded-xl bg-n-slate-3 motion-safe:animate-pulse"
        aria-hidden="true"
      />
      <div
        class="h-32 rounded-xl bg-n-slate-3 motion-safe:animate-pulse"
        aria-hidden="true"
      />
      <div
        class="h-20 rounded-xl bg-n-slate-3 motion-safe:animate-pulse"
        aria-hidden="true"
      />
    </div>
    <div v-else-if="loadError" class="space-y-4">
      <AuthFeedback error>
        {{ t('ONBOARDING_ASSISTANT.LOAD_ERROR') }}
      </AuthFeedback>
      <AuthButton @click="initialize">
        {{ t('ONBOARDING_ASSISTANT.RETRY') }}
      </AuthButton>
    </div>
    <form
      v-else-if="editing"
      id="assistant-form"
      class="space-y-4"
      @submit.prevent="createAndTest"
    >
      <AuthField
        id="assistant-name"
        v-model="name"
        required
        maxlength="120"
        :disabled="busy"
        :label="t('ONBOARDING_ASSISTANT.NAME')"
      />
      <div class="space-y-2">
        <label
          for="assistant-goal"
          class="text-sm font-medium leading-5 text-n-slate-12"
        >
          {{ t('ONBOARDING_ASSISTANT.GOAL') }}
        </label>
        <textarea
          id="assistant-goal"
          v-model="goal"
          required
          rows="3"
          :maxlength="GOAL_MAX_LENGTH"
          :disabled="busy"
          :class="AUTH_FIELD_CLASS"
          class="resize-none"
          aria-describedby="goal-count goal-examples"
        />
        <p
          id="goal-count"
          class="m-0 text-end text-sm leading-5 text-n-slate-11"
          aria-live="polite"
          aria-atomic="true"
        >
          {{
            t('ONBOARDING_ASSISTANT.CHARACTERS', {
              count: goal.length,
              max: GOAL_MAX_LENGTH,
            })
          }}
        </p>
        <p id="goal-examples" class="m-0 text-sm leading-6 text-n-slate-11">
          {{ t('ONBOARDING_ASSISTANT.EXAMPLES_LABEL') }}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="(example, index) in examples"
            :key="example"
            type="button"
            class="min-h-11 max-w-full rounded-full border border-solid px-3 py-2 text-start text-sm leading-5 text-n-slate-12 hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand disabled:opacity-60 motion-safe:transition-all motion-safe:duration-150 motion-safe:active:scale-[0.98]"
            :class="
              goal === example
                ? 'border-n-brand bg-n-blue-2'
                : 'border-n-slate-9 dark:border-n-slate-10 bg-transparent'
            "
            :disabled="busy"
            :title="example"
            :aria-label="`${exampleLabels[index]}: ${example}`"
            :aria-pressed="goal === example"
            data-testid="example"
            @click="goal = example"
          >
            {{ exampleLabels[index] }}
          </button>
        </div>
      </div>
      <fieldset role="radiogroup" aria-labelledby="assistant-tone-label">
        <legend
          id="assistant-tone-label"
          class="mb-2 text-sm font-medium leading-5 text-n-slate-12"
        >
          {{ t('ONBOARDING_ASSISTANT.TONE') }}
        </legend>
        <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <AuthChoiceCard
            v-for="option in toneOptions"
            :key="option.value"
            v-model="tone"
            name="assistant-tone"
            v-bind="option"
            :disabled="busy"
          />
        </div>
      </fieldset>
    </form>
    <section
      v-else
      class="space-y-4 motion-safe:animate-fade-in-up motion-safe:[animation-duration:200ms]"
      :aria-label="t('ONBOARDING_ASSISTANT.CHAT')"
    >
      <div
        role="status"
        class="flex items-start gap-3 rounded-xl bg-n-slate-3 p-4"
      >
        <AssistantAvatar :src="avatarUrl" class="size-10" />
        <div class="min-w-0 space-y-1">
          <p
            class="m-0 break-words text-base font-medium leading-6 text-n-slate-12"
          >
            {{ assistant.name }}
          </p>
          <p class="m-0 text-sm leading-6 text-n-slate-11">
            {{
              active
                ? t('ONBOARDING_ASSISTANT.ACTIVE')
                : t('ONBOARDING_ASSISTANT.DRAFT')
            }}
          </p>
        </div>
      </div>
      <h2 class="m-0 text-base font-semibold leading-6 text-n-slate-12">
        {{ t('ONBOARDING_ASSISTANT.CHAT') }}
      </h2>
      <AuthFeedback v-if="assistant.paused_reason">
        {{ t('ONBOARDING_ASSISTANT.AI_UNAVAILABLE') }}
      </AuthFeedback>
      <button
        v-if="assistant.paused_reason && !chatError"
        type="button"
        :class="AUTH_LINK_CLASS"
        :disabled="busy"
        data-testid="ai-retry"
        @click="initialize"
      >
        {{ t('ONBOARDING_ASSISTANT.RETRY') }}
      </button>
      <div
        ref="chatLog"
        role="log"
        aria-live="polite"
        :aria-label="t('ONBOARDING_ASSISTANT.CHAT')"
        tabindex="0"
        class="flex max-h-40 min-h-24 flex-col gap-3 overflow-y-auto rounded-xl border border-n-slate-9 dark:border-n-slate-10 bg-n-slate-2 p-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      >
        <div
          v-if="!messages.length"
          class="flex flex-1 flex-col items-center justify-center gap-2 text-center text-sm leading-6 text-n-slate-11"
          data-testid="chat-empty"
        >
          <span
            class="i-lucide-messages-square size-6 shrink-0"
            aria-hidden="true"
          />
          <p class="m-0">{{ t('ONBOARDING_ASSISTANT.CHAT_EMPTY') }}</p>
        </div>
        <div
          v-for="(message, index) in messages"
          :key="index"
          class="max-w-[90%] shrink-0 rounded-2xl p-3 motion-safe:animate-fade-in-up motion-safe:[animation-duration:200ms]"
          :class="
            message.role === 'user'
              ? 'self-end rounded-ee-sm bg-n-slate-4'
              : 'self-start rounded-es-sm bg-n-solid-1 dark:bg-n-solid-3'
          "
          :data-message-role="message.role"
        >
          <AssistantAvatar
            v-if="message.role === 'assistant'"
            :src="avatarUrl"
            class="mb-1 size-7"
          />
          <p
            class="m-0 mb-1 break-words text-sm font-medium leading-5 text-n-slate-11"
          >
            {{
              message.role === 'user'
                ? t('ONBOARDING_ASSISTANT.YOU')
                : assistant.name
            }}
          </p>
          <p
            class="m-0 whitespace-pre-wrap break-words text-sm leading-6 text-n-slate-12"
          >
            {{ message.content }}
          </p>
        </div>
        <p
          v-if="sending"
          role="status"
          class="m-0 flex items-center gap-2 text-sm leading-6 text-n-slate-11 motion-reduce:[&_svg]:animate-none"
        >
          <Spinner :size="16" aria-hidden="true" />{{
            t('ONBOARDING_ASSISTANT.THINKING')
          }}
        </p>
      </div>
      <form class="space-y-2" @submit.prevent="sendQuestion()">
        <p v-if="usageLabel" role="status" class="m-0 text-sm text-n-slate-11">
          {{ usageLabel }}
        </p>
        <a
          v-if="
            remaining?.uses_plan_pool &&
            remaining.plan_remaining <= 0 &&
            !chatError
          "
          :href="`/app/accounts/${accountId}/settings/billing`"
          :class="AUTH_LINK_CLASS"
        >
          {{ t('CAPTAIN.PLAYGROUND.USAGE.PLANS') }}
        </a>
        <div class="relative">
          <textarea
            id="assistant-question"
            v-model="question"
            :maxlength="PLAYGROUND_MESSAGE_LIMIT"
            rows="1"
            :class="AUTH_FIELD_CLASS"
            class="!h-14 resize-none !py-3.5 pe-16"
            :placeholder="t('ONBOARDING_ASSISTANT.QUESTION_PLACEHOLDER')"
            :aria-label="t('ONBOARDING_ASSISTANT.QUESTION')"
            :disabled="busy || Boolean(chatError)"
            :aria-invalid="Boolean(chatError)"
            :aria-describedby="chatError ? 'assistant-chat-error' : undefined"
            @keydown="onQuestionKeydown"
          />
          <AuthButton
            type="submit"
            variant="secondary"
            class="absolute end-1 top-1 !min-h-12 !w-12 !border-0 !bg-transparent !px-0"
            :loading="sending"
            :disabled="busy || !question.trim() || Boolean(chatError)"
            :aria-label="t('ONBOARDING_ASSISTANT.SEND')"
          >
            <span
              v-if="!sending"
              class="i-lucide-arrow-up size-5"
              aria-hidden="true"
            />
          </AuthButton>
        </div>
        <AuthFeedback v-if="chatError" id="assistant-chat-error" error>
          <p class="m-0">{{ chatError }}</p>
          <a
            v-if="errorCode === 'responses_limit_reached'"
            :href="`/app/accounts/${accountId}/settings/billing`"
            :class="AUTH_LINK_CLASS"
          >
            {{ t('CAPTAIN.PLAYGROUND.USAGE.PLANS') }}
          </a>
          <button
            type="button"
            :class="AUTH_LINK_CLASS"
            :disabled="busy"
            @click="sendQuestion(true)"
          >
            {{ t('ONBOARDING_ASSISTANT.RETRY') }}
          </button>
        </AuthFeedback>
      </form>
    </section>
    <template #footer>
      <AuthFeedback v-if="errorMessage" error>{{ errorMessage }}</AuthFeedback>
      <template v-if="!loading && !loadError">
        <AuthButton
          v-if="editing"
          type="submit"
          form="assistant-form"
          :loading="saving"
          :disabled="busy || !valid"
          data-testid="create"
        >
          {{
            saving
              ? t('ONBOARDING_ASSISTANT.CREATING')
              : t('ONBOARDING_ASSISTANT.CREATE')
          }}
        </AuthButton>
        <template v-else>
          <AuthButton
            :disabled="busy || !whatsappInbox"
            :loading="finishing"
            data-testid="activate"
            @click="complete(true)"
          >
            {{
              active
                ? t('ONBOARDING_ASSISTANT.CONTINUE')
                : t('ONBOARDING_ASSISTANT.ACTIVATE')
            }}
          </AuthButton>
          <p
            v-if="!whatsappInbox"
            class="m-0 text-center text-sm leading-6 text-n-slate-11"
          >
            {{ t('ONBOARDING_ASSISTANT.CONNECT_REQUIRED') }}
            <RouterLink
              :to="{ name: 'onboarding_inbox_setup', params: { accountId } }"
              :class="AUTH_LINK_CLASS"
            >
              {{ t('ONBOARDING_ASSISTANT.BACK_WHATSAPP') }}
            </RouterLink>
          </p>
          <button
            v-if="!active"
            type="button"
            :class="AUTH_LINK_CLASS"
            class="w-full"
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
        :class="AUTH_LINK_CLASS"
        class="w-full"
        :disabled="loading || busy"
        :aria-busy="finishing"
        data-testid="skip"
        @click="complete(false)"
      >
        <Spinner v-if="finishing" :size="16" aria-hidden="true" />
        {{ t('ONBOARDING_ASSISTANT.SKIP') }}
      </button>
    </template>
  </AuthSplitLayout>
</template>
