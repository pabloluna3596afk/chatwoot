<script setup>
/**
 * This component handles parsing and sending WhatsApp message templates.
 * It works as follows:
 * 1. Displays the template text with variable placeholders.
 * 2. Generates input fields for each variable in the template.
 * 3. Validates that all variables are filled before sending.
 * 4. Replaces placeholders with user-provided values.
 * 5. Emits events to send the processed message or reset the template.
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { requiredIf } from '@vuelidate/validators';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import InboxesAPI from 'dashboard/api/inboxes';

import { isWhatsAppComplete } from '@chatwoot/utils';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import {
  headerMediaAccept,
  headerMediaMaxMegabytes,
  isUploadedHeaderMedia,
  UPLOADED_MEDIA_KEYS,
  validateHeaderMediaFile,
  withoutUploadedMedia,
} from 'dashboard/helper/templateHeaderMedia';
import InsertVariableButton from 'dashboard/components-next/variable/InsertVariableButton.vue';
import { resolveLiquid } from 'dashboard/helper/templateVariableBindings';
import {
  buildTemplateParameters,
  buildTemplateButtonsSnapshot,
  allKeysRequired,
  DEFAULT_LANGUAGE,
  DEFAULT_CATEGORY,
  COMPONENT_TYPES,
  MEDIA_FORMATS,
  findComponentByType,
  renderTemplatePreview,
} from 'dashboard/helper/templateHelper';

const props = defineProps({
  template: {
    type: Object,
    default: () => ({}),
    validator: value => {
      if (!value || typeof value !== 'object') return false;
      if (!value.components || !Array.isArray(value.components)) return false;
      return true;
    },
  },
  sendRenderedContent: {
    type: Boolean,
    default: false,
  },
  // The values already chosen ({ body: { 1: '...' }, header: { ... } }), e.g. the ones a Captain setting saved.
  modelValue: {
    type: Object,
    default: null,
  },
  // Variables the owner can insert into each field, as { key, label, description }; with none there is no button.
  variableOptions: {
    type: Array,
    default: () => [],
  },
  // The text a variable starts with when nothing was saved for it, by the variable's name
  // ({ nombre: '{{ contact.name }}' }): a named template picked in a Captain setting fills itself in.
  defaultValues: {
    type: Object,
    default: () => ({}),
  },
  // The records the Liquid of a default value is resolved with ({ contact, conversation, agent }): the field then
  // shows the value ("Ana") and the Liquid is what is sent while the agent leaves it alone. With none, the field
  // shows the Liquid itself.
  resolveContext: {
    type: Object,
    default: null,
  },
  // What each variable key is worth in the preview ({ 'appointment.date': 'jueves 1 de octubre' }), so the preview
  // shows sample values and not the raw {{ variable }}.
  previewValues: {
    type: Object,
    default: null,
  },
  // The inbox whose number uploads the header file. With none, or when it is not a WhatsApp Cloud inbox, only the
  // link can be given.
  mediaInboxId: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits([
  'sendMessage',
  'resetTemplate',
  'back',
  'update:modelValue',
]);

const { t } = useI18n();

const processedParams = ref({});
// The fields the agent typed in: the others keep the Liquid they started with.
const edited = ref({});

const languageLabel = computed(() => {
  return `${t('WHATSAPP_TEMPLATES.PARSER.LANGUAGE')}: ${props.template.language || DEFAULT_LANGUAGE}`;
});

const categoryLabel = computed(() => {
  return `${t('WHATSAPP_TEMPLATES.PARSER.CATEGORY')}: ${t(`WHATSAPP_TEMPLATES.SEND_CENTER.CATEGORY.${props.template.category || DEFAULT_CATEGORY}`)}`;
});

const headerComponent = computed(() => {
  return findComponentByType(props.template, COMPONENT_TYPES.HEADER);
});

const bodyComponent = computed(() => {
  return findComponentByType(props.template, COMPONENT_TYPES.BODY);
});

const bodyText = computed(() => {
  return bodyComponent.value?.text || '';
});

const headerText = computed(() => {
  return headerComponent.value?.format === 'TEXT'
    ? headerComponent.value?.text || ''
    : '';
});

const hasMediaHeader = computed(() =>
  MEDIA_FORMATS.includes(headerComponent.value?.format)
);

const formatType = computed(() => {
  const format = headerComponent.value?.format;
  return format ? format.charAt(0) + format.slice(1).toLowerCase() : '';
});

const isDocumentTemplate = computed(() => {
  return headerComponent.value?.format?.toLowerCase() === 'document';
});

const hasBodyVariables = computed(() => {
  return bodyText.value?.match(/{{([^}]+)}}/g) !== null;
});

const hasTextHeaderVariables = computed(() => {
  return headerText.value?.match(/{{([^}]+)}}/g) !== null;
});

const hasVariables = computed(
  () => hasBodyVariables.value || hasTextHeaderVariables.value
);

const LIQUID_VARIABLE = /{{\s*([\w.]+)\s*}}/g;

// With preview values, {{ contact.name }} in a field shows its sample ("Ana Pérez") in the preview.
const withSamples = values =>
  Object.fromEntries(
    Object.entries(values || {}).map(([key, value]) => [
      key,
      props.previewValues
        ? String(value ?? '').replace(
            LIQUID_VARIABLE,
            (match, name) => props.previewValues[name] ?? match
          )
        : value,
    ])
  );

// What a field shows: the value of an untouched default (its Liquid resolved for this contact), else what is stored.
const displayValue = (component, key) => {
  const value = processedParams.value[component]?.[key] ?? '';
  if (!props.resolveContext || edited.value[`${component}.${key}`])
    return value;
  const resolved = resolveLiquid(value, props.resolveContext);
  return resolved === undefined ? value : resolved;
};

const setValue = (component, key, value) => {
  processedParams.value[component][key] = value;
  edited.value[`${component}.${key}`] = true;
};

const displayed = component =>
  Object.fromEntries(
    Object.keys(processedParams.value[component] || {}).map(key => [
      key,
      displayValue(component, key),
    ])
  );

const renderedHeader = computed(() => {
  return renderTemplatePreview(
    headerText.value,
    withSamples(displayed('header'))
  );
});

const renderedTemplate = computed(() => {
  return renderTemplatePreview(bodyText.value, withSamples(displayed('body')));
});

// Completeness validation is shared with the mobile app via @chatwoot/utils.
const isFormInvalid = computed(
  () => !isWhatsAppComplete(props.template, processedParams.value)
);

const v$ = useVuelidate(
  {
    processedParams: {
      requiredIfKeysPresent: requiredIf(hasVariables),
      allKeysRequired,
    },
  },
  { processedParams }
);

// A default whose value is empty for this contact (no email) is not filled in: the agent has to type it.
const defaultFor = liquid => {
  const resolved = props.resolveContext
    ? resolveLiquid(liquid, props.resolveContext)
    : undefined;
  return resolved === '' ? '' : liquid;
};

const initializeTemplateParameters = () => {
  edited.value = {};
  const built = buildTemplateParameters(props.template);
  ['header', 'body'].forEach(component => {
    Object.keys(built[component] || {}).forEach(key => {
      const saved = props.modelValue?.[component]?.[key];
      if (saved !== undefined) built[component][key] = saved;
      else if (!built[component][key] && props.defaultValues[key])
        built[component][key] = defaultFor(props.defaultValues[key]);
    });
  });
  // The uploaded header file travels with the saved values (it is not one of the template's own keys).
  UPLOADED_MEDIA_KEYS.forEach(key => {
    const saved = props.modelValue?.header?.[key];
    if (saved !== undefined && built.header) built.header[key] = saved;
  });
  processedParams.value = built;
};

const insertVariable = (component, key, liquid) => {
  const current = processedParams.value[component][key] || '';
  processedParams.value[component][key] =
    `${current}${current ? ' ' : ''}${liquid}`;
};

const updateMediaUrl = value => {
  // A link typed by hand replaces the uploaded file.
  processedParams.value.header = {
    ...withoutUploadedMedia(processedParams.value.header),
    media_url: value,
  };
};

const getInboxById = useMapGetter('inboxes/getInboxById');
const canUploadMedia = computed(
  () =>
    hasMediaHeader.value &&
    !!props.mediaInboxId &&
    getInboxById.value(props.mediaInboxId)?.provider === 'whatsapp_cloud'
);

const mediaFileInput = ref(null);
const isUploadingMedia = ref(false);
const mediaError = ref('');
const uploadedMedia = computed(() =>
  isUploadedHeaderMedia(processedParams.value.header)
    ? processedParams.value.header
    : null
);
const isImageUpload = computed(
  () => uploadedMedia.value && uploadedMedia.value.media_type === 'image'
);
const mediaLimitsHint = computed(() => {
  const format = headerComponent.value?.format?.toUpperCase();
  return t(`WHATSAPP_TEMPLATES.PARSER.MEDIA_HINT_${format}`, {
    max: headerMediaMaxMegabytes(format),
  });
});

const chooseMediaFile = () => mediaFileInput.value?.click();

const uploadMedia = async file => {
  const format = headerComponent.value?.format;
  mediaError.value = '';
  const invalid = validateHeaderMediaFile(format, file);
  if (invalid) {
    mediaError.value = t(`WHATSAPP_TEMPLATES.PARSER.MEDIA_ERROR_${invalid}`, {
      max: headerMediaMaxMegabytes(format),
    });
    return;
  }
  isUploadingMedia.value = true;
  try {
    const { data } = await InboxesAPI.uploadTemplateMedia(props.mediaInboxId, {
      format: format.toUpperCase(),
      file,
    });
    processedParams.value.header = {
      ...processedParams.value.header,
      ...data,
    };
  } catch (error) {
    const reason = error?.response?.data?.error;
    const known = ['invalid_type', 'too_large', 'empty'].includes(reason);
    mediaError.value = t(
      `WHATSAPP_TEMPLATES.PARSER.MEDIA_ERROR_${known ? reason.toUpperCase() : 'UPLOAD_FAILED'}`,
      { max: headerMediaMaxMegabytes(format) }
    );
  } finally {
    isUploadingMedia.value = false;
  }
};

const onMediaFileChange = event => {
  const [file] = event.target.files || [];
  event.target.value = '';
  if (file) uploadMedia(file);
};

const removeUploadedMedia = () => {
  mediaError.value = '';
  processedParams.value.header = {
    ...withoutUploadedMedia(processedParams.value.header),
    media_url: '',
    media_name: '',
  };
};

const updateMediaName = value => {
  processedParams.value.header ??= {};
  processedParams.value.header.media_name = value;
};

const sendMessage = () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  const { name, category, language, namespace } = props.template;
  const templateButtons = buildTemplateButtonsSnapshot(
    props.template,
    processedParams.value
  );

  const payload = {
    message: props.sendRenderedContent
      ? renderedTemplate.value
      : bodyText.value,
    pendingMessageContent: renderedTemplate.value,
    templateParams: {
      name,
      category,
      language,
      namespace,
      content_mode: props.sendRenderedContent ? 'rendered' : 'raw_template',
      processed_params: processedParams.value,
    },
  };

  if (templateButtons.length) {
    payload.contentAttributes = { template_buttons: templateButtons };
  }

  emit('sendMessage', payload);
};

const resetTemplate = () => {
  emit('resetTemplate');
};

const goBack = () => {
  emit('back');
};

onMounted(initializeTemplateParameters);

watch(
  () => props.template,
  () => {
    initializeTemplateParameters();
    v$.value.$reset();
  },
  { deep: true }
);

watch(
  processedParams,
  value => {
    if (props.modelValue !== null) emit('update:modelValue', value);
  },
  { deep: true }
);

defineExpose({
  processedParams,
  hasVariables,
  hasMediaHeader,
  isDocumentTemplate,
  headerComponent,
  renderedHeader,
  renderedTemplate,
  isFormInvalid,
  v$,
  updateMediaUrl,
  updateMediaName,
  canUploadMedia,
  uploadMedia,
  removeUploadedMedia,
  mediaError,
  sendMessage,
  resetTemplate,
  goBack,
});
</script>

<template>
  <div>
    <slot name="preview" :header="renderedHeader" :body="renderedTemplate">
      <div class="flex flex-col gap-4 p-4 mb-4 rounded-lg bg-n-alpha-black2">
        <div class="flex justify-between items-center">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ template.name }}
          </h3>
          <span class="text-xs text-n-slate-11">
            {{ languageLabel }}
          </span>
        </div>

        <div class="flex flex-col gap-2">
          <div class="rounded-md">
            <div
              v-if="renderedHeader"
              class="mb-2 text-sm font-medium whitespace-pre-wrap text-n-slate-12"
            >
              {{ renderedHeader }}
            </div>
            <div class="text-sm whitespace-pre-wrap text-n-slate-12">
              {{ renderedTemplate }}
            </div>
          </div>
        </div>

        <div class="text-xs text-n-slate-11">
          {{ categoryLabel }}
        </div>
      </div>
    </slot>
    <div v-if="hasVariables || hasMediaHeader">
      <div v-if="hasMediaHeader" class="mb-4">
        <p class="mb-2.5 text-sm font-semibold">
          {{
            $t('WHATSAPP_TEMPLATES.PARSER.MEDIA_HEADER_LABEL', {
              type: formatType,
            }) || `${formatType} Header`
          }}
        </p>
        <div
          v-if="!uploadedMedia && !canUploadMedia"
          data-testid="template-media-url"
          class="flex items-center mb-2.5"
        >
          <Input
            :model-value="processedParams.header?.media_url || ''"
            type="url"
            class="flex-1"
            :placeholder="
              t('WHATSAPP_TEMPLATES.PARSER.MEDIA_URL_LABEL', {
                type: formatType,
              })
            "
            @update:model-value="updateMediaUrl"
          />
        </div>
        <div v-if="canUploadMedia" class="flex flex-col gap-1.5 mb-2.5">
          <input
            ref="mediaFileInput"
            type="file"
            class="hidden"
            data-testid="template-media-input"
            :accept="headerMediaAccept(headerComponent?.format)"
            @change="onMediaFileChange"
          />
          <div v-if="uploadedMedia" class="flex items-center gap-2">
            <img
              v-if="isImageUpload"
              :src="uploadedMedia.media_url"
              :alt="uploadedMedia.media_name"
              class="object-cover rounded-lg size-12"
            />
            <span class="flex-1 min-w-0 text-sm truncate text-n-slate-12">
              {{
                t('WHATSAPP_TEMPLATES.PARSER.MEDIA_UPLOADED', {
                  name: uploadedMedia.media_name,
                })
              }}
            </span>
            <NextButton
              type="button"
              sm
              faded
              slate
              :label="t('WHATSAPP_TEMPLATES.PARSER.MEDIA_CHANGE')"
              data-testid="template-media-change"
              @click="chooseMediaFile"
            />
            <NextButton
              type="button"
              sm
              faded
              slate
              :label="t('WHATSAPP_TEMPLATES.PARSER.MEDIA_REMOVE')"
              @click="removeUploadedMedia"
            />
          </div>
          <div v-else class="flex items-center gap-2">
            <NextButton
              type="button"
              sm
              faded
              slate
              icon="i-lucide-upload"
              :is-loading="isUploadingMedia"
              :disabled="isUploadingMedia"
              :label="
                isUploadingMedia
                  ? t('WHATSAPP_TEMPLATES.PARSER.MEDIA_UPLOADING')
                  : t('WHATSAPP_TEMPLATES.PARSER.MEDIA_UPLOAD')
              "
              @click="chooseMediaFile"
            />
            <span class="text-xs text-n-slate-11">{{ mediaLimitsHint }}</span>
          </div>
          <p v-if="mediaError" class="mb-0 text-xs text-n-ruby-11">
            {{ mediaError }}
          </p>
        </div>
        <div v-if="isDocumentTemplate" class="flex items-center mb-2.5">
          <Input
            :model-value="processedParams.header?.media_name || ''"
            type="text"
            class="flex-1"
            :placeholder="
              t('WHATSAPP_TEMPLATES.PARSER.DOCUMENT_NAME_PLACEHOLDER')
            "
            @update:model-value="updateMediaName"
          />
        </div>
      </div>

      <!-- Text Header Variables Section -->
      <div v-if="hasTextHeaderVariables && processedParams.header">
        <p class="mb-2.5 text-sm font-semibold">
          {{ $t('WHATSAPP_TEMPLATES.PARSER.HEADER_VARIABLES_LABEL') }}
        </p>
        <div
          v-for="(variable, key) in processedParams.header"
          :key="`header-${key}`"
          class="flex items-center mb-2.5"
        >
          <Input
            :model-value="displayValue('header', key)"
            type="text"
            class="flex-1"
            :placeholder="
              t('WHATSAPP_TEMPLATES.PARSER.VARIABLE_PLACEHOLDER', {
                variable: key,
              })
            "
            @update:model-value="setValue('header', key, $event)"
          />
          <InsertVariableButton
            v-if="variableOptions.length"
            :variables="variableOptions"
            :show-label="false"
            @insert="insertVariable('header', key, $event)"
          />
        </div>
      </div>

      <!-- Body Variables Section -->
      <div v-if="processedParams.body">
        <p class="mb-2.5 text-sm font-semibold">
          {{ $t('WHATSAPP_TEMPLATES.PARSER.VARIABLES_LABEL') }}
        </p>
        <div
          v-for="(variable, key) in processedParams.body"
          :key="`body-${key}`"
          class="flex items-center mb-2.5"
        >
          <Input
            :model-value="displayValue('body', key)"
            type="text"
            class="flex-1"
            :placeholder="
              t('WHATSAPP_TEMPLATES.PARSER.VARIABLE_PLACEHOLDER', {
                variable: key,
              })
            "
            @update:model-value="setValue('body', key, $event)"
          />
          <InsertVariableButton
            v-if="variableOptions.length"
            :variables="variableOptions"
            :show-label="false"
            @insert="insertVariable('body', key, $event)"
          />
        </div>
      </div>

      <!-- Button Variables Section -->
      <div v-if="processedParams.buttons">
        <p class="mb-2.5 text-sm font-semibold">
          {{ t('WHATSAPP_TEMPLATES.PARSER.BUTTON_PARAMETERS') }}
        </p>
        <div
          v-for="(button, index) in processedParams.buttons"
          :key="`button-${index}`"
          class="flex items-center mb-2.5"
        >
          <Input
            v-model="processedParams.buttons[index].parameter"
            type="text"
            class="flex-1"
            :placeholder="t('WHATSAPP_TEMPLATES.PARSER.BUTTON_PARAMETER')"
          />
        </div>
      </div>
      <p
        v-if="v$.$dirty && v$.$invalid"
        class="p-2.5 text-center rounded-md bg-n-ruby-9/20 text-n-ruby-9"
      >
        {{ $t('WHATSAPP_TEMPLATES.PARSER.FORM_ERROR_MESSAGE') }}
      </p>
    </div>

    <slot
      name="actions"
      :send-message="sendMessage"
      :reset-template="resetTemplate"
      :go-back="goBack"
      :is-valid="!v$.$invalid"
      :disabled="isFormInvalid"
    />
  </div>
</template>
