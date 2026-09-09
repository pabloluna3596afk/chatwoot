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
const globalConfig = useMapGetter('globalConfig/get');
// Panel AI's webhook URL is generic for the whole installation (it resolves
// which org/assistant a message belongs to from the payload, not the URL) —
// prefilling it removes a manual copy-paste step for the common case, while
// staying a normal editable field for anyone plugging in a different bot.
const defaultWebhookUrl = computed(
  () => globalConfig.value.panelAiDefaultWebhookUrl || ''
);

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
    botUrl: {
      required: helpers.withMessage(
        () => t('AGENT_BOTS.FORM.ERRORS.URL'),
        required
      ),
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

// Always-visible caption instead of a hover-only tooltip — this is the one
// field that can actually stop the bot from receiving messages, so the
// warning shouldn't be easy to miss.
const botUrlMessage = computed(
  () => botUrlError.value || t('AGENT_BOTS.FORM.WEBHOOK_URL.HELP')
);
const botUrlMessageType = computed(() =>
  botUrlError.value ? 'error' : 'info'
);

const resetForm = () => {
  Object.assign(formState, {
    botName: '',
    botDescription: '',
    botUrl: defaultWebhookUrl.value,
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
          :message="botUrlMessage"
          :message-type="botUrlMessageType"
          @blur="v$.botUrl.$touch()"
        />
      </div>

      <div
        v-if="botSecret && type === MODAL_TYPES.EDIT"
        class="flex flex-col gap-1"
      >
        <label
          class="mb-0.5 flex items-center gap-1 text-sm font-medium text-n-slate-12"
        >
          {{ $t('AGENT_BOTS.SECRET.LABEL') }}
          <span
            v-tooltip.top="$t('AGENT_BOTS.SECRET.TOOLTIP')"
            class="i-lucide-info size-3.5 text-n-slate-9 cursor-help"
          />
        </label>
        <AccessToken
          :value="botSecret"
          @on-copy="onCopySecret"
          @on-reset="onResetSecret"
        />
      </div>

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
