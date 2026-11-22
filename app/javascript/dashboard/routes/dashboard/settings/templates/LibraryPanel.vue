<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import Button from 'dashboard/components-next/button/Button.vue';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import DraftsAPI from 'dashboard/api/whatsappTemplateDrafts';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { templateDraftError } from './templateDraftErrors';
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

const { t, te, locale } = useI18n();
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
const creatingTemplate = ref(null);
const isCreating = computed(() => Boolean(creatingTemplate.value));
const isCreatingTemplate = template => creatingTemplate.value === template;

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
    errorMessage.value = error?.response?.data?.message
      ? t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.ERROR_DETAIL', {
          message: templateDraftError(error, t, te).message,
        })
      : t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.ERROR');
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

const use = async template => {
  if (isCreating.value) return;
  creatingTemplate.value = template;
  try {
    const inbox = props.inboxes.find(item => item.id === template.inboxId);
    const { data } = await DraftsAPI.fromLibrary({
      channel_id: inbox.channel_id,
      library_template_name: template.name,
      name: toSnakeCase(template.name),
      language: template.language || languageUsed.value || language.value,
      category: template.category,
      button_inputs: (template.buttons || [])
        .filter(button => ['PHONE_NUMBER', 'URL'].includes(button.type))
        .map(button =>
          button.type === 'PHONE_NUMBER'
            ? { type: button.type, phone_number: '' }
            : {
                type: button.type,
                url: { base_url: '', url_suffix_example: '' },
              }
        ),
      preview: {
        body: template.body,
        ...(template.header ? { header: template.header } : {}),
        buttons: (template.buttons || []).map(button => ({
          type: button.type,
          text: button.text || '',
          ...(button.url ? { url: button.url } : {}),
          ...(button.phone_number ? { phone_number: button.phone_number } : {}),
        })),
      },
    });
    emit('created', data);
  } catch (error) {
    useAlert(templateDraftError(error, t, te).message);
  } finally {
    creatingTemplate.value = null;
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

    <div
      v-if="isLoading"
      role="status"
      class="flex items-center gap-2 text-n-slate-11"
      data-testid="library-loading"
    >
      <Spinner />
      {{ $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.LOADING') }}
    </div>
    <div v-else-if="failed" class="grid gap-2">
      <p
        role="alert"
        class="text-sm text-n-ruby-11"
        data-testid="library-error"
      >
        {{ errorMessage }}
      </p>
      <Button
        intent="secondary"
        size="sm"
        class="justify-self-start"
        :label="$t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.RETRY')"
        data-testid="library-retry"
        @click="load"
      />
    </div>
    <p
      v-else-if="!items.length"
      class="text-sm text-n-slate-11"
      role="status"
      data-testid="library-empty"
    >
      {{
        inboxes.length
          ? $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.EMPTY')
          : $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.NO_INBOXES')
      }}
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
        class="flex flex-col gap-2 p-4 border border-solid rounded-xl border-n-weak"
        :aria-busy="isCreatingTemplate(template)"
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
            :label="
              isCreatingTemplate(template)
                ? $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.CREATING')
                : $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.USE')
            "
            :is-loading="isCreatingTemplate(template)"
            icon="i-lucide-library"
            size="sm"
            intent="primary"
            :disabled="isCreating"
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
  </section>
</template>
