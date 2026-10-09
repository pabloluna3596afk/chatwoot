<script setup>
import {
  nextTick,
  computed,
  defineAsyncComponent,
  onBeforeUnmount,
  provide,
  reactive,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';

import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import { useAccount } from 'dashboard/composables/useAccount';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import Button from 'dashboard/components-next/button/Button.vue';
import TemplateComboBox from './TemplateComboBox.vue';
import VariablePicker from 'dashboard/components-next/variable-picker/VariablePicker.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
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
  copyVariableTokens,
  copyWithSystemVariables,
  suggestSystemMapping,
  systemMappingValid,
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

const formRef = ref(null);
// Bound floating pickers to the scroll viewport, leaving the fixed footer free.
provide(
  'comboboxBoundary',
  computed(() => formRef.value?.parentElement)
);

const { t, te, locale } = useI18n();
const { resolvedLocale } = useLocale();
const store = useStore();
const { currentAccount } = useAccount();
const { bindings } = useTemplateBindings('message');
const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');
const AddAttribute = defineAsyncComponent(
  () =>
    import('dashboard/routes/dashboard/settings/attributes/AddAttribute.vue')
);
const showAddAttribute = ref(false);
const closeAddAttribute = async () => {
  showAddAttribute.value = false;
  await store.dispatch('attributes/get');
};

const LANGUAGE_OPTIONS = computed(() => languageOptions(locale.value));

const panelRef = ref(null);
const previewDialogRef = ref(null);
const form = reactive(emptyForm());
const editing = ref(null);
const copySource = ref(null);
const systemMapping = reactive({});
const saveError = ref('');
const isLoading = ref(false);
const liveLoaded = ref(false);
const liveState = ref(null);
const lastUpdatedTime = computed(() => {
  const timestamp = liveState.value?.last_updated_time;
  if (!timestamp) return '';
  const date = new Date(timestamp);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat(resolvedLocale.value, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
});
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

const bindingLabel = binding => {
  const key = `VARIABLES.LABELS.${binding.key}`;
  const label = binding.label || (te(key) ? t(key) : binding.name);
  return `${label} (${binding.name})`;
};

const variableGroups = computed(() =>
  ['system', 'contact', 'conversation', 'captain'].map(key => ({
    key,
    label: t(
      `WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_GROUPS.${key.toUpperCase()}`
    ),
  }))
);
const variableOptions = computed(() => {
  const known = new Set(bindings.value.map(binding => binding.name));
  return [
    ...bindings.value.map(binding => ({
      value: binding.name,
      label: bindingLabel(binding),
      group: binding.group,
    })),
    ...CAPTAIN_VARIABLES.filter(name => !known.has(name)).map(name => ({
      value: name,
      label: name,
      group: 'captain',
    })),
  ];
});

const isEdit = computed(() => Boolean(editing.value));
const mappedForm = computed(() =>
  copySource.value ? copyWithSystemVariables(form, systemMapping) : form
);
const errors = computed(() => {
  const mappingReady =
    !copySource.value ||
    systemMappingValid(
      form,
      systemMapping,
      variableOptions.value.map(option => option.value)
    );
  const result = validateForm(mappingReady ? mappedForm.value : form, {
    isEdit: isEdit.value,
    original: editing.value,
  });
  if (!mappingReady) result.mapping = 'SYSTEM_MAPPING_REQUIRED';
  if (copySource.value && form.name === copySource.value.name)
    result.name = 'COPY_NAME_REQUIRED';
  return result;
});
const variableLabel = token => `{{${token}}}`;
const mappingTokens = computed(() =>
  copySource.value ? copyVariableTokens(form) : []
);
const hasOriginalComponent = type =>
  editing.value?.components?.some(component => component.type === type);
const visibleErrors = computed(() => (showErrors.value ? errors.value : {}));
const rules = computed(() =>
  editRules(liveState.value?.status || editing.value?.status)
);
const categoryLocked = computed(
  () => isEdit.value && rules.value.categoryLocked
);
const isMediaHeader = computed(() =>
  MEDIA_FORMATS.includes(form.header.format)
);
const bodyVariables = computed(() => variableTokens(form.body.text));
const generatedName = computed(() => toSnakeCase(form.name));
const preview = computed(() =>
  previewTemplate(mappedForm.value, headerPreviewUrl.value)
);
const variables = computed(() => previewVariables(mappedForm.value));
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

const apiError = error => {
  const data = error?.response?.data;
  const texts = [
    ...new Set([data?.error_user_msg, data?.message].filter(Boolean)),
  ].join(' \u2014 ');
  return texts
    ? t('WHATSAPP_TEMPLATE_MGMT.FORM.META_ERROR', { message: texts })
    : t('WHATSAPP_TEMPLATE_MGMT.FORM.SAVE_ERROR');
};

const resetForm = () => {
  delete form.parameterFormat;
  Object.assign(form, emptyForm());
  copySource.value = null;
  Object.keys(systemMapping).forEach(key => delete systemMapping[key]);
  saveError.value = '';
  liveLoaded.value = false;
  headerPreviewUrl.value = '';
  headerFileSize.value = 0;
  liveState.value = null;
  showErrors.value = false;
  languageTouched.value = false;
  variableMode.value = 'NAMED';
  customVariable.value = '';
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
    editing.value = { ...template, ...data };
    Object.assign(form, formFromTemplate(editing.value, form.inboxId));
    liveLoaded.value = true;
  } catch (error) {
    saveError.value = apiError(error);
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
  isLoading.value = true;
  resetForm();
  editing.value = template;
  panelRef.value?.open();
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
    await loadLiveState(template);
  } else {
    form.inboxId = props.inboxes.length === 1 ? props.inboxes[0].id : null;
  }
  if (!template && !languageTouched.value) setDefaultLanguage();
  variableMode.value =
    form.parameterFormat ||
    (hasNamedVariables(form.header.text, form.body.text)
      ? 'NAMED'
      : (bodyVariables.value.length && 'POSITIONAL') || 'NAMED');
  panelRef.value?.open();
  await nextTick();
  isLoading.value = false;
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

// The body variables need one example each: keep the list the same length as the variables.
watch(bodyVariables, numbers => {
  if (isEdit.value) return;
  const examples = [...form.body.examples];
  while (examples.length < numbers.length) examples.push('');
  form.body.examples = examples.slice(0, Math.max(numbers.length, 0));
});

const nextNumber = computed(
  () => Math.max(0, ...variableNumbers(form.body.text)) + 1
);

// What can be put in the message with one click: the CRM / system names (and the contact's and the conversation's
// custom attributes, which the send dialog fills in by name), then the names Captain fills in for appointments; or the
// next number when the message uses numbered variables.
const insertionOptions = computed(() => {
  if (variableMode.value === 'POSITIONAL') {
    return [
      { value: String(nextNumber.value), label: `{{${nextNumber.value}}}` },
    ];
  }
  const taken = new Set(bodyVariables.value);
  return variableOptions.value.filter(option => !taken.has(option.value));
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
  if (!value || isEdit.value) return;
  form.header.format = value;
  removeFile();
};

const openPreview = () => previewDialogRef.value?.open();

const save = async () => {
  if (
    isLoading.value ||
    (isEdit.value && (!liveLoaded.value || !rules.value.canEdit))
  )
    return;
  saveError.value = '';
  if (!isEdit.value) form.name = generatedName.value;
  showErrors.value = true;
  if (Object.keys(errors.value).length) return;

  isSaving.value = true;
  try {
    const payload = buildPayload(mappedForm.value);
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
    saveError.value = apiError(error);
  } finally {
    isSaving.value = false;
  }
};

onBeforeUnmount(() => {
  if (headerPreviewUrl.value) URL.revokeObjectURL(headerPreviewUrl.value);
});

const openSystemCopy = async template => {
  const inbox = props.inboxes.find(item =>
    template.inboxes?.some(owner => owner.id === item.id)
  );
  const prefill = formFromTemplate(template, inbox?.id || form.inboxId);
  prefill.name = `${template.name.slice(0, 509)}_v2`;
  await open(null, prefill);
  copySource.value = template;
  Object.assign(systemMapping, suggestSystemMapping(form));
  variableMode.value = 'NAMED';
};

defineExpose({ open, close, openSystemCopy });

// The combobox clears its value when the chosen option is clicked again: these fields always keep one.
const inboxOptions = computed(() =>
  props.inboxes.map(inbox => ({ value: inbox.id, label: inbox.name }))
);
const headerOptions = computed(() =>
  HEADER_FORMATS.filter(
    format =>
      format === form.header.format ||
      !MEDIA_FORMATS.includes(format) ||
      mediaHeaderAvailable.value
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
    :description="isEdit ? '' : $t('WHATSAPP_TEMPLATE_MGMT.FORM.DESCRIPTION')"
  >
    <p v-if="isLoading" class="text-sm text-n-slate-11" role="status">
      {{ $t('WHATSAPP_TEMPLATE_MGMT.LOADING') }}
    </p>
    <form
      v-else
      ref="formRef"
      class="flex flex-col gap-5"
      @submit.prevent="save"
    >
      <p
        v-if="saveError"
        role="alert"
        class="p-3 rounded-lg bg-n-ruby-3 text-sm text-n-ruby-11 break-words"
        data-testid="meta-error"
      >
        {{ saveError }}
      </p>
      <p
        v-if="visibleErrors.structure"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ fieldError('structure') }}
      </p>
      <div
        v-if="copySource"
        class="grid gap-3 p-3 rounded-lg border border-n-weak"
        data-testid="system-copy"
      >
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.SYSTEM_COPY') }}
        </h3>
        <p class="text-xs text-n-slate-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.SYSTEM_COPY_HELP') }}
        </p>
        <div v-for="token in mappingTokens" :key="token" class="grid gap-1">
          <span class="text-sm text-n-slate-12">{{
            variableLabel(token)
          }}</span>
          <VariablePicker
            mode="read"
            :aria-label="
              $t('WHATSAPP_TEMPLATE_MGMT.FORM.MAP_VARIABLE') +
              ' ' +
              variableLabel(token)
            "
            :model-value="systemMapping[token] || ''"
            :data-testid="`map-variable-${token}`"
            @update:model-value="value => (systemMapping[token] = value)"
          />
        </div>
        <p
          v-if="fieldError('mapping')"
          role="alert"
          class="text-xs text-n-ruby-11"
        >
          {{ fieldError('mapping') }}
        </p>
      </div>
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
        <p
          v-if="statusKey === 'APPROVED'"
          class="text-xs text-n-amber-11"
          data-testid="approved-warning"
        >
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.APPROVED_WARNING') }}
        </p>
        <p v-if="lastUpdatedTime" class="text-xs text-n-slate-11">
          {{
            $t('WHATSAPP_TEMPLATE_MGMT.FORM.LAST_EDIT', {
              time: lastUpdatedTime,
            })
          }}
        </p>
        <p class="text-xs text-n-slate-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.EDIT_STRUCTURE_HELP') }}
        </p>
        <Button
          v-if="form.parameterFormat === 'POSITIONAL' && liveLoaded"
          type="button"
          slate
          outline
          sm
          :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.SYSTEM_COPY')"
          data-testid="system-copy-open"
          @click="openSystemCopy(editing)"
        />
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
          <TemplateComboBox
            :model-value="form.inboxId ?? ''"
            :options="inboxOptions"
            :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL_PLACEHOLDER')"
            :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL')"
            :search-placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL')"
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
            (!isEdit && generatedName
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
          <TemplateComboBox
            :model-value="form.language"
            :options="LANGUAGE_OPTIONS"
            :disabled="isEdit"
            :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.LANGUAGE')"
            :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.LANGUAGE')"
            show-search
            :search-placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.LANGUAGE')"
            teleport
            data-testid="template-language"
            @update:model-value="chooseLanguage"
          />
        </div>
      </div>

      <fieldset v-if="!categoryLocked" class="grid gap-2">
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

      <div v-if="!isEdit && !copySource" class="grid gap-1">
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
          <div
            v-if="!isEdit || hasOriginalComponent('HEADER')"
            class="grid gap-2"
          >
            <TemplateComboBox
              :disabled="isEdit"
              :model-value="form.header.format"
              :options="headerOptions"
              :placeholder="
                $t('WHATSAPP_TEMPLATE_MGMT.FORM.HEADER_FORMATS.NONE')
              "
              :aria-label="
                $t('WHATSAPP_TEMPLATE_MGMT.FORM.HEADER_FORMATS.NONE')
              "
              teleport
              data-testid="template-header-format"
              @update:model-value="chooseHeaderFormat"
            />
            <p
              v-if="!isEdit && !mediaHeaderAvailable"
              class="text-xs text-n-slate-11"
              data-testid="media-header-unavailable"
            >
              {{ mediaUnavailableText }}
            </p>
            <template v-if="form.header.format === 'TEXT'">
              <Input
                :model-value="mappedForm.header.text"
                :disabled="Boolean(copySource)"
                :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.HEADER_TEXT')"
                :message="fieldError('header.text')"
                :message-type="fieldError('header.text') ? 'error' : 'info'"
                @update:model-value="value => (form.header.text = value)"
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
                :message-type="fieldError('header.example') ? 'error' : 'info'"
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
              :model-value="mappedForm.body.text"
              :disabled="Boolean(copySource)"
              :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.BODY_PLACEHOLDER')"
              :max-length="LIMITS.body"
              show-character-count
              :message="fieldError('body.text')"
              :message-type="fieldError('body.text') ? 'error' : 'info'"
              @update:model-value="value => (form.body.text = value)"
            />
            <div
              v-if="!isEdit && !copySource"
              class="flex flex-wrap items-start gap-2"
              data-testid="variable-picker"
            >
              <TemplateComboBox
                model-value=""
                :options="insertionOptions"
                :groups="variableMode === 'NAMED' ? variableGroups : []"
                :show-search="variableMode === 'NAMED'"
                :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.ADD_VARIABLE')"
                :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.ADD_VARIABLE')"
                :search-placeholder="
                  $t('WHATSAPP_TEMPLATE_MGMT.FORM.SEARCH_VARIABLE')
                "
                :show-create-attribute="isAdmin && variableMode === 'NAMED'"
                data-testid="variable-menu-toggle"
                @create-attribute="showAddAttribute = true"
                @update:model-value="insertVariable"
              />
              <div
                v-if="!isEdit && !copySource && variableMode === 'NAMED'"
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
                  :message-type="customVariableInvalid ? 'error' : 'info'"
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
            v-if="!isEdit || hasOriginalComponent('FOOTER')"
            v-model="form.footer.text"
            :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.FOOTER_PLACEHOLDER')"
            :message="fieldError('footer.text')"
            :message-type="fieldError('footer.text') ? 'error' : 'info'"
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
                :disabled="isEdit"
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
              :message-type="
                fieldError(`buttons.${index}.text`) ? 'error' : 'info'
              "
            />
            <template v-if="button.type === 'URL'">
              <Input
                :model-value="mappedForm.buttons[index].url"
                :disabled="Boolean(copySource)"
                size="sm"
                placeholder="https://ejemplo.com/pedido/{{1}}"
                :message="fieldError(`buttons.${index}.url`)"
                :message-type="
                  fieldError(`buttons.${index}.url`) ? 'error' : 'info'
                "
                @update:model-value="value => (button.url = value)"
              />
              <Input
                v-if="variableTokens(button.url).length"
                v-model="button.examples[0]"
                size="sm"
                :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.URL_EXAMPLE')"
                :message="fieldError(`buttons.${index}.example`)"
                :message-type="
                  fieldError(`buttons.${index}.example`) ? 'error' : 'info'
                "
              />
            </template>
            <Input
              v-if="button.type === 'PHONE_NUMBER'"
              v-model="button.phoneNumber"
              size="sm"
              placeholder="+593999999999"
              :message="fieldError(`buttons.${index}.phone`)"
              :message-type="
                fieldError(`buttons.${index}.phone`) ? 'error' : 'info'
              "
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
          <div v-if="!isEdit" class="flex flex-wrap gap-2">
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
            :label="`{{${copySource ? systemMapping[number] || number : number}}}`"
            size="sm"
          />
        </div>
        <span v-if="fieldError('body.examples')" class="text-xs text-n-ruby-9">
          {{ fieldError('body.examples') }}
        </span>
      </div>

      <div
        v-if="!isEdit && !copySource"
        class="p-3 rounded-lg bg-n-alpha-2"
        data-testid="meta-rules"
      >
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
          outline
          class="flex-1"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CANCEL')"
          @click="close"
        />
        <Button
          type="button"
          slate
          outline
          class="flex-1"
          icon="i-lucide-eye"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.PREVIEW')"
          data-testid="template-preview-open"
          @click="openPreview"
        />
        <Button
          type="button"
          class="flex-1"
          outline
          :is-loading="isSaving"
          :disabled="
            isSaving || isLoading || (isEdit && (!liveLoaded || !rules.canEdit))
          "
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
  <AddAttribute
    v-if="showAddAttribute"
    :selected-attribute-model-tab="1"
    :on-close="closeAddAttribute"
  />
</template>
