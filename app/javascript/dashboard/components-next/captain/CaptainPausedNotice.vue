<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { usePolicy } from 'dashboard/composables/usePolicy';

import Banner from 'dashboard/components-next/banner/Banner.vue';

const SUPER_ADMIN_CAPTAIN_SETTINGS = '/super_admin/app_config?config=captain';

const { t } = useI18n();
const route = useRoute();
const { accountScopedRoute } = useAccount();
const { checkPermissions } = usePolicy();

const assistants = useMapGetter('captainAssistants/getRecords');
const currentUser = useMapGetter('getCurrentUser');

const assistant = computed(() =>
  assistants.value?.find(({ id }) => id === Number(route.params.assistantId))
);
const reason = computed(() => assistant.value?.paused_reason || '');
const isSuperAdmin = computed(() => currentUser.value?.type === 'SuperAdmin');
const isVisible = computed(
  () => Boolean(reason.value) && checkPermissions(['administrator'])
);
const isMissingKey = computed(() => reason.value === 'missing_key');

const message = computed(() =>
  isMissingKey.value
    ? t('CAPTAIN.PAUSED_NOTICE.MISSING_KEY', { name: assistant.value.name })
    : t('CAPTAIN.PAUSED_NOTICE.QUOTA_EXHAUSTED', {
        name: assistant.value.name,
      })
);
</script>

<template>
  <Banner
    v-if="isVisible"
    color="amber"
    data-testid="captain-paused-notice"
    class="mb-3"
  >
    <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
      <span class="i-lucide-triangle-alert size-4 shrink-0" />
      <span data-testid="captain-paused-message">{{ message }}</span>
      <template v-if="isMissingKey">
        <a
          v-if="isSuperAdmin"
          data-testid="captain-paused-key-link"
          class="link font-medium underline"
          :href="SUPER_ADMIN_CAPTAIN_SETTINGS"
        >
          {{ t('CAPTAIN.PAUSED_NOTICE.CONFIGURE_KEY') }}
        </a>
        <span v-else data-testid="captain-paused-key-hint">
          {{ t('CAPTAIN.PAUSED_NOTICE.ASK_INSTALLATION_ADMIN') }}
        </span>
      </template>
      <router-link
        v-else
        data-testid="captain-paused-billing-link"
        class="link font-medium underline"
        :to="accountScopedRoute('billing_settings_index')"
      >
        {{ t('CAPTAIN.PAUSED_NOTICE.VIEW_BILLING') }}
      </router-link>
    </div>
  </Banner>
</template>
