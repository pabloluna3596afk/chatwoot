<script setup>
// The text of the invitation of an appointment, written once for the account (Settings > Integrations > Calendars): what
// the customer reads in the Google Calendar event, for the appointments of the agents and of Captain alike.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import Button from 'dashboard/components-next/button/Button.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import {
  INVITATION_TOKENS,
  renderInvitation,
  sampleValues,
  unknownTokens,
} from 'dashboard/helper/invitationText';

const { t, locale } = useI18n();

const template = ref('');
const location = ref('');
const defaultTemplate = ref('');
const saved = ref({ template: '', location: '' });
const maxLength = ref(4000);
const isLoading = ref(true);
const isSaving = ref(false);
const showMenu = ref(false);
const textBox = ref(null);

const preview = computed(() =>
  renderInvitation(
    template.value,
    sampleValues(locale.value, location.value.trim())
  )
);
const unknown = computed(() => unknownTokens(template.value));
const usingDefault = computed(
  () => template.value.trim() === defaultTemplate.value.trim()
);
const dirty = computed(
  () =>
    template.value !== saved.value.template ||
    location.value !== saved.value.location
);
const canSave = computed(
  () => dirty.value && !unknown.value.length && !isSaving.value
);

const menuItems = computed(() =>
  INVITATION_TOKENS.map(token => ({
    label: `${t(`CALENDAR_INVITATION.VARIABLES.${token}`)} (${token})`,
    action: 'insert',
    value: token,
  }))
);

const apply = data => {
  defaultTemplate.value = data.default_template || '';
  template.value = data.template || data.default_template || '';
  location.value = data.location || '';
  maxLength.value = data.max_length || 4000;
  saved.value = { template: template.value, location: location.value };
};

const load = async () => {
  try {
    const { data } = await CalendarAPI.getInvitation();
    apply(data);
  } catch {
    useAlert(t('CALENDAR_INVITATION.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);

// Puts {{variable}} where the cursor is (at the end when the text was never focused).
const insertVariable = token => {
  const field = textBox.value?.querySelector('textarea');
  const text = template.value;
  const start = field?.selectionStart ?? text.length;
  const end = field?.selectionEnd ?? text.length;
  template.value = `${text.slice(0, start)}{{${token}}}${text.slice(end)}`;
  showMenu.value = false;
};

const restore = () => {
  template.value = defaultTemplate.value;
};

const save = async () => {
  isSaving.value = true;
  try {
    // The default text is saved as "nothing": the account then follows the default if it ever changes.
    const { data } = await CalendarAPI.updateInvitation({
      template: usingDefault.value ? '' : template.value.trim(),
      location: location.value.trim(),
    });
    apply(data);
    useAlert(t('CALENDAR_INVITATION.SAVED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('CALENDAR_INVITATION.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <section
    class="flex flex-col gap-4 p-4 border rounded-xl border-n-weak"
    data-testid="invitation-settings"
  >
    <div>
      <h3 class="text-heading-1 text-n-slate-12">
        {{ $t('CALENDAR_INVITATION.TITLE') }}
      </h3>
      <p class="mt-1 text-body-main text-n-slate-11">
        {{ $t('CALENDAR_INVITATION.DESCRIPTION') }}
      </p>
    </div>

    <div class="grid gap-4 lg:grid-cols-2">
      <div class="flex flex-col gap-3">
        <div ref="textBox" class="grid gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('CALENDAR_INVITATION.TEXT_LABEL') }}
          </span>
          <TextArea
            v-model="template"
            :disabled="isLoading"
            :max-length="maxLength"
            show-character-count
            :placeholder="$t('CALENDAR_INVITATION.TEXT_PLACEHOLDER')"
            :message="
              unknown.length
                ? $t('CALENDAR_INVITATION.UNKNOWN', {
                    tokens: unknown.map(token => `{{${token}}}`).join(', '),
                  })
                : ''
            "
            message-type="error"
            data-testid="invitation-template"
          />
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <MenuPopover
            v-model:open="showMenu"
            :menu-items="menuItems"
            show-search
            :search-placeholder="$t('CALENDAR_INVITATION.SEARCH_VARIABLE')"
            panel-class="w-72 max-w-[calc(100vw-2rem)]"
            :restore-focus-on-select="false"
            align="start"
            @action="item => insertVariable(item.value)"
          >
            <template #trigger>
              <Button
                type="button"
                slate
                xs
                icon="i-lucide-braces"
                :label="$t('CALENDAR_INVITATION.INSERT_VARIABLE')"
                data-testid="invitation-variables"
                @click="showMenu = !showMenu"
              />
            </template>
          </MenuPopover>
          <Button
            type="button"
            ghost
            slate
            xs
            :label="$t('CALENDAR_INVITATION.RESTORE')"
            :disabled="usingDefault"
            data-testid="invitation-restore"
            @click="restore"
          />
          <span v-if="usingDefault" class="text-xs text-n-slate-11">
            {{ $t('CALENDAR_INVITATION.USING_DEFAULT') }}
          </span>
        </div>

        <div class="grid gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('CALENDAR_INVITATION.LOCATION_LABEL') }}
          </span>
          <TextArea
            v-model="location"
            :disabled="isLoading"
            :max-length="500"
            :placeholder="$t('CALENDAR_INVITATION.LOCATION_PLACEHOLDER')"
            :message="$t('CALENDAR_INVITATION.LOCATION_HELP')"
            data-testid="invitation-location"
          />
        </div>
      </div>

      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('CALENDAR_INVITATION.PREVIEW') }}
        </span>
        <pre
          class="p-3 text-sm whitespace-pre-wrap border rounded-lg font-sans border-n-weak bg-n-alpha-2 text-n-slate-12"
          data-testid="invitation-preview"
          >{{ preview }}</pre
        >
        <span class="text-xs text-n-slate-11">
          {{ $t('CALENDAR_INVITATION.PREVIEW_NOTE') }}
        </span>
      </div>
    </div>

    <div>
      <Button
        type="button"
        :label="$t('CALENDAR_INVITATION.SAVE')"
        :is-loading="isSaving"
        :disabled="!canSave"
        data-testid="invitation-save"
        @click="save"
      />
    </div>
  </section>
</template>
