<script setup>
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { toSnakeCase } from './templateForm';

const props = defineProps({
  // The WhatsApp Cloud inboxes a template can be created in.
  inboxes: { type: Array, default: () => [] },
});

const emit = defineEmits(['created']);

const { t } = useI18n();

const LANGUAGES = ['es', 'es_MX', 'es_AR', 'es_ES', 'en', 'en_US', 'pt_BR'];
const SEARCH_DELAY = 400;

const search = ref('');
const language = ref('es');
const inboxId = ref(props.inboxes[0]?.id ?? null);
const items = ref([]);
const nextCursor = ref(null);
const isLoading = ref(false);
const failed = ref(false);
const dialogRef = ref(null);
const picked = ref(null);
const isCreating = ref(false);
const form = reactive({ name: '', buttonInputs: [] });
let searchTimer = null;

watch(
  () => props.inboxes,
  list => {
    if (!inboxId.value && list[0]) inboxId.value = list[0].id;
  }
);

const humanName = name => String(name || '').replaceAll('_', ' ');

const load = async ({ append = false } = {}) => {
  if (!inboxId.value) return;
  isLoading.value = true;
  failed.value = false;
  try {
    const { data } = await WhatsappTemplatesAPI.library(inboxId.value, {
      search: search.value.trim() || undefined,
      language: language.value,
      after: append ? nextCursor.value : undefined,
    });
    items.value = append ? [...items.value, ...data.templates] : data.templates;
    nextCursor.value = data.next || null;
  } catch {
    failed.value = true;
    if (!append) items.value = [];
  } finally {
    isLoading.value = false;
  }
};

watch([search, language, inboxId], () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => load(), SEARCH_DELAY);
});

onMounted(() => load());
onBeforeUnmount(() => clearTimeout(searchTimer));

// The inputs some library buttons ask for: a phone number for a call button, a link for a URL button.
const inputsFor = template =>
  (template.buttons || [])
    .filter(button => ['PHONE_NUMBER', 'URL'].includes(button.type))
    .map(button => ({
      type: button.type,
      text: button.text || '',
      value: '',
      suffix: '',
      hasVariable: String(button.url || '').includes('{{'),
    }));

const use = template => {
  picked.value = template;
  form.name = toSnakeCase(template.name);
  form.buttonInputs = inputsFor(template);
  dialogRef.value?.open();
};

const buttonInputsPayload = () =>
  form.buttonInputs
    .filter(input => input.value.trim())
    .map(input =>
      input.type === 'PHONE_NUMBER'
        ? { type: 'PHONE_NUMBER', phone_number: input.value.trim() }
        : {
            type: 'URL',
            url: {
              base_url: input.value.trim(),
              url_suffix_example: input.suffix.trim() || undefined,
            },
          }
    );

const canCreate = computed(
  () =>
    Boolean(picked.value && inboxId.value && form.name) &&
    form.buttonInputs.every(input => input.value.trim())
);

const create = async () => {
  if (!canCreate.value) return;
  isCreating.value = true;
  try {
    await WhatsappTemplatesAPI.createFromLibrary(inboxId.value, {
      library_template_name: picked.value.name,
      name: toSnakeCase(form.name),
      language: picked.value.language || language.value,
      category: picked.value.category,
      button_inputs: buttonInputsPayload(),
    });
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.CREATED'));
    dialogRef.value?.close();
    emit('created');
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.ERROR')
    );
  } finally {
    isCreating.value = false;
  }
};

const selectClass =
  'px-3 py-2 text-sm rounded-lg bg-n-alpha-black2 text-n-slate-12 outline outline-1 outline-n-weak';
</script>

<template>
  <section class="grid gap-3" data-testid="library-panel">
    <div>
      <h3 class="text-heading-2 text-n-slate-12">
        {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.TITLE') }}
      </h3>
      <p class="mt-1 text-body-main text-n-slate-11">
        {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DESCRIPTION') }}
      </p>
    </div>

    <div class="flex flex-wrap items-center gap-2">
      <Input
        v-model="search"
        size="sm"
        class="flex-1 min-w-48"
        :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.SEARCH')"
        data-testid="library-search"
      />
      <select
        v-model="language"
        :class="selectClass"
        :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.LANGUAGE')"
      >
        <option v-for="code in LANGUAGES" :key="code" :value="code">
          {{ $t(`WHATSAPP_TEMPLATE_MGMT.FORM.LANGUAGES.${code}`) }}
        </option>
      </select>
      <select
        v-if="inboxes.length > 1"
        v-model="inboxId"
        :class="selectClass"
        :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CHANNEL')"
      >
        <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
          {{ inbox.name }}
        </option>
      </select>
    </div>

    <p v-if="failed" class="text-sm text-n-ruby-11" data-testid="library-error">
      {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.ERROR') }}
    </p>
    <p
      v-else-if="!isLoading && !items.length"
      class="text-sm text-n-slate-11"
      data-testid="library-empty"
    >
      {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.EMPTY') }}
    </p>

    <div class="grid gap-3 sm:grid-cols-2">
      <article
        v-for="template in items"
        :key="`${template.name}-${template.language}`"
        class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak"
        data-testid="library-item"
      >
        <h4 class="text-heading-3 text-n-slate-12">
          {{ humanName(template.name) }}
        </h4>
        <p class="p-2 text-xs rounded-lg text-n-slate-12 bg-n-alpha-2">
          {{ template.body }}
        </p>
        <p class="text-xs text-n-slate-10">
          {{
            $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.CATEGORY', {
              category: template.category,
            })
          }}
        </p>
        <div class="mt-auto">
          <Button
            :label="$t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.USE')"
            icon="i-lucide-library"
            size="sm"
            data-testid="library-use"
            @click="use(template)"
          />
        </div>
      </article>
    </div>

    <div v-if="nextCursor">
      <Button
        slate
        sm
        :is-loading="isLoading"
        :label="$t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.LOAD_MORE')"
        data-testid="library-more"
        @click="load({ append: true })"
      />
    </div>

    <Dialog
      ref="dialogRef"
      :title="$t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.TITLE')"
      :description="
        $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.DESCRIPTION')
      "
      :confirm-button-label="
        $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.CREATE')
      "
      :disable-confirm-button="!canCreate"
      :is-loading="isCreating"
      @confirm="create"
    >
      <div v-if="picked" class="grid gap-3">
        <Input
          v-model="form.name"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.NAME')"
        />
        <template v-for="(input, index) in form.buttonInputs" :key="index">
          <Input
            v-model="input.value"
            :label="
              input.type === 'PHONE_NUMBER'
                ? $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.PHONE', {
                    text: input.text,
                  })
                : $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.URL', {
                    text: input.text,
                  })
            "
            :placeholder="
              input.type === 'PHONE_NUMBER'
                ? '+593999999999'
                : 'https://ejemplo.com'
            "
          />
          <Input
            v-if="input.type === 'URL' && input.hasVariable"
            v-model="input.suffix"
            :label="
              $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.URL_SUFFIX')
            "
          />
        </template>
      </div>
    </Dialog>
  </section>
</template>
