<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import { useAccount } from 'dashboard/composables/useAccount';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { TemplatePreview } from 'dashboard/components-next/template-preview';
import { PLATFORMS } from 'dashboard/services/TemplateConstants';
import {
  BUTTON_TYPES,
  CATEGORIES,
  HEADER_FORMATS,
  LIMITS,
  MEDIA_ACCEPT,
  MEDIA_FORMATS,
  CAPTAIN_VARIABLES,
  buildPayload,
  editRules,
  emptyForm,
  formFromTemplate,
  hasNamedVariables,
  isValidVariableName,
  newButton,
  previewTemplate,
  previewVariables,
  promoWarnings,
  toSnakeCase,
  validateForm,
  variableNumbers,
  variableTokens,
} from './templateForm';
import { formatTemplateLabel, templateStatusClasses } from './templateUtils';
import { defaultLanguage, languageOptions } from './whatsappLanguages';

const props = defineProps({
  // The WhatsApp Cloud inboxes the template can be created in.
  inboxes: { type: Array, default: () => [] },
  // The templates of the page: a new one starts in the language most of its channel's templates use.
  templates: { type: Array, default: () => [] },
});

const emit = defineEmits(['saved']);

const { t, te, locale } = useI18n();
const store = useStore();
const { currentAccount } = useAccount();
const { bindings } = useTemplateBindings('message');

const LANGUAGE_OPTIONS = computed(() => languageOptions(locale.value));

const panelRef = ref(null);
const previewDialogRef = ref(null);
const form = reactive(emptyForm());
const editing = ref(null);
const liveState = ref(null);
const showErrors = ref(false);
const isSaving = ref(false);
const isUploading = ref(false);
const mediaHeaderAvailable = ref(false);
const mediaHeaderReason = ref('');
const headerPreviewUrl = ref('');
const headerFileSize = ref(0);
const fileInput = ref(null);
const bodyBox = ref(null);
const languageTouched = ref(false);
// How the variables of the message are written: {{nombre}} or {{1}}. A template uses one of them.
const variableMode = ref('NAMED');
const customVariable = ref('');
const showVariableMenu = ref(false);

const isEdit = computed(() => Boolean(editing.value));
const errors = computed(() => validateForm(form, { isEdit: isEdit.value }));
const visibleErrors = computed(() => (showErrors.value ? errors.value : {}));
const rules = computed(() => editRules(editing.value?.status));
const categoryLocked = computed(
  () => isEdit.value && rules.value.categoryLocked
);
const isMediaHeader = computed(() =>
  MEDIA_FORMATS.includes(form.header.format)
);
const bodyVariables = computed(() => variableTokens(form.body.text));
const generatedName = computed(() => toSnakeCase(form.name));
const preview = computed(() => previewTemplate(form, headerPreviewUrl.value));
const variables = computed(() => previewVariables(form));
const promoWords = computed(() => promoWarnings(form));
const statusKey = computed(() =>
  String(liveState.value?.status || editing.value?.status || '').toUpperCase()
);
const preservedLabels = computed(() => [
  ...form.preserved.components.map(item => item.component.type),
  ...form.preserved.buttons.map(item => item.button.type),
]);
const hasCopyCode = computed(() =>
  form.buttons.some(button => button.type === 'COPY_CODE')
);

const errorText = key => {
  if (!key) return '';
  return t(`WHATSAPP_TEMPLATE_MGMT.FORM.ERRORS.${key}`, {
    variable: '{{1}}',
    sequence: '{{1}}, {{2}}, {{3}}…',
    headerLimit: LIMITS.headerText,
    bodyLimit: LIMITS.body,
    footerLimit: LIMITS.footer,
    buttonLimit: LIMITS.buttonText,
    buttonsLimit: LIMITS.buttons,
    urlLimit: LIMITS.urlButtons,
    phoneLimit: LIMITS.phoneButtons,
    codeLimit: LIMITS.copyCode,
  });
};
const fieldError = path => errorText(visibleErrors.value[path]);

const statusLabel = computed(() => {
  const key = statusKey.value;
  return te(`WHATSAPP_TEMPLATE_MGMT.STATUS.${key}`)
    ? t(`WHATSAPP_TEMPLATE_MGMT.STATUS.${key}`)
    : formatTemplateLabel(key);
});

const mediaUnavailableText = computed(() => {
  const key = `WHATSAPP_TEMPLATE_MGMT.FORM.MEDIA_HEADER_REASONS.${mediaHeaderReason.value}`;
  return mediaHeaderReason.value && te(key)
    ? t(key)
    : t('WHATSAPP_TEMPLATE_MGMT.FORM.MEDIA_HEADER_UNAVAILABLE');
});

const apiError = error =>
  error?.response?.data?.message || t('WHATSAPP_TEMPLATE_MGMT.FORM.SAVE_ERROR');

const resetForm = () => {
  Object.assign(form, emptyForm());
  headerPreviewUrl.value = '';
  headerFileSize.value = 0;
  liveState.value = null;
  showErrors.value = false;
  languageTouched.value = false;
  variableMode.value = 'NAMED';
  customVariable.value = '';
  showVariableMenu.value = false;
};

const loadCapabilities = async () => {
  mediaHeaderAvailable.value = false;
  mediaHeaderReason.value = '';
  if (!form.inboxId) return;
  try {
    const { data } = await WhatsappTemplatesAPI.capabilities(form.inboxId);
    mediaHeaderAvailable.value = Boolean(data.media_header);
    mediaHeaderReason.value = data.reason || '';
  } catch {
    mediaHeaderAvailable.value = false;
  }
};

const loadLiveState = async template => {
  try {
    const { data } = await WhatsappTemplatesAPI.getTemplate(
      form.inboxId,
      template.id
    );
    liveState.value = data;
  } catch {
    liveState.value = null;
  }
};

const setDefaultLanguage = () => {
  form.language = defaultLanguage(
    currentAccount.value?.locale,
    props.templates,
    form.inboxId
  );
};

// Opens the form to create a template, or to edit `template` (a synced template of a Cloud inbox).
const open = async (template = null, prefill = null) => {
  resetForm();
  editing.value = template;
  store.dispatch('attributes/get');
  if (prefill) {
    languageTouched.value = Boolean(prefill.language);
    Object.assign(form, prefill);
    if (!form.inboxId)
      form.inboxId = props.inboxes.length === 1 ? props.inboxes[0].id : null;
  } else if (template) {
    const inbox = props.inboxes.find(item =>
      template.inboxes?.some(owner => owner.id === item.id)
    );
    Object.assign(form, formFromTemplate(template, inbox?.id));
    loadLiveState(template);
  } else {
    form.inboxId = props.inboxes.length === 1 ? props.inboxes[0].id : null;
  }
  if (!template && !languageTouched.value) setDefaultLanguage();
  variableMode.value = hasNamedVariables(form.header.text, form.body.text)
    ? 'NAMED'
    : (bodyVariables.value.length && 'POSITIONAL') || 'NAMED';
  panelRef.value?.open();
  await loadCapabilities();
};

const close = () => panelRef.value?.close();

watch(
  () => form.inboxId,
  (value, previous) => {
    if (value === previous) return;
    loadCapabilities();
    if (!isEdit.value && !languageTouched.value) setDefaultLanguage();
  }
);

watch(
  () => form.header.format,
  () => {
    form.header.handle = '';
    form.header.fileName = '';
    headerFileSize.value = 0;
    headerPreviewUrl.value = '';
  }
);

// The body variables need one example each: keep the list the same length as the variables.
watch(bodyVariables, numbers => {
  const examples = [...form.body.examples];
  while (examples.length < numbers.length) examples.push('');
  form.body.examples = examples.slice(0, Math.max(numbers.length, 0));
});

const nextNumber = computed(
  () => Math.max(0, ...variableNumbers(form.body.text)) + 1
);

const bindingLabel = binding => {
  const key = `VARIABLES.LABELS.${binding.key}`;
  const label = binding.label || (te(key) ? t(key) : binding.name);
  return `${label} (${binding.name})`;
};

// What can be put in the message with one click: the CRM / system names (and the contact's and the conversation's
// custom attributes, which the send dialog fills in by name), then the names Captain fills in for appointments; or the
// next number when the message uses numbered variables.
const variableMenuSections = computed(() => {
  if (variableMode.value === 'POSITIONAL') {
    return [
      {
        items: [
          {
            label: `{{${nextNumber.value}}}`,
            action: 'insert',
            value: String(nextNumber.value),
          },
        ],
      },
    ];
  }
  const taken = new Set(bodyVariables.value);
  const section = (group, title) => ({
    title: t(`WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_GROUPS.${title}`),
    items: bindings.value
      .filter(binding => binding.group === group && !taken.has(binding.name))
      .map(binding => ({
        label: bindingLabel(binding),
        action: 'insert',
        value: binding.name,
      })),
  });
  const known = new Set(bindings.value.map(binding => binding.name));
  const captain = {
    title: t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_GROUPS.CAPTAIN'),
    items: CAPTAIN_VARIABLES.filter(
      name => !known.has(name) && !taken.has(name)
    ).map(name => ({ label: name, action: 'insert', value: name })),
  };
  return [
    section('system', 'SYSTEM'),
    section('contact', 'CONTACT'),
    section('conversation', 'CONVERSATION'),
    captain,
  ].filter(item => item.items.length);
});

const customVariableInvalid = computed(
  () => customVariable.value && !isValidVariableName(customVariable.value)
);

// Puts {{token}} where the cursor is in the body (at the end when the field was never focused).
const insertVariable = token => {
  const field = bodyBox.value?.querySelector('textarea');
  const text = form.body.text;
  const start = field?.selectionStart ?? text.length;
  const end = field?.selectionEnd ?? text.length;
  form.body.text = `${text.slice(0, start)}{{${token}}}${text.slice(end)}`;
  showVariableMenu.value = false;
};

const addCustomVariable = () => {
  const name = customVariable.value.trim();
  if (!isValidVariableName(name)) return;
  insertVariable(name);
  customVariable.value = '';
};

const addButton = type => {
  form.buttons.push(newButton(type));
};
const removeButton = index => {
  form.buttons.splice(index, 1);
};

const chooseFile = () => fileInput.value?.click();

const onFileChosen = async event => {
  const [file] = event.target.files || [];
  event.target.value = '';
  if (!file) return;

  isUploading.value = true;
  try {
    const { data } = await WhatsappTemplatesAPI.uploadHeaderExample(
      form.inboxId,
      form.header.format,
      file
    );
    form.header.handle = data.handle;
    form.header.fileName = data.name;
    headerFileSize.value = file.size;
    if (headerPreviewUrl.value) URL.revokeObjectURL(headerPreviewUrl.value);
    headerPreviewUrl.value = URL.createObjectURL(file);
  } catch (error) {
    useAlert(apiError(error));
  } finally {
    isUploading.value = false;
  }
};

const removeFile = () => {
  form.header.handle = '';
  form.header.fileName = '';
  headerFileSize.value = 0;
  if (headerPreviewUrl.value) URL.revokeObjectURL(headerPreviewUrl.value);
  headerPreviewUrl.value = '';
};

const fileSizeLabel = computed(() => {
  const bytes = headerFileSize.value;
  if (!bytes) return '';
  return bytes >= 1024 * 1024
    ? `${(bytes / 1024 / 1024).toFixed(1)} MB`
    : `${Math.max(1, Math.round(bytes / 1024))} KB`;
});

const fileIcon = computed(
  () =>
    ({
      IMAGE: 'i-lucide-image',
      VIDEO: 'i-lucide-video',
      DOCUMENT: 'i-lucide-file-text',
    })[form.header.format] || 'i-lucide-file'
);

const chooseInbox = value => {
  if (value) form.inboxId = value;
};
const chooseLanguage = value => {
  if (!value) return;
  form.language = value;
  languageTouched.value = true;
};
const chooseHeaderFormat = value => {
  if (value) form.header.format = value;
};

const openPreview = () => previewDialogRef.value?.open();

const save = async () => {
  if (!isEdit.value) form.name = generatedName.value;
  showErrors.value = true;
  if (Object.keys(errors.value).length) return;

  isSaving.value = true;
  try {
    const payload = buildPayload(form);
    let created = null;
    if (isEdit.value) {
      await WhatsappTemplatesAPI.updateTemplate(
        form.inboxId,
        editing.value.id,
        categoryLocked.value ? { ...payload, category: undefined } : payload
      );
    } else {
      ({ data: created } = await WhatsappTemplatesAPI.createTemplate(
        form.inboxId,
        payload
      ));
    }
    useAlert(
      t(
        isEdit.value
          ? 'WHATSAPP_TEMPLATE_MGMT.FORM.UPDATED'
          : 'WHATSAPP_TEMPLATE_MGMT.FORM.CREATED'
      )
    );
    // Meta decides the final category from the wording: say so when it is not the one that was asked for.
    const assigned = String(created?.category || '').toUpperCase();
    if (assigned && assigned !== form.category) {
      useAlert(
        t('WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORY_CHANGED', {
          requested: t(
            `WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.${form.category}.LABEL`
          ),
          assigned: te(
            `WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.${assigned}.LABEL`
          )
            ? t(`WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.${assigned}.LABEL`)
            : formatTemplateLabel(assigned),
        })
      );
    }
    emit('saved');
    close();
  } catch (error) {
    useAlert(apiError(error));
  } finally {
    isSaving.value = false;
  }
};

onBeforeUnmount(() => {
  if (headerPreviewUrl.value) URL.revokeObjectURL(headerPreviewUrl.value);
});

defineExpose({ open, close });

// The combobox clears its value when the chosen option is clicked again: these fields always keep one.
const inboxOptions = computed(() =>
  props.inboxes.map(inbox => ({ value: inbox.id, label: inbox.name }))
);
const headerOptions = computed(() =>
  HEADER_FORMATS.filter(
    format => !MEDIA_FORMATS.includes(format) || mediaHeaderAvailable.value
  ).map(format => ({
    value: format,
    label: t(`WHATSAPP_TEMPLATE_MGMT.FORM.HEADER_FORMATS.${format}`),
  }))
);
const buttonChoices = computed(() =>
  BUTTON_TYPES.filter(
    type =>
      type !== 'COPY_CODE' ||
      (form.category === 'MARKETING' && !hasCopyCode.value)
  )
);
</script>

<template>
  <SidePanel
    ref="panelRef"
    width="2xl"
    :title="
      isEdit
        ? $t('WHATSAPP_TEMPLATE_MGMT.FORM.EDIT_TITLE')
        : $t('WHATSAPP_TEMPLATE_MGMT.FORM.NEW_TITLE')
    "
    :description="$t('WHATSAPP_TEMPLATE_MGMT.FORM.DESCRIPTION')"
  >
    <form class="flex flex-col gap-5" @submit.prevent="save">
      <div
        v-if="isEdit"
        class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-2"
      >
        <div class="flex flex-wrap items-center gap-2 text-sm text-n-slate-12">
          <span>{{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.STATUS') }}</span>
          <span
            class="inline-flex px-2 py-0.5 text-xs font-medium rounded-md"
            :class="templateStatusClasses(statusKey)"
          >
            {{ statusLabel }}
          </span>
          <span
            class="inline-flex px-2 py-0.5 text-xs font-medium rounded-md"
            :class="
              form.category === 'UTILITY'
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-amber-3 text-n-amber-11'
            "
            data-testid="category-chip"
          >
            {{
              $t(
                `WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.${form.category}.LABEL`
              )
            }}
          </span>
        </div>
        <p
          v-if="
            liveState?.rejected_reason && liveState.rejected_reason !== 'NONE'
          "
          class="text-sm text-n-ruby-11"
        >
          {{
            $t('WHATSAPP_TEMPLATE_MGMT.FORM.REJECTED_REASON', {
              reason: liveState.rejected_reason,
            })
          }}
        </p>
        <p v-if="!rules.canEdit" class="text-sm text-n-amber-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.CANNOT_EDIT_NOW') }}
        </p>
      </div>

      <div class="grid gap-4 sm:grid-cols-2">
        <div
          v-if="inboxes.length > 1 || visibleErrors.inboxId"
          class="grid gap-1 content-start sm:col-span-2"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL') }}
          </span>
          <ComboBox
            :model-value="form.inboxId ?? ''"
            :options="inboxOptions"
            :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL_PLACEHOLDER')"
            :disabled="isEdit"
            :has-error="Boolean(fieldError('inboxId'))"
            teleport
            data-testid="template-inbox"
            @update:model-value="chooseInbox"
          />
          <span v-if="fieldError('inboxId')" class="text-xs text-n-ruby-9">
            {{ fieldError('inboxId') }}
          </span>
        </div>
        <Input
          v-model="form.name"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.NAME')"
          :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.NAME_PLACEHOLDER')"
          :disabled="isEdit"
          :message="
            fieldError('name') ||
            (generatedName
              ? $t('WHATSAPP_TEMPLATE_MGMT.FORM.NAME_SAVED_AS', {
                  name: generatedName,
                })
              : '')
          "
          :message-type="fieldError('name') ? 'error' : 'info'"
          @blur="form.name = generatedName"
        />
        <div class="grid gap-1 content-start">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.LANGUAGE') }}
          </span>
          <ComboBox
            :model-value="form.language"
            :options="LANGUAGE_OPTIONS"
            :disabled="isEdit"
            :search-placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.LANGUAGE')"
            teleport
            data-testid="template-language"
            @update:model-value="chooseLanguage"
          />
        </div>
      </div>

      <fieldset class="grid gap-2">
        <legend class="text-sm font-medium text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORY') }}
        </legend>
        <div class="grid gap-2 sm:grid-cols-2">
          <label
            v-for="category in CATEGORIES"
            :key="category"
            class="flex items-start gap-2 p-3 rounded-lg outline outline-1 outline-n-weak"
            :class="{ 'opacity-60': categoryLocked }"
          >
            <input
              v-model="form.category"
              type="radio"
              :value="category"
              :disabled="categoryLocked"
              class="mt-1"
            />
            <span class="grid gap-0.5">
              <span class="text-sm font-medium text-n-slate-12">
                {{
                  $t(`WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.${category}.LABEL`)
                }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{
                  $t(`WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.${category}.HELP`)
                }}
              </span>
            </span>
          </label>
        </div>
        <p v-if="categoryLocked" class="text-xs text-n-amber-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORY_LOCKED') }}
        </p>
        <p
          v-if="promoWords.length"
          class="p-3 text-sm rounded-lg text-n-amber-12 bg-n-amber-3"
          data-testid="promo-warning"
        >
          {{
            $t('WHATSAPP_TEMPLATE_MGMT.FORM.PROMO_WARNING', {
              words: promoWords.join(', '),
            })
          }}
        </p>
      </fieldset>

      <div class="grid gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLES_AS') }}
        </span>
        <div class="flex flex-wrap items-center gap-2">
          <Button
            type="button"
            xs
            :slate="variableMode !== 'NAMED'"
            :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLES_NAMED')"
            data-testid="mode-named"
            @click="variableMode = 'NAMED'"
          />
          <Button
            type="button"
            xs
            :slate="variableMode !== 'POSITIONAL'"
            :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLES_POSITIONAL')"
            data-testid="mode-positional"
            @click="variableMode = 'POSITIONAL'"
          />
        </div>
        <span class="text-xs text-n-slate-11">
          {{
            variableMode === 'NAMED'
              ? $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLES_NAMED_HELP')
              : $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLES_POSITIONAL_HELP')
          }}
        </span>
      </div>

      <!-- The message as the customer will read it, edited in place -->
      <div
        class="p-4 rounded-xl bg-n-alpha-2 outline outline-1 outline-n-weak"
        data-testid="message-editor"
      >
        <div
          class="grid gap-3 p-3 rounded-lg shadow-sm bg-n-solid-1 outline outline-1 outline-n-weak"
        >
          <div class="grid gap-2">
            <ComboBox
              :model-value="form.header.format"
              :options="headerOptions"
              teleport
              data-testid="template-header-format"
              @update:model-value="chooseHeaderFormat"
            />
            <p
              v-if="!mediaHeaderAvailable"
              class="text-xs text-n-slate-11"
              data-testid="media-header-unavailable"
            >
              {{ mediaUnavailableText }}
            </p>
            <template v-if="form.header.format === 'TEXT'">
              <Input
                v-model="form.header.text"
                :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.HEADER_TEXT')"
                :message="fieldError('header.text')"
                message-type="error"
              />
              <Input
                v-if="variableTokens(form.header.text).length"
                v-model="form.header.examples[0]"
                :label="
                  $t('WHATSAPP_TEMPLATE_MGMT.FORM.EXAMPLE_FOR', {
                    n: variableTokens(form.header.text)[0],
                  })
                "
                :message="fieldError('header.example')"
                message-type="error"
              />
            </template>
            <div v-if="isMediaHeader" class="grid gap-1">
              <input
                ref="fileInput"
                type="file"
                class="hidden"
                :accept="MEDIA_ACCEPT[form.header.format]"
                @change="onFileChosen"
              />
              <div
                v-if="form.header.handle"
                class="flex items-center gap-3 p-3 rounded-lg bg-n-alpha-2"
                data-testid="file-chip"
              >
                <span
                  :class="fileIcon"
                  class="size-5 shrink-0 text-n-slate-11"
                />
                <div class="grid min-w-0">
                  <span class="text-sm truncate text-n-slate-12">
                    {{ form.header.fileName }}
                  </span>
                  <span v-if="fileSizeLabel" class="text-xs text-n-slate-11">
                    {{ fileSizeLabel }}
                  </span>
                </div>
                <div class="flex items-center gap-1 ml-auto shrink-0">
                  <Button
                    type="button"
                    ghost
                    slate
                    xs
                    :is-loading="isUploading"
                    :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANGE_FILE')"
                    @click="chooseFile"
                  />
                  <Button
                    type="button"
                    ghost
                    slate
                    xs
                    icon="i-lucide-x"
                    :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.REMOVE_FILE')"
                    data-testid="file-remove"
                    @click="removeFile"
                  />
                </div>
              </div>
              <Button
                v-else
                type="button"
                slate
                sm
                icon="i-lucide-upload"
                :is-loading="isUploading"
                :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.UPLOAD_EXAMPLE')"
                @click="chooseFile"
              />
              <span
                v-if="fieldError('header.media')"
                class="text-xs text-n-ruby-9"
              >
                {{ fieldError('header.media') }}
              </span>
            </div>
          </div>

          <div ref="bodyBox" class="grid gap-2">
            <TextArea
              v-model="form.body.text"
              :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.BODY_PLACEHOLDER')"
              :max-length="LIMITS.body"
              show-character-count
              :message="fieldError('body.text')"
              message-type="error"
            />
            <div
              class="flex flex-wrap items-start gap-2"
              data-testid="variable-picker"
            >
              <div
                v-on-click-outside="() => (showVariableMenu = false)"
                class="relative"
              >
                <Button
                  type="button"
                  slate
                  xs
                  icon="i-lucide-braces"
                  :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.ADD_VARIABLE')"
                  data-testid="variable-menu-toggle"
                  @click="showVariableMenu = !showVariableMenu"
                />
                <DropdownMenu
                  v-if="showVariableMenu"
                  :menu-sections="variableMenuSections"
                  show-search
                  :search-placeholder="
                    $t('WHATSAPP_TEMPLATE_MGMT.FORM.SEARCH_VARIABLE')
                  "
                  class="mt-1 min-w-52 max-h-64 overflow-y-auto top-full ltr:left-0 rtl:right-0"
                  @action="item => insertVariable(item.value)"
                />
              </div>
              <div
                v-if="variableMode === 'NAMED'"
                class="flex items-start gap-2"
              >
                <Input
                  v-model="customVariable"
                  size="sm"
                  :placeholder="
                    $t('WHATSAPP_TEMPLATE_MGMT.FORM.CUSTOM_VARIABLE')
                  "
                  :message="
                    customVariableInvalid
                      ? $t(
                          'WHATSAPP_TEMPLATE_MGMT.FORM.ERRORS.VARIABLE_NAME_INVALID'
                        )
                      : ''
                  "
                  message-type="error"
                  @enter="addCustomVariable"
                />
                <Button
                  type="button"
                  slate
                  sm
                  :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.ADD')"
                  :disabled="!customVariable || customVariableInvalid"
                  @click="addCustomVariable"
                />
              </div>
            </div>
          </div>

          <Input
            v-model="form.footer.text"
            :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.FOOTER_PLACEHOLDER')"
            :message="fieldError('footer.text')"
            message-type="error"
          />
        </div>

        <div class="grid gap-2 mt-2">
          <div
            v-for="(button, index) in form.buttons"
            :key="index"
            class="grid gap-2 p-3 rounded-lg bg-n-solid-1 outline outline-1 outline-n-weak"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-xs font-medium uppercase text-n-slate-11">
                {{
                  $t(`WHATSAPP_TEMPLATE_MGMT.FORM.BUTTON_TYPES.${button.type}`)
                }}
              </span>
              <Button
                type="button"
                ghost
                slate
                xs
                icon="i-lucide-trash-2"
                :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.REMOVE_BUTTON')"
                @click="removeButton(index)"
              />
            </div>
            <Input
              v-if="button.type === 'COPY_CODE'"
              v-model="button.code"
              size="sm"
              :placeholder="
                $t('WHATSAPP_TEMPLATE_MGMT.FORM.COPY_CODE_PLACEHOLDER')
              "
              :message="
                fieldError(`buttons.${index}.code`) ||
                $t('WHATSAPP_TEMPLATE_MGMT.FORM.COPY_CODE_HELP')
              "
              :message-type="
                fieldError(`buttons.${index}.code`) ? 'error' : 'info'
              "
            />
            <Input
              v-else
              v-model="button.text"
              size="sm"
              :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.BUTTON_TEXT')"
              :message="fieldError(`buttons.${index}.text`)"
              message-type="error"
            />
            <template v-if="button.type === 'URL'">
              <Input
                v-model="button.url"
                size="sm"
                placeholder="https://ejemplo.com/pedido/{{1}}"
                :message="fieldError(`buttons.${index}.url`)"
                message-type="error"
              />
              <Input
                v-if="variableNumbers(button.url).length"
                v-model="button.examples[0]"
                size="sm"
                :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.URL_EXAMPLE')"
                :message="fieldError(`buttons.${index}.example`)"
                message-type="error"
              />
            </template>
            <Input
              v-if="button.type === 'PHONE_NUMBER'"
              v-model="button.phoneNumber"
              size="sm"
              placeholder="+593999999999"
              :message="fieldError(`buttons.${index}.phone`)"
              message-type="error"
            />
          </div>
          <p
            v-if="preservedLabels.length"
            class="text-xs text-n-slate-11"
            data-testid="preserved-parts"
          >
            {{
              $t('WHATSAPP_TEMPLATE_MGMT.FORM.PRESERVED', {
                parts: preservedLabels.join(', '),
              })
            }}
          </p>
          <div class="flex flex-wrap gap-2">
            <Button
              v-for="type in buttonChoices"
              :key="type"
              type="button"
              slate
              xs
              icon="i-lucide-plus"
              :label="$t(`WHATSAPP_TEMPLATE_MGMT.FORM.BUTTON_TYPES.${type}`)"
              :disabled="form.buttons.length >= LIMITS.buttons"
              @click="addButton(type)"
            />
          </div>
          <span v-if="fieldError('buttons')" class="text-xs text-n-ruby-9">
            {{ fieldError('buttons') }}
          </span>
        </div>
      </div>

      <div
        v-if="bodyVariables.length"
        class="grid gap-2"
        data-testid="examples"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.EXAMPLES') }}
        </span>
        <div class="grid gap-2 sm:grid-cols-2">
          <Input
            v-for="(number, index) in bodyVariables"
            :key="number"
            v-model="form.body.examples[index]"
            :label="`{{${number}}}`"
            size="sm"
          />
        </div>
        <span v-if="fieldError('body.examples')" class="text-xs text-n-ruby-9">
          {{ fieldError('body.examples') }}
        </span>
      </div>

      <div class="p-3 rounded-lg bg-n-alpha-2" data-testid="meta-rules">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.RULES.TITLE') }}
        </h3>
        <ul
          class="mt-2 text-xs list-disc list-inside text-n-slate-11 grid gap-1"
        >
          <li>{{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.RULES.REVIEW') }}</li>
          <li>{{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.RULES.EDIT_LIMITS') }}</li>
          <li>{{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.RULES.CATEGORY') }}</li>
          <li>{{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.RULES.DELETE_LOCK') }}</li>
          <li>{{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.RULES.LIMIT') }}</li>
        </ul>
      </div>
    </form>

    <Dialog
      ref="previewDialogRef"
      width="md"
      :title="$t('WHATSAPP_TEMPLATE_MGMT.FORM.PREVIEW')"
      :description="$t('WHATSAPP_TEMPLATE_MGMT.FORM.PREVIEW_HELP')"
      :show-confirm-button="false"
      :cancel-button-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CLOSE')"
      overflow-y-auto
    >
      <div
        class="flex items-center justify-center px-4 py-8 border rounded-xl border-n-weak bg-n-alpha-1"
      >
        <TemplatePreview
          :template="preview"
          :variables="variables"
          :platform="PLATFORMS.WHATSAPP"
        />
      </div>
    </Dialog>

    <template #footer>
      <div class="flex gap-2">
        <Button
          type="button"
          slate
          class="flex-1"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CANCEL')"
          @click="close"
        />
        <Button
          type="button"
          slate
          class="flex-1"
          icon="i-lucide-eye"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.PREVIEW')"
          data-testid="template-preview-open"
          @click="openPreview"
        />
        <Button
          type="button"
          class="flex-1"
          :is-loading="isSaving"
          :disabled="isSaving || (isEdit && !rules.canEdit)"
          :label="
            isEdit
              ? $t('WHATSAPP_TEMPLATE_MGMT.FORM.SAVE_CHANGES')
              : $t('WHATSAPP_TEMPLATE_MGMT.FORM.CREATE')
          "
          @click="save"
        />
      </div>
    </template>
  </SidePanel>
</template>
