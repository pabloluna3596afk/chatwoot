<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store';
import IntegrationsAPI from 'dashboard/api/integrations';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const INTEGRATION_ID = 'google_translate';
const { t } = useI18n();
const store = useStore();
const integration = useFunctionGetter(
  'integrations/getIntegration',
  INTEGRATION_ID
);
const uiFlags = useMapGetter('integrations/getUIFlags');
const connectedHook = computed(() => integration.value.hooks?.[0] || null);
const isLoaded = computed(() => Boolean(integration.value.id));
const projectId = ref('');
const credentialsJson = ref('');
const errorMessage = ref('');
const isConnecting = ref(false);
const isDisconnecting = ref(false);
const dialogRef = ref(null);

const connect = async () => {
  errorMessage.value = '';
  if (!projectId.value.trim() || !credentialsJson.value.trim()) {
    errorMessage.value = t(
      'INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.REQUIRED_FIELDS'
    );
    return;
  }

  let credentials;
  try {
    credentials = JSON.parse(credentialsJson.value);
  } catch {
    errorMessage.value = t(
      'INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.INVALID_CREDENTIALS'
    );
    return;
  }

  isConnecting.value = true;
  try {
    await IntegrationsAPI.connectGoogleTranslate({
      projectId: projectId.value,
      credentials,
    });
    await store.dispatch('integrations/get');
    projectId.value = '';
    credentialsJson.value = '';
    useAlert(t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.CONNECT_SUCCESS'));
  } catch (error) {
    errorMessage.value =
      error?.response?.data?.error ||
      t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.INVALID_CREDENTIALS');
  } finally {
    isConnecting.value = false;
  }
};

const disconnect = async () => {
  isDisconnecting.value = true;
  try {
    await IntegrationsAPI.disconnectGoogleTranslate();
    await store.dispatch('integrations/get');
    useAlert(t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.DISCONNECT_SUCCESS'));
  } catch {
    useAlert(t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.ERROR'));
  } finally {
    isDisconnecting.value = false;
    dialogRef.value?.close();
  }
};

onMounted(() => store.dispatch('integrations/get', INTEGRATION_ID));
</script>

<template>
  <SettingsLayout :is-loading="uiFlags.isFetching && !isLoaded">
    <template #header>
      <BaseSettingsHeader
        :title="t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.HEADER')"
        description=""
        :feature-name="INTEGRATION_ID"
        :back-button-label="t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <div v-if="isLoaded" class="flex flex-col gap-5">
        <section
          class="flex flex-col gap-4 rounded-xl bg-n-card p-5 outline outline-1 outline-n-container"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex flex-col gap-1">
              <h3 class="text-heading-2 text-n-slate-12">
                {{ t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.STATUS') }}
              </h3>
              <p class="text-body-main text-n-slate-11">
                {{
                  connectedHook
                    ? t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.CONNECTED')
                    : t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.NOT_CONNECTED')
                }}
              </p>
            </div>
            <Button
              v-if="connectedHook"
              intent="destructive"
              :label="t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.DISCONNECT')"
              :is-loading="isDisconnecting"
              @click="dialogRef?.open()"
            />
          </div>
          <div v-if="connectedHook" class="flex flex-col gap-1">
            <span class="text-label-small text-n-slate-11">
              {{ t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.PROJECT_ID') }}
            </span>
            <span class="break-all font-mono text-body-main text-n-slate-12">
              {{
                connectedHook.settings?.projectId ||
                connectedHook.settings?.project_id
              }}
            </span>
          </div>
        </section>

        <section
          v-if="!connectedHook"
          class="flex flex-col gap-4 rounded-xl bg-n-card p-5 outline outline-1 outline-n-container"
        >
          <div class="flex flex-col gap-1">
            <h3 class="text-heading-2 text-n-slate-12">
              {{ t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.CONNECT_TITLE') }}
            </h3>
            <p class="text-body-main text-n-slate-11">
              {{ t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.CREDENTIALS_HELP') }}
            </p>
          </div>
          <form class="flex max-w-2xl flex-col gap-3" @submit.prevent="connect">
            <Input
              id="google-translate-project-id"
              v-model="projectId"
              :label="t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.PROJECT_ID')"
            />
            <TextArea
              id="google-translate-credentials"
              v-model="credentialsJson"
              :label="t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.CREDENTIALS')"
              auto-height
              min-height="10rem"
            />
            <p v-if="errorMessage" class="text-sm text-n-ruby-9" role="alert">
              {{ errorMessage }}
            </p>
            <Button
              type="submit"
              intent="primary"
              :label="t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.CONNECT')"
              :is-loading="isConnecting"
            />
          </form>
        </section>
      </div>
    </template>
    <Dialog
      ref="dialogRef"
      type="alert"
      :title="t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.DISCONNECT')"
      :description="
        t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.DISCONNECT_CONFIRM')
      "
      :confirm-button-label="
        t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.DISCONNECT')
      "
      :cancel-button-label="t('INTEGRATION_SETTINGS.GOOGLE_TRANSLATE.CANCEL')"
      @confirm="disconnect"
    />
  </SettingsLayout>
</template>
