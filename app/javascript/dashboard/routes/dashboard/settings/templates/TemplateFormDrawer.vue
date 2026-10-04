<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import Button from 'dashboard/components-next/button/Button.vue';
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
  buildPayload,
  editRules,
  emptyForm,
  formFromTemplate,
  newButton,
  previewTemplate,
  previewVariables,
  toSnakeCase,
  validateForm,
  SUGGESTED_VARIABLES,
  isValidVariableName,
  variableNumbers,
  variableTokens,
} from './templateForm';
import { formatTemplateLabel, templateStatusClasses } from './templateUtils';

const props = defineProps({
  // The WhatsApp Cloud inboxes the template can be created in.
  inboxes: { type: Array, default: () => [] },
});

const emit = defineEmits(['saved']);

const { t, te } = useI18n();

const LANGUAGES = ['es', 'es_MX', 'es_AR', 'es_ES', 'en', 'en_US', 'pt_BR'];

const panelRef = ref(null);
const form = reactive(emptyForm());
const editing = ref(null);
const liveState = ref(null);
const showErrors = ref(false);
const isSaving = ref(false);
const isUploading = ref(false);
const mediaHeaderAvailable = ref(false);
const headerPreviewUrl = ref('');
const fileInput = ref(null);

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
const headerHasVariable = computed(
  () => variableTokens(form.header.text).length > 0
);
const generatedName = computed(() => toSnakeCase(form.name));
const preview = computed(() => previewTemplate(form, headerPreviewUrl.value));
const variables = computed(() => previewVariables(form));
const statusKey = computed(() =>
  String(liveState.value?.status || editing.value?.status || '').toUpperCase()
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
  });
};
const fieldError = path => errorText(visibleErrors.value[path]);

const statusLabel = computed(() => {
  const key = statusKey.value;
  return te(`WHATSAPP_TEMPLATE_MGMT.STATUS.${key}`)
    ? t(`WHATSAPP_TEMPLATE_MGMT.STATUS.${key}`)
    : formatTemplateLabel(key);
});

const apiError = error =>
  error?.response?.data?.message || t('WHATSAPP_TEMPLATE_MGMT.FORM.SAVE_ERROR');

const resetForm = () => {
  Object.assign(form, emptyForm());
  headerPreviewUrl.value = '';
  liveState.value = null;
  showErrors.value = false;
};

const loadCapabilities = async () => {
  mediaHeaderAvailable.value = false;
  if (!form.inboxId) return;
  try {
    const { data } = await WhatsappTemplatesAPI.capabilities(form.inboxId);
    mediaHeaderAvailable.value = Boolean(data.media_header);
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

// Opens the form to create a template, or to edit `template` (a synced template of a Cloud inbox).
const open = async (template = null, prefill = null) => {
  resetForm();
  editing.value = template;
  if (prefill) {
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
  panelRef.value?.open();
  await loadCapabilities();
};

const close = () => panelRef.value?.close();

watch(
  () => form.inboxId,
  (value, previous) => {
    if (value !== previous) loadCapabilities();
  }
);

watch(
  () => form.header.format,
  () => {
    form.header.handle = '';
    form.header.fileName = '';
    headerPreviewUrl.value = '';
  }
);

// The body variables need one example each: keep the list the same length as the variables.
watch(bodyVariables, numbers => {
  const examples = [...form.body.examples];
  while (examples.length < numbers.length) examples.push('');
  form.body.examples = examples.slice(0, Math.max(numbers.length, 0));
});

// Named variables ({{nombre}}) are added at the end of the body; the ones already in it are not offered again.
const customVariable = ref('');
const offeredVariables = computed(() =>
  SUGGESTED_VARIABLES.filter(name => !bodyVariables.value.includes(name))
);
const customVariableInvalid = computed(
  () => customVariable.value && !isValidVariableName(customVariable.value)
);

const addVariable = name => {
  form.body.text = `${form.body.text}{{${name}}}`;
};

const addCustomVariable = () => {
  const name = customVariable.value.trim();
  if (!isValidVariableName(name)) return;
  addVariable(name);
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
    if (headerPreviewUrl.value) URL.revokeObjectURL(headerPreviewUrl.value);
    headerPreviewUrl.value = URL.createObjectURL(file);
  } catch (error) {
    useAlert(apiError(error));
  } finally {
    isUploading.value = false;
  }
};

const save = async () => {
  if (!isEdit.value) form.name = generatedName.value;
  showErrors.value = true;
  if (Object.keys(errors.value).length) return;

  isSaving.value = true;
  try {
    const payload = buildPayload(form);
    if (isEdit.value) {
      await WhatsappTemplatesAPI.updateTemplate(
        form.inboxId,
        editing.value.id,
        categoryLocked.value ? { ...payload, category: undefined } : payload
      );
    } else {
      await WhatsappTemplatesAPI.createTemplate(form.inboxId, payload);
    }
    useAlert(
      t(
        isEdit.value
          ? 'WHATSAPP_TEMPLATE_MGMT.FORM.UPDATED'
          : 'WHATSAPP_TEMPLATE_MGMT.FORM.CREATED'
      )
    );
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

const selectClass =
  'w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-black2 text-n-slate-12 outline outline-1 outline-n-weak disabled:opacity-60';
</script>

<template>
  <SidePanel
    ref="panelRef"
    width="3xl"
    :title="
      isEdit
        ? $t('WHATSAPP_TEMPLATE_MGMT.FORM.EDIT_TITLE')
        : $t('WHATSAPP_TEMPLATE_MGMT.FORM.NEW_TITLE')
    "
    :description="$t('WHATSAPP_TEMPLATE_MGMT.FORM.DESCRIPTION')"
  >
    <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
      <form class="flex flex-col gap-5" @submit.prevent="save">
        <div
          v-if="isEdit"
          class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-2"
        >
          <div class="flex items-center gap-2 text-sm text-n-slate-12">
            <span>{{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.STATUS') }}</span>
            <span
              class="inline-flex px-2 py-0.5 text-xs font-medium rounded-md"
              :class="templateStatusClasses(statusKey)"
            >
              {{ statusLabel }}
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

        <label
          v-if="inboxes.length > 1 || visibleErrors.inboxId"
          class="grid gap-1"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL') }}
          </span>
          <select
            v-model="form.inboxId"
            :class="selectClass"
            :disabled="isEdit"
          >
            <option :value="null" disabled>
              {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL_PLACEHOLDER') }}
            </option>
            <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
              {{ inbox.name }}
            </option>
          </select>
          <span v-if="fieldError('inboxId')" class="text-xs text-n-ruby-9">
            {{ fieldError('inboxId') }}
          </span>
        </label>

        <div class="grid gap-4 sm:grid-cols-2">
          <div class="grid gap-1">
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
          </div>
          <label class="grid gap-1 content-start">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.LANGUAGE') }}
            </span>
            <select
              v-model="form.language"
              :class="selectClass"
              :disabled="isEdit"
            >
              <option v-for="code in LANGUAGES" :key="code" :value="code">
                {{ $t(`WHATSAPP_TEMPLATE_MGMT.FORM.LANGUAGES.${code}`) }}
              </option>
            </select>
          </label>
        </div>

        <fieldset class="grid gap-2">
          <legend class="text-sm font-medium text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORY') }}
          </legend>
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
          <p v-if="categoryLocked" class="text-xs text-n-amber-11">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORY_LOCKED') }}
          </p>
        </fieldset>

        <div class="grid gap-3">
          <label class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.HEADER') }}
            </span>
            <select v-model="form.header.format" :class="selectClass">
              <option
                v-for="format in HEADER_FORMATS"
                :key="format"
                :value="format"
                :disabled="
                  MEDIA_FORMATS.includes(format) && !mediaHeaderAvailable
                "
              >
                {{ $t(`WHATSAPP_TEMPLATE_MGMT.FORM.HEADER_FORMATS.${format}`) }}
              </option>
            </select>
          </label>
          <p
            v-if="!mediaHeaderAvailable"
            class="text-xs text-n-slate-11"
            data-testid="media-header-unavailable"
          >
            {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.MEDIA_HEADER_UNAVAILABLE') }}
          </p>
          <template v-if="form.header.format === 'TEXT'">
            <Input
              v-model="form.header.text"
              :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.HEADER_TEXT')"
              :message="fieldError('header.text')"
              message-type="error"
            />
            <Input
              v-if="headerHasVariable"
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
          <div v-if="isMediaHeader" class="flex flex-wrap items-center gap-3">
            <input
              ref="fileInput"
              type="file"
              class="hidden"
              :accept="MEDIA_ACCEPT[form.header.format]"
              @change="onFileChosen"
            />
            <Button
              type="button"
              slate
              sm
              icon="i-lucide-upload"
              :is-loading="isUploading"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.UPLOAD_EXAMPLE')"
              @click="chooseFile"
            />
            <span v-if="form.header.fileName" class="text-sm text-n-slate-11">
              {{ form.header.fileName }}
            </span>
            <span
              v-if="fieldError('header.media')"
              class="text-xs text-n-ruby-9"
            >
              {{ fieldError('header.media') }}
            </span>
          </div>
        </div>

        <div class="grid gap-2">
          <TextArea
            v-model="form.body.text"
            :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.BODY')"
            :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.BODY_PLACEHOLDER')"
            :max-length="LIMITS.body"
            show-character-count
            :message="fieldError('body.text')"
            message-type="error"
          />
          <div class="grid gap-2" data-testid="variable-picker">
            <span class="text-xs text-n-slate-11">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.ADD_VARIABLE') }}
            </span>
            <div class="flex flex-wrap items-center gap-2">
              <Button
                v-for="name in offeredVariables"
                :key="name"
                type="button"
                slate
                xs
                icon="i-lucide-plus"
                :label="name"
                :data-testid="`add-variable-${name}`"
                @click="addVariable(name)"
              />
            </div>
            <div class="flex items-start gap-2">
              <Input
                v-model="customVariable"
                size="sm"
                class="flex-1"
                :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CUSTOM_VARIABLE')"
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
          <div v-if="bodyVariables.length" class="grid gap-2">
            <Input
              v-for="(number, index) in bodyVariables"
              :key="number"
              v-model="form.body.examples[index]"
              :label="
                $t('WHATSAPP_TEMPLATE_MGMT.FORM.EXAMPLE_FOR', { n: number })
              "
              size="sm"
            />
            <span
              v-if="fieldError('body.examples')"
              class="text-xs text-n-ruby-9"
            >
              {{ fieldError('body.examples') }}
            </span>
          </div>
        </div>

        <Input
          v-model="form.footer.text"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.FOOTER')"
          :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.FOOTER_PLACEHOLDER')"
          :message="fieldError('footer.text')"
          message-type="error"
        />

        <div class="grid gap-3">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.BUTTONS') }}
          </span>
          <div
            v-for="(button, index) in form.buttons"
            :key="index"
            class="grid gap-2 p-3 rounded-lg outline outline-1 outline-n-weak"
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
          <div class="flex flex-wrap gap-2">
            <Button
              v-for="type in BUTTON_TYPES"
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
      </form>

      <aside class="flex flex-col gap-4">
        <div
          class="flex items-center justify-center px-4 py-8 border rounded-xl border-n-weak bg-n-alpha-1"
        >
          <TemplatePreview
            :template="preview"
            :variables="variables"
            :platform="PLATFORMS.WHATSAPP"
          />
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
      </aside>
    </div>

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
