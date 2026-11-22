<script setup>
import {
  nextTick,
  computed,
  onBeforeUnmount,
  provide,
  reactive,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';

import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import { useAccount } from 'dashboard/composables/useAccount';
import InboxesAPI from 'dashboard/api/inboxes';
import { templateDataEligible, templateVariables } from './templateData';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import DraftsAPI from 'dashboard/api/whatsappTemplateDrafts';
import { templateDraftError } from './templateDraftErrors';
import { useTemplateDraft } from './useTemplateDraft';
import {
  currentSubmission,
  draftDestination,
  draftFromForm,
  libraryPreview,
  formFromDraft,
  hasOpaqueComponents,
  draftVariableNamesValid,
} from './templateDrafts';
import Button from 'dashboard/components-next/button/Button.vue';
import TemplateComboBox from './TemplateComboBox.vue';
import LibraryDraftFields from './LibraryDraftFields.vue';
import VariablePicker from 'dashboard/components-next/variable-picker/VariablePicker.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import WhatsAppBubble from 'dashboard/components-next/whatsapp/WhatsAppBubble.vue';
import { bubbleFromTemplate } from 'dashboard/components-next/whatsapp/bubbleFromTemplate';
import {
  BUTTON_TYPES,
  CATEGORIES,
  HEADER_FORMATS,
  LIMITS,
  MEDIA_ACCEPT,
  MEDIA_FORMATS,
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
  // WhatsApp inboxes for local bindings; creation is limited to Cloud inboxes.
  inboxes: { type: Array, default: () => [] },
  // The templates of the page: a new one starts in the language most of its channel's templates use.
  templates: { type: Array, default: () => [] },
});

const emit = defineEmits(['saved', 'viewDraft']);

const DRAFT_SAVED_TOAST_DURATION = 8000;

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

const LANGUAGE_OPTIONS = computed(() => languageOptions(locale.value));

const panelRef = ref(null);
const previewDialogRef = ref(null);
const form = reactive(emptyForm());
const editing = ref(null);
const saveError = ref('');
const isLoading = ref(false);
const loadFailed = ref(false);
const isApplyingDraft = ref(false);
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
const activeOperation = ref(null);
const serverFieldErrors = ref({});
const isUploading = ref(false);
const headerPreviewUrl = ref('');
const headerFileSize = ref(0);
const fileInput = ref(null);
const bodyBox = ref(null);
const languageTouched = ref(false);
// How the variables of the message are written: {{nombre}} or {{1}}. A template uses one of them.
const variableMode = ref('NAMED');
const customVariable = ref('');

const draftSession = useTemplateDraft();
const { draft, conflict, conflictLoaded } = draftSession;
const editingBindings = ref(false);
const savedSnapshot = ref('');
const duplicateDialog = ref(null);
const duplicateInboxId = ref(null);
const isRemote = computed(() => Boolean(editing.value));
const drawerTitle = computed(() => {
  if (isRemote.value)
    return editing.value?.name || t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.DETAILS');
  if (draft.value?.source_remote_id)
    return t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.NEW_VERSION_TITLE');
  if (draft.value) return t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.EDIT_TITLE');
  return t('WHATSAPP_TEMPLATE_MGMT.FORM.NEW_TITLE');
});
// Keep the existing form's identity/structure locks for installed templates only.
const isEdit = isRemote;
const localReadOnly = computed(() =>
  Boolean(
    draft.value &&
      ['submitting', 'submitted', 'reconciling'].includes(draft.value.status)
  )
);
const currentAttempt = computed(() => currentSubmission(draft.value));
const sharedChannels = computed(() => {
  const waba =
    draftDestination(form.inboxId, props.inboxes).waba_id || form.wabaId;
  return props.inboxes
    .filter(
      inbox => waba && inbox.provider_config?.business_account_id === waba
    )
    .map(inbox => inbox.name);
});
const localSnapshot = () => JSON.stringify(draftFromForm(form, props.inboxes));
const hasUnsavedChanges = computed(
  () => !draft.value || localSnapshot() !== savedSnapshot.value
);
const localSaveStatus = computed(() => {
  if (activeOperation.value === 'save')
    return t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.SAVING');
  if (activeOperation.value === 'submit')
    return t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.SENDING');
  if (!draft.value && localSnapshot() === savedSnapshot.value)
    return t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.LOCAL_DRAFT');
  return hasUnsavedChanges.value
    ? t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.UNSAVED')
    : t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.SAVED_LOCALLY');
});
watch(
  () => localSnapshot(),
  () => {
    serverFieldErrors.value = {};
  }
);

const inboxOptions = computed(() =>
  props.inboxes
    .filter(inbox => isEdit.value || inbox.provider === 'whatsapp_cloud')
    .map(inbox => ({ value: inbox.id, label: inbox.name }))
);

const cloudInboxOptions = computed(() =>
  props.inboxes
    .filter(inbox => inbox.provider === 'whatsapp_cloud')
    .map(inbox => ({ value: inbox.id, label: inbox.name }))
);
const canCopyRemote = computed(() =>
  props.inboxes.some(
    inbox => inbox.id === form.inboxId && inbox.provider === 'whatsapp_cloud'
  )
);
// The names a variable can have: the same catalog the VariablePicker offers (CRM, attributes and appointments).
const knownVariableNames = computed(() =>
  bindings.value.map(binding => binding.name)
);

// The variables of the message the shared table does not know ({{pedido}}): each one needs to say what fills it.
const ownVariables = computed(() =>
  isEdit.value
    ? [...new Set(templateVariables(editing.value).map(item => item.token))]
    : [
        ...variableTokens(
          form.header.format === 'TEXT' ? form.header.text : ''
        ),
        ...variableTokens(form.body.text),
      ].filter(
        (token, index, all) =>
          all.indexOf(token) === index &&
          !/^\d+$/.test(token) &&
          (!knownVariableNames.value.includes(token) ||
            (form.variableBindings[token] &&
              !bindings.value.some(
                binding =>
                  binding.key === form.variableBindings[token] ||
                  binding.legacyPaths.includes(form.variableBindings[token])
              )))
      )
);
const allBindings = bindings;
const bindingNameFor = token =>
  allBindings.value.find(
    binding =>
      binding.key === form.variableBindings[token] ||
      binding.legacyPaths.includes(form.variableBindings[token])
  )?.id ||
  form.variableBindings[token] ||
  '';
const setVariableBinding = (token, id) => {
  if (!id) delete form.variableBindings[token];
  const binding = allBindings.value.find(item => item.id === id);
  if (binding) form.variableBindings[token] = binding.key;
};

const canEditContent = computed(
  () => !isRemote.value && !localReadOnly.value && !loadFailed.value
);
const canEditBindings = computed(
  () => editingBindings.value && templateDataEligible(editing.value)
);
const automaticVariable = token =>
  templateVariables(editing.value).some(
    item => item.token === token && item.source === 'alias'
  ) && !form.variableBindings[token];
const isLibrary = computed(() => Boolean(form.library));
const errors = computed(() => {
  if (isLibrary.value) {
    const result = validateForm({
      ...emptyForm(),
      inboxId: form.inboxId,
      name: form.name,
      language: form.language,
      category: form.category,
      body: { text: 'library', examples: [] },
    });
    if (
      form.library.button_inputs.some(input =>
        input.type === 'PHONE_NUMBER'
          ? !input.phone_number.trim()
          : !input.url.base_url.trim()
      )
    )
      result.buttons = 'BUTTON_TEXT_REQUIRED';
    return result;
  }
  const result = validateForm(form, {
    isEdit: isEdit.value,
    original: editing.value,
  });
  if (!isRemote.value && !draftVariableNamesValid(form))
    result['body.text'] = 'VARIABLE_NAME_INVALID';
  return result;
});
const canAttemptSubmit = computed(
  () =>
    draft.value &&
    !isRemote.value &&
    !localReadOnly.value &&
    !conflict.value &&
    !loadFailed.value &&
    !hasOpaqueComponents(form)
);
const canSubmit = computed(
  () =>
    canAttemptSubmit.value &&
    draftVariableNamesValid(form) &&
    !Object.keys(errors.value).length
);
const variableLabel = token => `{{${token}}}`;
const hasOriginalComponent = type =>
  editing.value?.components?.some(component => component.type === type);
const visibleErrors = computed(() => (showErrors.value ? errors.value : {}));
const categoryLocked = isRemote;
const isMediaHeader = computed(() =>
  MEDIA_FORMATS.includes(form.header.format)
);
const bodyVariables = computed(() => variableTokens(form.body.text));
const generatedName = computed(() => toSnakeCase(form.name));
const preview = computed(() =>
  isLibrary.value
    ? libraryPreview(form)
    : previewTemplate(form, headerPreviewUrl.value)
);
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
const fieldError = path =>
  serverFieldErrors.value[path] || errorText(visibleErrors.value[path]);
const focusFirstInvalid = async () => {
  await nextTick();
  formRef.value
    ?.querySelector(
      'input[aria-invalid="true"], button[aria-invalid="true"], [aria-invalid="true"] textarea'
    )
    ?.focus();
};

const statusLabel = computed(() => {
  const key = statusKey.value;
  return te(`WHATSAPP_TEMPLATE_MGMT.STATUS.${key}`)
    ? t(`WHATSAPP_TEMPLATE_MGMT.STATUS.${key}`)
    : formatTemplateLabel(key);
});

const apiError = error => {
  const data = error?.response?.data;
  const validationKey = data?.error?.toUpperCase();
  if (
    validationKey &&
    te(`WHATSAPP_TEMPLATE_MGMT.FORM.ERRORS.${validationKey}`)
  )
    return errorText(validationKey);
  return templateDraftError(error, t, te).message;
};

const resetForm = () => {
  draftSession.reset();
  editingBindings.value = false;
  savedSnapshot.value = '';
  if (headerPreviewUrl.value) URL.revokeObjectURL(headerPreviewUrl.value);
  delete form.parameterFormat;
  delete form.library;
  Object.assign(form, emptyForm());
  saveError.value = '';
  serverFieldErrors.value = {};
  loadFailed.value = false;
  headerPreviewUrl.value = '';
  headerFileSize.value = 0;
  liveState.value = null;
  showErrors.value = false;
  languageTouched.value = false;
  variableMode.value = 'NAMED';
  customVariable.value = '';
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
      form.inboxId =
        inboxOptions.value.length === 1 ? inboxOptions.value[0].value : null;
  } else if (template) {
    const inbox = props.inboxes.find(item =>
      template.inboxes?.some(owner => owner.id === item.id)
    );
    Object.assign(form, formFromTemplate(template, inbox?.id));
    if (inbox?.provider === 'whatsapp_cloud') await loadLiveState(template);
    // Use the server's resolved sources, including missing values across grouped inboxes.
    templateVariables(template).forEach(item => {
      if (item.source === 'binding')
        form.variableBindings[item.token] = item.path;
      else delete form.variableBindings[item.token];
    });
  } else {
    form.inboxId =
      inboxOptions.value.length === 1 ? inboxOptions.value[0].value : null;
  }
  if (!template && !languageTouched.value) setDefaultLanguage();
  variableMode.value =
    form.parameterFormat ||
    (hasNamedVariables(form.header.text, form.body.text)
      ? 'NAMED'
      : (bodyVariables.value.length && 'POSITIONAL') || 'NAMED');
  form.parameterFormat = variableMode.value;
  savedSnapshot.value = localSnapshot();
  panelRef.value?.open();
  await nextTick();
  isLoading.value = false;
};

const discardDialog = ref(null);
const close = () => {
  if (
    !isRemote.value &&
    !localReadOnly.value &&
    localSnapshot() !== savedSnapshot.value
  ) {
    discardDialog.value?.open();
    return;
  }
  panelRef.value?.close();
};
const reportError = async error => {
  try {
    if (await draftSession.handleConflict(error)) {
      saveError.value = '';
      return;
    }
    const result = templateDraftError(error, t, te);
    serverFieldErrors.value = result.fields;
    saveError.value = apiError(error);
  } catch {
    saveError.value = t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.RELOAD_ERROR');
  }
};
const applyMedia = async record => {
  form.header.handle = record.media ? 'local_attachment' : '';
  form.header.fileName = record.media?.filename || '';
  headerFileSize.value = record.media?.byte_size || 0;
  if (headerPreviewUrl.value) URL.revokeObjectURL(headerPreviewUrl.value);
  headerPreviewUrl.value = '';
  if (record.media) {
    const { data } = await DraftsAPI.downloadMedia(record.id);
    headerPreviewUrl.value = URL.createObjectURL(data);
  }
};
const applyDraft = async record => {
  isApplyingDraft.value = true;
  Object.assign(form, formFromDraft(record, props.inboxes));
  languageTouched.value = true;
  variableMode.value = form.parameterFormat;
  await nextTick();
  isApplyingDraft.value = false;
  savedSnapshot.value = localSnapshot();
  await applyMedia(record);
};
const keepChanges = async () => {
  try {
    await applyMedia(draft.value);
    draftSession.acceptRevision();
  } catch (error) {
    saveError.value = apiError(error);
  }
};
const openDraft = async record => {
  resetForm();
  editing.value = null;
  isLoading.value = true;
  panelRef.value?.open();
  store.dispatch('attributes/get');
  try {
    const latest = await draftSession.load(record.id);
    await applyDraft(latest);
  } catch (error) {
    loadFailed.value = true;
    saveError.value = apiError(error);
  } finally {
    isLoading.value = false;
  }
};
const reloadConflict = async () => {
  try {
    await applyDraft(await draftSession.load(draft.value.id));
    draftSession.acceptRevision();
    saveError.value = '';
  } catch (error) {
    saveError.value = apiError(error);
  }
};

watch(
  () => form.inboxId,
  (value, previous) => {
    if (value === previous) return;
    if (!isEdit.value && !languageTouched.value) setDefaultLanguage();
  }
);

// The body variables need one example each: keep the list the same length as the variables.
watch(bodyVariables, numbers => {
  if (isEdit.value || isLoading.value || isApplyingDraft.value) return;
  const examples = [...form.body.examples];
  while (examples.length < numbers.length) examples.push('');
  form.body.examples = examples.slice(0, Math.max(numbers.length, 0));
});

const variablesHelp = computed(() =>
  variableMode.value === 'NAMED'
    ? t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLES_NAMED_HELP')
    : t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLES_POSITIONAL_HELP')
);

const nextNumber = computed(
  () => Math.max(0, ...variableNumbers(form.body.text)) + 1
);

// Named variables already in the message are not offered again.
const isFreeVariable = binding => !bodyVariables.value.includes(binding.name);

const customVariableInvalid = computed(
  () => customVariable.value && !isValidVariableName(customVariable.value)
);

// Puts {{token}} where the cursor is in the body (at the end when the field was never focused).
const insertVariable = token => {
  const binding = bindings.value.find(item => item.name === token);
  if (binding) form.variableBindings[token] = binding.key;
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

const persistDraft = async () => {
  const record = await draftSession.save(draftFromForm(form, props.inboxes));
  savedSnapshot.value = localSnapshot();
  emit('saved');
  return record;
};
const onFileChosen = async event => {
  const [file] = event.target.files || [];
  event.target.value = '';
  if (
    !file ||
    isSaving.value ||
    isUploading.value ||
    conflict.value ||
    !canEditContent.value
  )
    return;
  isUploading.value = true;
  saveError.value = '';
  try {
    // Ensure an owner exists before attaching; neither call contacts Meta.
    await persistDraft();
    await draftSession.upload(file);
    form.header.handle = 'local_attachment';
    form.header.fileName = draft.value.media.filename;
    headerFileSize.value = draft.value.media.byte_size;
    if (headerPreviewUrl.value) URL.revokeObjectURL(headerPreviewUrl.value);
    headerPreviewUrl.value = URL.createObjectURL(file);
    emit('saved');
  } catch (error) {
    await reportError(error);
  } finally {
    isUploading.value = false;
  }
};
const removeFile = async () => {
  if (
    isUploading.value ||
    isSaving.value ||
    conflict.value ||
    !canEditContent.value
  )
    return;
  isUploading.value = true;
  try {
    if (draft.value?.media) await draftSession.removeMedia();
    form.header.handle = '';
    form.header.fileName = '';
    headerFileSize.value = 0;
    if (headerPreviewUrl.value) URL.revokeObjectURL(headerPreviewUrl.value);
    headerPreviewUrl.value = '';
    emit('saved');
  } catch (error) {
    await reportError(error);
  } finally {
    isUploading.value = false;
  }
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
  form.inboxId = value || null;
  form.wabaId = null;
};
const chooseLanguage = value => {
  if (!value) return;
  form.language = value;
  languageTouched.value = true;
};
const chooseHeaderFormat = value => {
  if (!value || isEdit.value) return;
  form.header.format = value;
};

const openPreview = () => previewDialogRef.value?.open();

const save = async () => {
  if (
    isSaving.value ||
    isUploading.value ||
    isLoading.value ||
    loadFailed.value ||
    conflict.value
  )
    return;
  isSaving.value = true;
  activeOperation.value = 'save';
  saveError.value = '';
  serverFieldErrors.value = {};
  try {
    if (isRemote.value) {
      if (!canEditBindings.value) return;
      await editing.value.inboxes.reduce(async (previous, inbox) => {
        await previous;
        await InboxesAPI.updateWhatsappTemplateVariableBindings(inbox.id, {
          name: editing.value.name,
          variable_bindings: form.variableBindings,
        });
      }, Promise.resolve());
      await store.dispatch('inboxes/get', { force: true });
      useAlert(t('WHATSAPP_TEMPLATE_MGMT.FORM.SAVED_LOCALLY'));
      emit('saved');
      panelRef.value?.close();
    } else if (!localReadOnly.value) {
      const record = await persistDraft();
      useAlert(t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.SAVED'), {
        type: 'callback',
        duration: DRAFT_SAVED_TOAST_DURATION,
        message: t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.VIEW_IN_TEMPLATES'),
        onClick: () => {
          emit('viewDraft', record);
          close();
        },
      });
    }
  } catch (error) {
    await reportError(error);
  } finally {
    isSaving.value = false;
    activeOperation.value = null;
    if (Object.keys(serverFieldErrors.value).length || showErrors.value)
      await focusFirstInvalid();
  }
};
const submitForReview = async () => {
  if (
    !canAttemptSubmit.value ||
    isSaving.value ||
    isUploading.value ||
    isLoading.value
  )
    return;
  showErrors.value = true;
  if (!canSubmit.value) {
    await focusFirstInvalid();
    return;
  }
  isSaving.value = true;
  activeOperation.value = 'submit';
  serverFieldErrors.value = {};
  saveError.value = '';
  try {
    if (localSnapshot() !== savedSnapshot.value) await persistDraft();
    await draftSession.submit();
    emit('saved');
  } catch (error) {
    await reportError(error);
  } finally {
    isSaving.value = false;
    activeOperation.value = null;
    if (Object.keys(serverFieldErrors.value).length || showErrors.value)
      await focusFirstInvalid();
  }
};
const verifySubmission = async () => {
  if (isSaving.value || !currentAttempt.value) return;
  isSaving.value = true;
  try {
    await DraftsAPI.reconcile(draft.value.id, currentAttempt.value.id);
    await applyDraft(await draftSession.load(draft.value.id));
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.VERIFY_QUEUED'));
    emit('saved');
  } catch (error) {
    await reportError(error);
  } finally {
    isSaving.value = false;
  }
};
const refreshDraft = async () => {
  if (isSaving.value) return;
  isSaving.value = true;
  try {
    await applyDraft(await draftSession.load(draft.value.id));
    emit('saved');
  } catch (error) {
    await reportError(error);
  } finally {
    isSaving.value = false;
  }
};
const newVersion = async () => {
  if (isSaving.value) return;
  isSaving.value = true;
  try {
    const { data } = isRemote.value
      ? await DraftsAPI.newVersion(
          props.inboxes.find(item => item.id === form.inboxId).channel_id,
          String(editing.value.id)
        )
      : await DraftsAPI.newVersion(
          draft.value.preferred_channel_id ||
            props.inboxes.find(
              inbox =>
                inbox.provider === 'whatsapp_cloud' &&
                inbox.provider_config?.business_account_id ===
                  draft.value.waba_id
            )?.channel_id,
          currentAttempt.value.remote_id
        );
    await openDraft(data);
    emit('saved');
  } catch (error) {
    await reportError(error);
  } finally {
    isSaving.value = false;
  }
};
const duplicate = async () => {
  if (isSaving.value || !duplicateInboxId.value) return;
  isSaving.value = true;
  try {
    // Installed templates first acquire a local copy; duplication always uses the
    // server copy endpoint so media and opaque components are preserved there.
    let source = draft.value;
    if (isRemote.value) {
      const { data } = await DraftsAPI.newVersion(
        props.inboxes.find(item => item.id === form.inboxId).channel_id,
        String(editing.value.id)
      );
      source = data;
    }
    const { data } = await DraftsAPI.duplicate(
      source.id,
      draftDestination(duplicateInboxId.value, props.inboxes)
    );
    duplicateDialog.value?.close();
    await openDraft(data);
    emit('saved');
  } catch (error) {
    await reportError(error);
  } finally {
    isSaving.value = false;
  }
};
const openBindings = async template => {
  await open(template);
  editingBindings.value = true;
};
const onPanelClosed = () => {
  if (
    !isRemote.value &&
    !localReadOnly.value &&
    localSnapshot() !== savedSnapshot.value
  ) {
    panelRef.value?.open();
    discardDialog.value?.open();
  }
};
const discard = () => {
  savedSnapshot.value = localSnapshot();
  discardDialog.value?.close();
  panelRef.value?.close();
};

onBeforeUnmount(() => {
  if (headerPreviewUrl.value) URL.revokeObjectURL(headerPreviewUrl.value);
});

const openDuplicate = async record => {
  duplicateInboxId.value = null;
  if (record.isLocalDraft) await openDraft(record);
  else await open(record);
  duplicateDialog.value?.open();
};
defineExpose({ open, close, openDraft, openBindings, openDuplicate });

// The combobox clears its value when the chosen option is clicked again: these fields always keep one.
const headerOptions = computed(() =>
  HEADER_FORMATS.map(format => ({
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
    :title="drawerTitle"
    @close="onPanelClosed"
  >
    <template #header>
      <div class="flex items-center min-w-0 gap-2">
        <h3 class="text-base font-medium truncate text-n-slate-12">
          {{ drawerTitle }}
        </h3>
        <span
          v-if="!isEdit"
          v-tooltip.bottom="$t('WHATSAPP_TEMPLATE_MGMT.FORM.DESCRIPTION')"
          class="i-lucide-info size-4 shrink-0 text-n-slate-10"
          role="img"
          :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.DESCRIPTION')"
          data-testid="form-info"
        />
      </div>
    </template>
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
        v-if="conflict"
        role="alert"
        class="grid gap-2 p-3 rounded-lg bg-n-amber-3 text-sm text-n-amber-11"
        data-testid="revision-conflict"
      >
        <p>{{ $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.CONFLICT') }}</p>
        <Button
          intent="secondary"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.RELOAD')"
          data-testid="reload-revision"
          @click="reloadConflict"
        />
        <Button
          v-if="conflictLoaded"
          intent="secondary"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.KEEP_CHANGES')"
          data-testid="keep-changes"
          @click="keepChanges"
        />
      </div>
      <div v-if="!isRemote" class="grid gap-2 text-sm text-n-slate-11">
        <div
          v-if="!localReadOnly"
          role="status"
          class="rounded-lg border border-solid border-n-weak bg-n-alpha-1 px-2 py-1.5 text-xs leading-5 text-n-slate-11"
          data-testid="local-save-status"
        >
          <span
            class="i-lucide-info inline-block size-3 align-middle"
            aria-hidden="true"
          />
          <span class="rounded bg-n-alpha-2 px-1 font-medium text-n-slate-12">{{
            localSaveStatus
          }}</span>
          {{ $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.LOCAL_SAVE_HELP') }}
        </div>
        <p v-if="sharedChannels.length > 1">
          {{
            $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.SHARED', {
              channels: sharedChannels.join(', '),
            })
          }}
        </p>
        <p
          v-if="hasOpaqueComponents(form)"
          class="text-n-amber-11"
          data-testid="opaque-warning"
        >
          {{ $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.OPAQUE') }}
        </p>
        <template v-if="draft">
          <p
            v-if="localReadOnly || draft.status !== 'draft'"
            role="status"
            data-testid="draft-state"
          >
            {{
              $t(
                'WHATSAPP_TEMPLATE_MGMT.DRAFTS.STATUS.' +
                  draft.status.toUpperCase()
              )
            }}
          </p>
          <p v-if="currentAttempt?.remote_status">
            {{
              $te(
                'WHATSAPP_TEMPLATE_MGMT.STATUS.' + currentAttempt.remote_status
              )
                ? $t(
                    'WHATSAPP_TEMPLATE_MGMT.STATUS.' +
                      currentAttempt.remote_status
                  )
                : currentAttempt.remote_status
            }}
          </p>
          <p v-if="draft.status === 'reconciling'">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.UNCERTAIN') }}
          </p>
          <p
            v-if="currentAttempt?.remote_status === 'REJECTED'"
            class="text-n-ruby-11"
          >
            {{
              $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.REJECTED', {
                reason: currentAttempt.remote_reason || '—',
              })
            }}
          </p>
          <p
            v-if="currentAttempt?.remote_status === 'PAUSED'"
            class="text-n-amber-11"
          >
            {{ $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.PAUSED') }}
          </p>
          <p
            v-if="
              currentAttempt?.error_details &&
              Object.keys(currentAttempt.error_details).length
            "
            role="alert"
            class="break-words text-n-ruby-11"
          >
            {{ JSON.stringify(currentAttempt.error_details) }}
          </p>
          <div class="flex flex-wrap gap-2">
            <Button
              v-if="localReadOnly"
              intent="secondary"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.REFRESH')"
              :disabled="isSaving"
              @click="refreshDraft"
            />
            <Button
              v-if="['reconciling', 'submitted'].includes(draft.status)"
              intent="secondary"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.VERIFY')"
              :disabled="isSaving"
              data-testid="verify-submission"
              @click="verifySubmission"
            />
          </div>
        </template>
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
            $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.REJECTED', {
              reason: liveState.rejected_reason,
            })
          }}
        </p>
        <p
          v-if="statusKey === 'APPROVED'"
          class="text-xs text-n-amber-11"
          data-testid="approved-warning"
        >
          {{ $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.READ_ONLY') }}
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
        <p v-if="statusKey === 'PAUSED'" class="text-n-amber-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.PAUSED') }}
        </p>
        <Button
          v-if="templateDataEligible(editing) && !editingBindings"
          intent="secondary"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.CONFIGURE_BINDINGS')"
          @click="editingBindings = true"
        />
      </div>

      <fieldset
        :disabled="!canEditContent || isSaving || isUploading"
        :inert="!canEditContent || isSaving || isUploading"
        class="grid gap-4 min-w-0"
      >
        <Input
          v-if="!isRemote"
          v-model="form.title"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.INTERNAL_TITLE')"
          :max-length="100"
          :message="
            fieldError('title') ||
            $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.INTERNAL_TITLE_HELP')
          "
          :message-type="fieldError('title') ? 'error' : 'info'"
          data-testid="draft-title"
        />
        <div class="grid gap-4 sm:grid-cols-2">
          <div
            v-if="!isRemote || inboxes.length > 1 || visibleErrors.inboxId"
            class="grid gap-1 content-start sm:col-span-2"
          >
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL') }}
            </span>
            <TemplateComboBox
              :model-value="form.inboxId ?? ''"
              :options="inboxOptions"
              :placeholder="
                $t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL_PLACEHOLDER')
              "
              :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL')"
              :search-placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL')"
              :disabled="isEdit"
              :has-error="Boolean(fieldError('inboxId'))"
              :message="
                fieldError('inboxId') ||
                (!isRemote && !form.inboxId
                  ? $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.NO_DESTINATION_HELP')
                  : '')
              "
              teleport
              data-testid="template-inbox"
              @update:model-value="chooseInbox"
            />
          </div>
          <Input
            v-model="form.name"
            :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.NAME')"
            :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.NAME_PLACEHOLDER')"
            :disabled="isEdit"
            :message="
              fieldError('name') ||
              (!isEdit && generatedName && generatedName !== form.name
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
              :disabled="isEdit || isLibrary"
              :has-error="Boolean(fieldError('language'))"
              :message="fieldError('language')"
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
                :aria-invalid="Boolean(fieldError('category')) || undefined"
                :aria-describedby="
                  fieldError('category') ? 'draft-category-error' : undefined
                "
              />
              <span class="grid gap-0.5">
                <span
                  class="flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
                >
                  {{
                    $t(
                      `WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.${category}.LABEL`
                    )
                  }}
                  <span
                    v-tooltip.top="
                      $t(
                        `WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.${category}.HELP`
                      )
                    "
                    class="i-lucide-info size-3.5 shrink-0 text-n-slate-10"
                    role="img"
                    :aria-label="
                      $t(
                        `WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.${category}.HELP`
                      )
                    "
                    :data-testid="`category-info-${category}`"
                  />
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
          <p
            v-if="fieldError('category')"
            id="draft-category-error"
            role="alert"
            class="text-xs text-n-ruby-11"
          >
            {{ fieldError('category') }}
          </p>
        </fieldset>

        <div v-if="!isEdit && !isLibrary" class="grid gap-1">
          <span
            class="flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
          >
            {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLES_AS') }}
            <span
              v-tooltip.top="variablesHelp"
              class="i-lucide-info size-3.5 shrink-0 text-n-slate-10"
              role="img"
              :aria-label="variablesHelp"
              data-testid="variables-info"
            />
          </span>
          <div class="flex flex-wrap items-center gap-2">
            <Button
              type="button"
              xs
              :slate="variableMode !== 'NAMED'"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLES_NAMED')"
              data-testid="mode-named"
              @click="
                variableMode = 'NAMED';
                form.parameterFormat = 'NAMED';
              "
            />
            <Button
              type="button"
              xs
              :slate="variableMode !== 'POSITIONAL'"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLES_POSITIONAL')"
              data-testid="mode-positional"
              @click="
                variableMode = 'POSITIONAL';
                form.parameterFormat = 'POSITIONAL';
              "
            />
          </div>
        </div>

        <LibraryDraftFields v-if="isLibrary" v-model="form.library" />
        <!-- The message as the customer will read it, edited in place -->
        <div
          v-if="!isLibrary"
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
              <div class="flex items-center gap-2">
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
              </div>
              <template v-if="form.header.format === 'TEXT'">
                <Input
                  :model-value="form.header.text"
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
                  :message-type="
                    fieldError('header.example') ? 'error' : 'info'
                  "
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
                      :aria-label="
                        $t('WHATSAPP_TEMPLATE_MGMT.FORM.REMOVE_FILE')
                      "
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
              <div class="relative">
                <TextArea
                  :model-value="form.body.text"
                  resize
                  class="[&_textarea]:min-h-32"
                  :placeholder="
                    $t('WHATSAPP_TEMPLATE_MGMT.FORM.BODY_PLACEHOLDER')
                  "
                  :max-length="LIMITS.body"
                  show-character-count
                  :message="fieldError('body.text')"
                  :message-type="fieldError('body.text') ? 'error' : 'info'"
                  :aria-invalid="Boolean(fieldError('body.text')) || undefined"
                  @update:model-value="value => (form.body.text = value)"
                />
                <!-- Next to the character counter, inside the text box: a small button, not a full-width field. -->
                <div
                  v-if="!isEdit"
                  class="absolute bottom-2.5 end-24 w-40"
                  data-testid="variable-picker"
                >
                  <VariablePicker
                    v-if="variableMode === 'NAMED'"
                    value-format="alias"
                    :filter="isFreeVariable"
                    :placeholder="
                      $t('WHATSAPP_TEMPLATE_MGMT.FORM.ADD_VARIABLE')
                    "
                    :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.ADD_VARIABLE')"
                    class="[&_button]:!h-6 [&_button]:!py-0 [&_button]:!px-2 [&_button]:text-xs"
                    data-testid="variable-menu-toggle"
                    @update:model-value="insertVariable"
                  />
                  <Button
                    v-else
                    type="button"
                    slate
                    outline
                    xs
                    class="w-full"
                    :label="`{{${nextNumber}}}`"
                    :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.ADD_VARIABLE')"
                    data-testid="variable-menu-toggle"
                    @click="insertVariable(String(nextNumber))"
                  />
                </div>
              </div>
              <div
                v-if="!isEdit && variableMode === 'NAMED'"
                class="flex flex-wrap items-start gap-2"
              >
                <div
                  v-if="!isEdit && variableMode === 'NAMED'"
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
                    intent="secondary"
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
              :placeholder="
                $t('WHATSAPP_TEMPLATE_MGMT.FORM.FOOTER_PLACEHOLDER')
              "
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
                    $t(
                      `WHATSAPP_TEMPLATE_MGMT.FORM.BUTTON_TYPES.${button.type}`
                    )
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
                  :model-value="form.buttons[index].url"
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
      </fieldset>
      <fieldset
        v-if="
          ownVariables.length &&
          ((!isEdit && !localReadOnly) || canEditBindings)
        "
        class="grid gap-2 min-w-0"
        :disabled="isSaving || isUploading || loadFailed"
        :inert="isSaving || isUploading || loadFailed"
        data-testid="variable-values"
      >
        <span
          class="flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
        >
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_VALUES') }}
          <span
            v-tooltip.top="
              $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_VALUES_HELP')
            "
            class="i-lucide-info size-3.5 text-n-slate-10"
          />
        </span>
        <div class="grid gap-2 sm:grid-cols-2">
          <div v-for="token in ownVariables" :key="token" class="grid gap-1">
            <span class="text-xs text-n-slate-11">{{
              variableLabel(token)
            }}</span>
            <span
              v-if="automaticVariable(token)"
              class="text-xs text-n-slate-11"
            >
              {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_AUTOMATIC') }}
            </span>
            <VariablePicker
              value-format="id"
              mode="read"
              allow-none
              :allow-none-label="
                automaticVariable(token)
                  ? $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_AUTOMATIC')
                  : isEdit
                    ? $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_PENDING')
                    : $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_ONLY_HERE')
              "
              :model-value="bindingNameFor(token)"
              :placeholder="
                automaticVariable(token)
                  ? $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_AUTOMATIC')
                  : isEdit
                    ? $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_PENDING')
                    : $t('WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_ONLY_HERE')
              "
              :aria-label="variableLabel(token)"
              :data-testid="`variable-value-${token}`"
              @update:model-value="name => setVariableBinding(token, name)"
            />
          </div>
        </div>
      </fieldset>

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
            :disabled="!canEditContent || isSaving || isUploading"
            :label="`{{${number}}}`"
            size="sm"
          />
        </div>
        <span v-if="fieldError('body.examples')" class="text-xs text-n-ruby-9">
          {{ fieldError('body.examples') }}
        </span>
      </div>

      <div
        v-if="!isEdit"
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
      <WhatsAppBubble
        v-bind="bubbleFromTemplate(preview, variables)"
        class="w-full max-w-sm mx-auto"
        data-testid="form-preview"
      />
    </Dialog>

    <Dialog
      ref="duplicateDialog"
      :title="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DUPLICATE')"
      :confirm-button-label="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DUPLICATE')"
      :disable-confirm-button="!duplicateInboxId || isSaving"
      :is-loading="isSaving"
      @confirm="duplicate"
    >
      <TemplateComboBox
        v-model="duplicateInboxId"
        :options="cloudInboxOptions"
        :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL_PLACEHOLDER')"
        :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL')"
      />
    </Dialog>
    <Dialog
      ref="discardDialog"
      :title="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DISCARD_TITLE')"
      :description="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DISCARD_HELP')"
      :confirm-button-label="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DISCARD')"
      @confirm="discard"
    />
    <template #footer>
      <div
        class="grid grid-cols-[auto_auto_minmax(0,1fr)] gap-2 sm:flex sm:flex-wrap sm:justify-end"
        data-testid="draft-footer"
      >
        <Button
          v-if="canEditContent || canEditBindings"
          type="button"
          class="col-span-3 w-full sm:order-3 sm:w-auto"
          intent="primary"
          :is-loading="activeOperation === 'save'"
          :disabled="isSaving || isUploading || isLoading || conflict"
          data-testid="save-draft"
          @click="save"
        >
          {{
            activeOperation === 'save'
              ? $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.SAVING')
              : canEditBindings
                ? $t('WHATSAPP_TEMPLATE_MGMT.FORM.SAVE_CHANGES')
                : $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.SAVE')
          }}
        </Button>
        <Button
          type="button"
          intent="tertiary"
          size="sm"
          class="min-h-10 whitespace-nowrap px-2 sm:order-1"
          @click="close"
        >
          {{ $t('WHATSAPP_TEMPLATE_MGMT.FORM.CANCEL') }}
        </Button>
        <Button
          type="button"
          intent="secondary"
          size="sm"
          class="min-h-10 whitespace-nowrap px-2 sm:order-2"
          icon="i-lucide-eye"
          :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.PREVIEW')"
          data-testid="template-preview-open"
          @click="openPreview"
        >
          <span class="hidden sm:inline">{{
            $t('WHATSAPP_TEMPLATE_MGMT.FORM.PREVIEW')
          }}</span>
        </Button>
        <Button
          v-if="!isRemote && draft && !localReadOnly"
          intent="secondary"
          size="sm"
          class="min-h-10 whitespace-nowrap px-2 sm:order-4"
          :disabled="!canAttemptSubmit || isSaving || isUploading || isLoading"
          :is-loading="activeOperation === 'submit'"
          :title="
            !canSubmit
              ? $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.SUBMIT_REQUIREMENTS')
              : undefined
          "
          data-testid="submit-draft"
          @click="submitForReview"
        >
          <span class="whitespace-nowrap">{{
            activeOperation === 'submit'
              ? $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.SENDING')
              : $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.SUBMIT')
          }}</span>
        </Button>
        <template v-if="isRemote || localReadOnly">
          <Button
            v-if="(isRemote && canCopyRemote) || currentAttempt?.remote_id"
            intent="primary"
            class="w-full sm:order-4 sm:w-auto"
            :disabled="isSaving || isLoading"
            :label="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.NEW_VERSION')"
            data-testid="new-version"
            @click="newVersion"
          />
          <Button
            v-if="(isRemote && canCopyRemote) || draft"
            intent="secondary"
            class="w-full sm:order-5 sm:w-auto"
            :disabled="isSaving || isLoading"
            :label="$t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DUPLICATE')"
            data-testid="duplicate-draft"
            @click="duplicateDialog?.open()"
          />
        </template>
      </div>
    </template>
  </SidePanel>
</template>
