<script setup>
import { ref, computed, reactive, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { required, helpers, url } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useToggle } from '@vueuse/core';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import AccessToken from 'dashboard/routes/dashboard/settings/profile/AccessToken.vue';
import ConfirmButton from 'dashboard/components-next/button/ConfirmButton.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'create',
    validator: value => ['create', 'edit'].includes(value),
  },
  selectedBot: {
    type: Object,
    default: () => ({}),
  },
});

const MODAL_TYPES = {
  CREATE: 'create',
  EDIT: 'edit',
};

const store = useStore();
const { t } = useI18n();
const dialogRef = ref(null);
const uiFlags = useMapGetter('agentBots/getUIFlags');

const formState = reactive({
  botName: '',
  botDescription: '',
  botUrl: '',
  botAvatar: null,
  botAvatarUrl: '',
});

// Only reveals the webhook secret after creation — the access token used to
// be shown here too, but Panel AI never authenticates with a bot's own
// token (every call back to Chatwoot uses one fixed CHATWOOT_API_TOKEN from
// its own .env, verified by tracing every ChatwootClient(...) call site).
// Showing "Reset" for a credential that does nothing here only invites
// admins to break something for no real gain, so it was dropped entirely.
const [showSecretReveal, toggleSecretReveal] = useToggle();
const botSecret = ref('');

const v$ = useVuelidate(
  {
    botName: {
      required: helpers.withMessage(
        () => t('AGENT_BOTS.FORM.ERRORS.NAME'),
        required
      ),
    },
    // Blank is a valid, meaningful choice here — it means "use Panel AI's
    // default" (see AgentBot#effective_outgoing_url) — so no `required`.
    botUrl: {
      url: helpers.withMessage(
        () => t('AGENT_BOTS.FORM.ERRORS.VALID_URL'),
        url
      ),
    },
  },
  formState
);

const isLoading = computed(() =>
  props.type === MODAL_TYPES.CREATE
    ? uiFlags.value.isCreating
    : uiFlags.value.isUpdating
);

const dialogTitle = computed(() => {
  if (showSecretReveal.value) {
    return t('AGENT_BOTS.SECRET.LABEL');
  }

  return props.type === MODAL_TYPES.CREATE
    ? t('AGENT_BOTS.ADD.TITLE')
    : t('AGENT_BOTS.EDIT.TITLE');
});

const dialogDescription = computed(() => {
  if (showSecretReveal.value) {
    return t('AGENT_BOTS.SECRET.CREATED_DESC');
  }
  return '';
});

const confirmButtonLabel = computed(() =>
  props.type === MODAL_TYPES.CREATE
    ? t('AGENT_BOTS.FORM.CREATE')
    : t('AGENT_BOTS.FORM.UPDATE')
);

const botNameError = computed(() =>
  v$.value.botName.$error ? v$.value.botName.$errors[0]?.$message : ''
);

const botUrlError = computed(() =>
  v$.value.botUrl.$error ? v$.value.botUrl.$errors[0]?.$message : ''
);

// Rendered as our own <p> below the Input rather than through its built-in
// `message` slot, which truncates to one line — fine for a short validation
// error, not for this full sentence.

// Blank means "use Panel AI's default" — the client never sees that real
// value (it never even reaches the browser, see the jbuilder secret gate
// below), so this is the one signal the UI has for which mode it's in.
const isUsingCustomAi = computed(() => !!formState.botUrl.trim());

const botUrlHelp = computed(() =>
  isUsingCustomAi.value
    ? t('AGENT_BOTS.FORM.WEBHOOK_URL.HELP_CUSTOM')
    : t('AGENT_BOTS.FORM.WEBHOOK_URL.HELP_DEFAULT')
);

const resetForm = () => {
  Object.assign(formState, {
    botName: '',
    botDescription: '',
    botUrl: '',
    botAvatar: null,
    botAvatarUrl: '',
  });
  v$.value.$reset();
};

const handleImageUpload = ({ file, url: avatarUrl }) => {
  formState.botAvatar = file;
  formState.botAvatarUrl = avatarUrl;
};

const handleAvatarDelete = async () => {
  if (props.selectedBot?.id) {
    try {
      await store.dispatch(
        'agentBots/deleteAgentBotAvatar',
        props.selectedBot.id
      );
      formState.botAvatar = null;
      formState.botAvatarUrl = '';
      useAlert(t('AGENT_BOTS.AVATAR.SUCCESS_DELETE'));
    } catch (error) {
      useAlert(t('AGENT_BOTS.AVATAR.ERROR_DELETE'));
    }
  } else {
    formState.botAvatar = null;
    formState.botAvatarUrl = '';
  }
};

const handleSubmit = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;
  if (showSecretReveal.value) return;

  const botData = {
    name: formState.botName,
    description: formState.botDescription,
    outgoing_url: formState.botUrl,
    bot_type: 'webhook',
    avatar: formState.botAvatar,
  };

  const isCreate = props.type === MODAL_TYPES.CREATE;

  try {
    const actionPayload = isCreate
      ? botData
      : { id: props.selectedBot.id, data: botData };

    const response = await store.dispatch(
      `agentBots/${isCreate ? 'create' : 'update'}`,
      actionPayload
    );

    const alertKey = isCreate
      ? t('AGENT_BOTS.ADD.API.SUCCESS_MESSAGE')
      : t('AGENT_BOTS.EDIT.API.SUCCESS_MESSAGE');
    useAlert(alertKey);

    // Show the webhook secret once, right after creation
    if (isCreate) {
      const { secret: responseSecret, id } = response || {};

      if (id && responseSecret) {
        botSecret.value = responseSecret;
        toggleSecretReveal(true);
      } else {
        botSecret.value = '';
        dialogRef.value.close();
      }
    } else {
      dialogRef.value.close();
    }

    resetForm();
  } catch (error) {
    const errorKey = isCreate
      ? t('AGENT_BOTS.ADD.API.ERROR_MESSAGE')
      : t('AGENT_BOTS.EDIT.API.ERROR_MESSAGE');
    useAlert(errorKey);
  }
};

const initializeForm = () => {
  if (props.selectedBot && Object.keys(props.selectedBot).length) {
    const {
      name,
      description,
      outgoing_url: botUrl,
      thumbnail,
      bot_config: botConfig,
      secret: botSecretValue,
    } = props.selectedBot;
    formState.botName = name || '';
    formState.botDescription = description || '';
    formState.botUrl = botUrl || botConfig?.webhook_url || '';
    formState.botAvatarUrl = thumbnail || '';

    if (props.type === MODAL_TYPES.EDIT && botSecretValue) {
      botSecret.value = botSecretValue;
    }
  } else {
    resetForm();
  }
};

const onCopySecret = async value => {
  await copyTextToClipboard(value || botSecret.value);
  useAlert(t('AGENT_BOTS.SECRET.COPY_SUCCESS'));
};

const onResetSecret = async () => {
  const response = await store.dispatch(
    'agentBots/resetSecret',
    props.selectedBot.id
  );
  if (response) {
    botSecret.value = response.secret;
    useAlert(t('AGENT_BOTS.SECRET.RESET_SUCCESS'));
  } else {
    useAlert(t('AGENT_BOTS.SECRET.RESET_ERROR'));
  }
};

const closeModal = () => {
  if (!showSecretReveal.value) v$.value?.$reset();
  botSecret.value = '';
  toggleSecretReveal(false);
};

const onClickClose = () => {
  closeModal();
  dialogRef.value.close();
};

watch(() => props.selectedBot, initializeForm, { immediate: true, deep: true });

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="dialogTitle"
    :description="dialogDescription"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="closeModal"
  >
    <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
      <div
        v-if="!showSecretReveal || type === MODAL_TYPES.EDIT"
        class="flex flex-col gap-4"
      >
        <div class="mb-2 flex flex-col items-start">
          <span class="mb-2 text-sm font-medium text-n-slate-12">
            {{ $t('AGENT_BOTS.FORM.AVATAR.LABEL') }}
          </span>
          <Avatar
            :src="formState.botAvatarUrl"
            :name="formState.botName"
            :size="68"
            allow-upload
            icon-name="i-lucide-bot-message-square"
            @upload="handleImageUpload"
            @delete="handleAvatarDelete"
          />
        </div>

        <Input
          id="bot-name"
          v-model="formState.botName"
          :label="$t('AGENT_BOTS.FORM.NAME.LABEL')"
          :placeholder="$t('AGENT_BOTS.FORM.NAME.PLACEHOLDER')"
          :message="botNameError"
          :message-type="botNameError ? 'error' : 'info'"
          @blur="v$.botName.$touch()"
        />

        <TextArea
          id="bot-description"
          v-model="formState.botDescription"
          :label="$t('AGENT_BOTS.FORM.DESCRIPTION.LABEL')"
          :placeholder="$t('AGENT_BOTS.FORM.DESCRIPTION.PLACEHOLDER')"
        />

        <Input
          id="bot-url"
          v-model="formState.botUrl"
          :label="$t('AGENT_BOTS.FORM.WEBHOOK_URL.LABEL')"
          :placeholder="$t('AGENT_BOTS.FORM.WEBHOOK_URL.PLACEHOLDER')"
          :message="botUrlError"
          message-type="error"
          @blur="v$.botUrl.$touch()"
        />
        <p
          v-if="!botUrlError"
          class="-mt-1 text-label-small"
          :class="isUsingCustomAi ? 'text-n-amber-11' : 'text-n-slate-11'"
        >
          {{ botUrlHelp }}
        </p>
      </div>

      <!-- Using our default (blank URL): nothing to see or copy, only reset -->
      <div
        v-if="type === MODAL_TYPES.EDIT && !isUsingCustomAi"
        class="flex flex-col gap-1"
      >
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ $t('AGENT_BOTS.SECRET.LABEL') }}
        </label>
        <ConfirmButton
          :label="$t('PROFILE_SETTINGS.FORM.ACCESS_TOKEN.RESET')"
          :confirm-label="
            $t('PROFILE_SETTINGS.FORM.ACCESS_TOKEN.CONFIRM_RESET')
          "
          :confirm-hint="$t('PROFILE_SETTINGS.FORM.ACCESS_TOKEN.CONFIRM_HINT')"
          color="slate"
          confirm-color="ruby"
          variant="outline"
          icon="i-lucide-key-round"
          class="self-start rounded-xl"
          @click="onResetSecret"
        />
        <p class="text-label-small text-n-slate-11">
          {{ $t('AGENT_BOTS.SECRET.HELP_DEFAULT') }}
        </p>
      </div>

      <!-- Own AI, secret already loaded from the server -->
      <div
        v-else-if="isUsingCustomAi && botSecret && type === MODAL_TYPES.EDIT"
        class="flex flex-col gap-1"
      >
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ $t('AGENT_BOTS.SECRET.LABEL') }}
        </label>
        <AccessToken
          :value="botSecret"
          @on-copy="onCopySecret"
          @on-reset="onResetSecret"
        />
        <p class="text-label-small text-n-slate-11">
          {{ $t('AGENT_BOTS.SECRET.HELP_CUSTOM') }}
        </p>
      </div>

      <!-- Own AI just typed, not saved yet -- server hasn't sent a secret -->
      <p
        v-else-if="isUsingCustomAi && type === MODAL_TYPES.EDIT"
        class="text-label-small text-n-slate-11"
      >
        {{ $t('AGENT_BOTS.SECRET.HELP_PENDING_SAVE') }}
      </p>

      <div
        v-if="botSecret && showSecretReveal && type === MODAL_TYPES.CREATE"
        class="flex flex-col gap-1"
      >
        <p class="text-sm text-n-slate-11">
          {{ $t('AGENT_BOTS.SECRET.CREATED_DESC') }}
        </p>
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ $t('AGENT_BOTS.SECRET.LABEL') }}
        </label>
        <AccessToken
          :value="botSecret"
          :show-reset-button="false"
          @on-copy="onCopySecret"
        />
      </div>

      <div class="flex items-center justify-end w-full gap-2 px-0 py-2">
        <NextButton
          faded
          slate
          type="reset"
          :label="$t('AGENT_BOTS.FORM.CANCEL')"
          @click="onClickClose()"
        />
        <NextButton
          v-if="!showSecretReveal"
          type="submit"
          data-testid="label-submit"
          :label="confirmButtonLabel"
          :is-loading="isLoading"
          :disabled="v$.$invalid"
        />
      </div>
    </form>
  </Dialog>
</template>
