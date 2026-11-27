<script setup>
// The text of the invitation of an appointment, written once for the account (Settings > Integrations > Calendars): what
// the customer reads in the Google Calendar event, for the appointments of the agents and of Captain alike.
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import {
  INVITATION_TOKENS,
  renderInvitation,
  sampleValues,
  unknownTokens,
} from 'dashboard/helper/invitationText';

const emit = defineEmits(['dirty', 'state']);

const { t, locale } = useI18n();

const template = ref('');
const location = ref('');
const defaultTemplate = ref('');
const saved = ref({ template: '', location: '' });
const maxLength = ref(4000);
const isLoading = ref(true);
const loadFailed = ref(false);
const isSaving = ref(false);
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
watch(dirty, value => emit('dirty', value));
watch([template, defaultTemplate], () =>
  emit('state', { usingDefault: usingDefault.value })
);
const canSave = computed(
  () =>
    dirty.value &&
    !unknown.value.length &&
    !isSaving.value &&
    !isLoading.value &&
    !loadFailed.value
);
const tokenLabel = token => {
  switch (token) {
    case 'nombre':
      return t('CALENDAR_INVITATION.VARIABLES.nombre');
    case 'primer_nombre':
      return t('CALENDAR_INVITATION.VARIABLES.primer_nombre');
    case 'telefono':
      return t('CALENDAR_INVITATION.VARIABLES.telefono');
    case 'correo':
      return t('CALENDAR_INVITATION.VARIABLES.correo');
    case 'agente':
      return t('CALENDAR_INVITATION.VARIABLES.agente');
    case 'empresa':
      return t('CALENDAR_INVITATION.VARIABLES.empresa');
    case 'fecha':
      return t('CALENDAR_INVITATION.VARIABLES.fecha');
    case 'hora':
      return t('CALENDAR_INVITATION.VARIABLES.hora');
    case 'motivo':
      return t('CALENDAR_INVITATION.VARIABLES.motivo');
    case 'direccion':
      return t('CALENDAR_INVITATION.VARIABLES.direccion');
    case 'enlace_meet':
      return t('CALENDAR_INVITATION.VARIABLES.enlace_meet');
    default:
      return t('CALENDAR_INVITATION.VARIABLES.conversacion');
  }
};

const apply = data => {
  defaultTemplate.value = data.default_template || '';
  template.value = data.template || data.default_template || '';
  location.value = data.location || '';
  maxLength.value = data.max_length || 4000;
  saved.value = { template: template.value, location: location.value };
  emit('state', { usingDefault: usingDefault.value });
};

const load = async () => {
  isLoading.value = true;
  loadFailed.value = false;
  try {
    const { data } = await CalendarAPI.getInvitation();
    apply(data);
  } catch {
    loadFailed.value = true;
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);

// Puts {{variable}} where the cursor is (at the end when the text was never focused).
const insertVariable = async token => {
  const field = textBox.value?.querySelector('textarea');
  const text = template.value;
  const start = field?.selectionStart ?? text.length;
  const end = field?.selectionEnd ?? text.length;
  template.value = `${text.slice(0, start)}{{${token}}}${text.slice(end)}`;
  await nextTick();
  field?.focus();
  field?.setSelectionRange(start + token.length + 4, start + token.length + 4);
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
  <section class="flex flex-col gap-4" data-testid="invitation-settings">
    <div>
      <p class="m-0 text-body-main text-n-slate-11">
        {{ $t('CITAS_SCREEN.INSERT_HINT') }}
      </p>
    </div>

    <div v-if="loadFailed" role="alert" class="text-body-main text-n-ruby-11">
      {{ $t('CALENDAR_INVITATION.LOAD_ERROR') }}
      <Button
        intent="secondary"
        :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
        @click="load"
      />
    </div>
    <div v-else class="grid gap-4 lg:grid-cols-2">
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
          <Button
            v-for="token in INVITATION_TOKENS"
            :key="token"
            type="button"
            intent="secondary"
            size="sm"
            :label="tokenLabel(token)"
            :disabled="isLoading"
            :data-testid="`invitation-token-${token}`"
            @click="insertVariable(token)"
          />
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
        <div
          class="p-3 text-sm whitespace-pre-wrap rounded-lg font-sans bg-n-alpha-2 text-n-slate-12 break-words"
          data-testid="invitation-preview"
        >
          {{ preview }}
        </div>
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
