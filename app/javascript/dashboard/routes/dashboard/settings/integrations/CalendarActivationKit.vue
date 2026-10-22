<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// What an account needs so appointments work from day one: the contact attributes and the WhatsApp confirmation template
// Meta has to approve. The administrator marks the WhatsApp Cloud inboxes that get the template.
const STATUS_COLORS = {
  missing: 'slate',
  pending: 'amber',
  in_appeal: 'amber',
  approved: 'teal',
  rejected: 'ruby',
  error: 'ruby',
};
const SENT = ['pending', 'approved', 'in_appeal'];
const ERROR_CODES = [
  'token_invalid',
  'permission_denied',
  'rate_limited',
  'name_exists',
  'name_locked',
  'template_limit',
  'not_found',
  'meta_unreachable',
];
const ATTRIBUTES_TOTAL = 4;

const { t, te } = useI18n();
const { accountScopedRoute } = useAccount();
const { isAdmin } = useAdmin();
const kit = ref(null);
const results = ref({});
const selected = ref([]);
const loading = ref(true);
const loadFailed = ref(false);
const sending = ref(false);

const inboxes = computed(() => kit.value?.inboxes || []);
const attributesEnabled = computed(
  () => kit.value?.attributes?.enabled_keys?.length || 0
);
const canSend = computed(
  () => isAdmin.value && !sending.value && selected.value.length > 0
);

const errorOf = inbox =>
  results.value[inbox.id]?.status === 'error' ? results.value[inbox.id] : null;
const shownStatus = inbox => (errorOf(inbox) ? 'error' : inbox.status);
const statusLabel = status =>
  te(`CALENDAR_ACTIVATION_KIT.STATUS.${status}`)
    ? t(`CALENDAR_ACTIVATION_KIT.STATUS.${status}`)
    : status;
const isSelectable = inbox => !SENT.includes(inbox.status);
const canResend = inbox => inbox.status === 'rejected' || !!errorOf(inbox);
const errorMessage = result => {
  if (ERROR_CODES.includes(result.code)) {
    return t(`CALENDAR_ACTIVATION_KIT.ERRORS.${result.code}`);
  }
  return result.detail || t('CALENDAR_ACTIVATION_KIT.ERRORS.unknown');
};
const toggle = (id, checked) => {
  selected.value = checked
    ? [...selected.value, id]
    : selected.value.filter(value => value !== id);
};
const apply = data => {
  kit.value = data;
  results.value = data.results || {};
  const sendable = new Set(
    data.inboxes.filter(isSelectable).map(inbox => inbox.id)
  );
  selected.value = selected.value.filter(id => sendable.has(id));
};
const load = async () => {
  loading.value = true;
  try {
    const { data } = await CalendarAPI.getActivationKit();
    apply(data);
    loadFailed.value = false;
  } catch {
    loadFailed.value = true;
    useAlert(t('CALENDAR_ACTIVATION_KIT.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};
const send = async ids => {
  sending.value = true;
  try {
    const { data } = await CalendarAPI.applyActivationKit(ids);
    apply(data);
    const failed = Object.values(data.results || {}).some(
      result => result.status === 'error'
    );
    useAlert(
      failed
        ? t('CALENDAR_ACTIVATION_KIT.SENT_WITH_ERRORS')
        : t('CALENDAR_ACTIVATION_KIT.SENT')
    );
  } catch (error) {
    useAlert(
      error.response?.data?.error || t('CALENDAR_ACTIVATION_KIT.SEND_ERROR')
    );
  } finally {
    sending.value = false;
  }
};
onMounted(load);
</script>

<template>
  <section
    class="flex flex-col gap-4 p-4 border rounded-xl border-n-weak"
    data-testid="activation-kit"
  >
    <div>
      <h3 class="text-heading-1 text-n-slate-12">
        {{ $t('CALENDAR_ACTIVATION_KIT.TITLE') }}
      </h3>
      <p class="mt-1 text-body-main text-n-slate-11">
        {{ $t('CALENDAR_ACTIVATION_KIT.DESCRIPTION') }}
      </p>
    </div>

    <div v-if="loading && !kit" class="flex justify-center p-6">
      <Spinner />
    </div>
    <div
      v-else-if="loadFailed && !kit"
      role="alert"
      class="flex flex-wrap items-center gap-2 text-body-main text-n-ruby-11"
    >
      {{ $t('CALENDAR_ACTIVATION_KIT.LOAD_ERROR') }}
      <Button
        sm
        ghost
        :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
        @click="load"
      />
    </div>
    <template v-else-if="kit">
      <div
        class="flex flex-wrap items-center gap-2 text-body-main text-n-slate-12"
        data-testid="activation-kit-attributes"
      >
        <span class="i-lucide-user-round-check size-4 text-n-slate-11" />
        {{ $t('CALENDAR_ACTIVATION_KIT.ATTRIBUTES') }}
        <Label
          :label="
            $t('CALENDAR_ACTIVATION_KIT.ATTRIBUTES_COUNT', {
              count: attributesEnabled,
              total: ATTRIBUTES_TOTAL,
            })
          "
          :color="attributesEnabled ? 'teal' : 'slate'"
          compact
        />
      </div>

      <div class="flex flex-col gap-1">
        <h4 class="m-0 text-body-main font-medium text-n-slate-12">
          {{ $t('CALENDAR_ACTIVATION_KIT.QUESTION') }}
        </h4>
        <p class="m-0 text-body-main text-n-slate-11">
          {{ $t('CALENDAR_ACTIVATION_KIT.QUESTION_HINT') }}
        </p>
      </div>

      <div
        class="flex flex-col gap-2 p-3 rounded-xl bg-n-alpha-1"
        data-testid="activation-kit-preview"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{ $t('CALENDAR_ACTIVATION_KIT.PREVIEW') }}
        </span>
        <p class="m-0 text-body-main text-n-slate-12 whitespace-pre-line">
          {{ kit.template.body }}
        </p>
        <div
          v-if="kit.template.buttons?.length"
          class="flex flex-wrap gap-2"
          data-testid="activation-kit-buttons"
        >
          <span
            v-for="label in kit.template.buttons"
            :key="label"
            class="px-3 py-1 text-xs font-medium rounded-lg bg-n-solid-1 text-n-blue-11"
          >
            {{ label }}
          </span>
        </div>
        <span class="text-xs text-n-slate-11">
          {{
            $t('CALENDAR_ACTIVATION_KIT.TEMPLATE_META', {
              name: kit.template.name,
              language: kit.template.language,
            })
          }}
        </span>
      </div>

      <div
        v-if="!inboxes.length"
        class="flex flex-wrap items-center gap-2 text-body-main text-n-slate-11"
        data-testid="activation-kit-no-inbox"
      >
        {{ $t('CALENDAR_ACTIVATION_KIT.NO_INBOX') }}
        <router-link
          :to="accountScopedRoute('settings_inbox_new')"
          class="text-n-blue-11 hover:underline"
        >
          {{ $t('CALENDAR_ACTIVATION_KIT.CREATE_INBOX') }}
        </router-link>
      </div>
      <ul v-else class="flex flex-col gap-2 m-0 p-0 list-none">
        <li
          v-for="inbox in inboxes"
          :key="inbox.id"
          class="flex flex-wrap items-center gap-2"
          :data-testid="`activation-kit-inbox-${inbox.id}`"
        >
          <label
            class="flex items-center gap-2 text-body-main text-n-slate-12"
            :class="{ 'opacity-60': !isSelectable(inbox) }"
          >
            <Checkbox
              :model-value="selected.includes(inbox.id)"
              :disabled="!isAdmin || sending || !isSelectable(inbox)"
              :data-testid="`activation-kit-check-${inbox.id}`"
              @update:model-value="toggle(inbox.id, $event)"
            />
            {{ inbox.name }}
          </label>
          <Label
            :label="statusLabel(shownStatus(inbox))"
            :color="STATUS_COLORS[shownStatus(inbox)] || 'slate'"
            :data-testid="`activation-kit-status-${inbox.id}`"
            compact
            role="status"
          />
          <Button
            v-if="isAdmin && canResend(inbox)"
            xs
            ghost
            :label="$t('CALENDAR_ACTIVATION_KIT.RESEND')"
            :disabled="sending"
            :data-testid="`activation-kit-resend-${inbox.id}`"
            @click="send([inbox.id])"
          />
          <p
            v-if="inbox.status === 'rejected' && inbox.rejected_reason"
            class="basis-full m-0 text-xs text-n-ruby-11"
          >
            {{
              $t('CALENDAR_ACTIVATION_KIT.REJECTED_REASON', {
                reason: inbox.rejected_reason,
              })
            }}
          </p>
          <p
            v-if="errorOf(inbox)"
            class="basis-full m-0 text-xs text-n-ruby-11"
            role="alert"
          >
            {{ errorMessage(errorOf(inbox)) }}
          </p>
        </li>
      </ul>

      <div class="flex flex-wrap items-center gap-2">
        <Button
          v-if="isAdmin && inboxes.length"
          type="button"
          :label="$t('CALENDAR_ACTIVATION_KIT.SEND')"
          :disabled="!canSend"
          :is-loading="sending"
          data-testid="activation-kit-send"
          @click="send(selected)"
        />
        <Button
          type="button"
          faded
          slate
          icon="i-lucide-refresh-cw"
          :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
          :disabled="loading || sending"
          data-testid="activation-kit-reload"
          @click="load"
        />
      </div>
    </template>
  </section>
</template>
