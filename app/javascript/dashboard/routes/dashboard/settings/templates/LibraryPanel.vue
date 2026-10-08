<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import Button from 'dashboard/components-next/button/Button.vue';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { toSnakeCase } from './templateForm';
import {
  defaultLanguage,
  languageLabel,
  languageOptions,
} from './whatsappLanguages';

const props = defineProps({
  // The WhatsApp Cloud inboxes a template can be created in.
  inboxes: { type: Array, default: () => [] },
  // The templates of the page, to start in the language most of the channel's templates use.
  templates: { type: Array, default: () => [] },
});

const emit = defineEmits(['created']);

const { t, locale } = useI18n();
const { currentAccount } = useAccount();

const PAGE_SIZE = 12;

const search = ref('');
const language = ref('es');
const inboxId = ref(props.inboxes[0]?.id ?? 'all');
const languageTouched = ref(false);
const catalog = ref([]);
const visibleCount = ref(PAGE_SIZE);
const { run, isPending: isLoading } = useAbortableRequest();
const failed = ref(false);
const errorMessage = ref('');
const inboxLanguages = ref({});
const languageUsed = computed(() => {
  if (inboxId.value !== 'all') return inboxLanguages.value[inboxId.value];
  const languages = [...new Set(Object.values(inboxLanguages.value))];
  return languages.length === 1 ? languages[0] : null;
});
const dialogRef = ref(null);
const picked = ref(null);
const isCreating = ref(false);
const form = reactive({ name: '', buttonInputs: [] });

const applyDefaultLanguage = () => {
  if (languageTouched.value) return;
  language.value = defaultLanguage(
    currentAccount.value?.locale,
    props.templates,
    inboxId.value === 'all' ? null : inboxId.value
  );
};
applyDefaultLanguage();
watch([() => props.templates, inboxId], applyDefaultLanguage);

const humanName = name => String(name || '').replaceAll('_', ' ');

// Fetch every page, without language/search filters, so facets count the complete
// library available in each inbox rather than just its first visible page.
const readInbox = async (inbox, signal, after, entries = []) => {
  const { data } = await WhatsappTemplatesAPI.library(
    inbox.id,
    { after },
    { signal }
  );
  if (signal.aborted) return undefined;
  entries.push(
    ...data.templates.map(template => ({
      ...template,
      language: template.language || data.language_used,
      inboxId: inbox.id,
    }))
  );
  // Meta can include an end cursor even when the next page is empty.
  if (data.templates.length && data.next)
    return readInbox(inbox, signal, data.next, entries);
  return {
    templates: entries,
    languageUsed: data.language_used,
    inboxId: inbox.id,
  };
};
const load = async () => {
  catalog.value = [];
  failed.value = false;
  errorMessage.value = '';
  inboxLanguages.value = {};
  try {
    const result = await run(async signal => {
      const entries = await Promise.all(
        props.inboxes.map(inbox => readInbox(inbox, signal))
      );
      return signal.aborted ? undefined : entries;
    });
    if (result) {
      catalog.value = result.flatMap(inbox => inbox.templates);
      inboxLanguages.value = Object.fromEntries(
        result.map(inbox => [inbox.inboxId, inbox.languageUsed])
      );
    }
  } catch (error) {
    failed.value = true;
    errorMessage.value = error?.response?.data?.message || '';
  }
};
watch(() => props.inboxes, load, { immediate: true });
watch([search, language, inboxId], () => {
  visibleCount.value = PAGE_SIZE;
});
const searched = computed(() =>
  catalog.value.filter(template =>
    `${humanName(template.name)} ${template.body}`
      .toLocaleLowerCase()
      .includes(search.value.trim().toLocaleLowerCase())
  )
);
const languageRows = computed(() =>
  searched.value.filter(
    template => inboxId.value === 'all' || template.inboxId === inboxId.value
  )
);
const inboxRows = computed(() =>
  searched.value.filter(
    template => language.value === 'all' || template.language === language.value
  )
);
const filtered = computed(() =>
  languageRows.value.filter(
    template => language.value === 'all' || template.language === language.value
  )
);
const items = computed(() => filtered.value.slice(0, visibleCount.value));
const hasMore = computed(() => visibleCount.value < filtered.value.length);
const languageFilterOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_LANGUAGES'),
    count: languageRows.value.length,
  },
  ...languageOptions(locale.value).map(option => ({
    ...option,
    count: languageRows.value.filter(
      template => template.language === option.value
    ).length,
  })),
]);

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
    Boolean(picked.value && form.name) &&
    form.buttonInputs.every(input => input.value.trim())
);

const create = async () => {
  if (!canCreate.value) return;
  isCreating.value = true;
  try {
    const { data } = await WhatsappTemplatesAPI.createFromLibrary(
      picked.value.inboxId,
      {
        library_template_name: picked.value.name,
        name: toSnakeCase(form.name),
        language: picked.value.language || languageUsed.value || language.value,
        category: picked.value.category,
        button_inputs: buttonInputsPayload(),
      }
    );
    useAlert(
      t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.CREATED_LANGUAGE', {
        language: languageLabel(data.language_used, locale.value),
      })
    );
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

const chooseLanguage = value => {
  language.value = value;
  languageTouched.value = true;
};
const inboxOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_INBOXES'),
    count: inboxRows.value.length,
  },
  ...props.inboxes.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
    count: inboxRows.value.filter(template => template.inboxId === inbox.id)
      .length,
  })),
]);
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
      <FilterDropdown
        :model-value="language"
        :options="languageFilterOptions"
        icon="i-lucide-languages"
        :label="$t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.LANGUAGE')"
        class="w-56 shrink-0"
        data-testid="library-language"
        @update:model-value="chooseLanguage"
      />
      <FilterDropdown
        v-if="inboxes.length > 1"
        v-model="inboxId"
        :options="inboxOptions"
        icon="i-lucide-inbox"
        :label="$t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_INBOXES')"
        class="w-56 shrink-0"
        data-testid="library-inbox"
      />
    </div>

    <p v-if="failed" class="text-sm text-n-ruby-11" data-testid="library-error">
      {{
        errorMessage
          ? $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.ERROR_DETAIL', {
              message: errorMessage,
            })
          : $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.ERROR')
      }}
    </p>

    <p
      v-else-if="!isLoading && !items.length"
      class="text-sm text-n-slate-11"
      data-testid="library-empty"
    >
      {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.EMPTY') }}
    </p>
    <p
      v-if="!failed && !isLoading"
      class="text-sm text-n-slate-11"
      data-testid="library-language-used"
    >
      {{
        languageUsed
          ? $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.LANGUAGE_USED', {
              language: languageLabel(languageUsed, locale),
            })
          : $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.ALL_LANGUAGES')
      }}
    </p>

    <div class="grid gap-3 sm:grid-cols-2">
      <article
        v-for="template in items"
        :key="`${template.inboxId}-${template.name}-${template.language}`"
        class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak"
        data-testid="library-item"
      >
        <h4 class="text-heading-3 text-n-slate-12">
          {{ humanName(template.name) }}
        </h4>
        <p class="p-2 text-xs rounded-lg text-n-slate-12 bg-n-alpha-2">
          {{ template.body }}
        </p>
        <p
          v-if="inboxId === 'all' && inboxes.length > 1"
          class="text-xs text-n-slate-11"
        >
          {{ inboxes.find(inbox => inbox.id === template.inboxId).name }}
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

    <div v-if="hasMore">
      <Button
        slate
        sm
        :is-loading="isLoading"
        :label="$t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.LOAD_MORE')"
        data-testid="library-more"
        @click="visibleCount += PAGE_SIZE"
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
