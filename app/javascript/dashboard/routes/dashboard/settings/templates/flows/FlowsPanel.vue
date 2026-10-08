<script setup>
import {
  computed,
  onActivated,
  onDeactivated,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TemplatesToolbar from '../TemplatesToolbar.vue';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import TemplatesTable from '../TemplatesTable.vue';
import { templateTableColumns } from '../templateTableColumns';
import TemplateRowActions from '../TemplateRowActions.vue';
import FlowPublicationSummary from './FlowPublicationSummary.vue';
import FlowPublicationPanel from './FlowPublicationPanel.vue';
import { CATEGORIES } from './flowDefinition';

const PAGE_SIZE = 8;
const STATES = ['published', 'partial', 'error', 'none'];
const { t, locale } = useI18n();
const router = useRouter();
const { checkPermissions } = usePolicy();
const isAdmin = computed(() => checkPermissions(['administrator']));
const createAction = computed(() =>
  isAdmin.value
    ? {
        label: t('WHATSAPP_FLOWS.LIST.NEW'),
        run: () => router.push({ name: 'settings_flow_new' }),
      }
    : null
);
const { run, abort, isPending } = useAbortableRequest();
const flows = ref([]);
const total = ref(0);
const facets = ref({ state: {}, category: {} });
const search = ref('');
const state = ref('all');
const category = ref('all');
const page = ref(1);
const failed = ref(false);
const hasLoaded = ref(false);
const toDelete = ref(null);
const deleteDialog = ref(null);
const publicationPanel = ref(null);
const isDeleting = ref(false);
const toDuplicate = ref(null);
const duplicateDialog = ref(null);
const isDuplicating = ref(false);
const actionLabels = computed(() => ({
  edit: t('WHATSAPP_FLOWS.LIST.EDIT'),
  duplicate: t('WHATSAPP_TEMPLATE_MGMT.DUPLICATE'),
  delete: t('WHATSAPP_FLOWS.LIST.DELETE'),
}));
const askDuplicate = flow => {
  toDuplicate.value = flow;
  duplicateDialog.value.open();
};
const stateOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_FLOWS.LIST.ALL_STATES'),
    count: facets.value.state.all ?? 0,
  },
  ...STATES.map(value => ({
    value,
    label: t(`WHATSAPP_FLOWS.LIST.STATES.${value}`),
    count: facets.value.state[value] ?? 0,
  })),
]);
const categoryOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_FLOWS.LIST.ALL_CATEGORIES'),
    count: facets.value.category.all ?? 0,
  },
  ...CATEGORIES.map(value => ({
    value,
    label: t(`WHATSAPP_FLOWS.CATEGORIES.${value}`),
    count: facets.value.category[value] ?? 0,
  })),
]);
const columns = computed(() => templateTableColumns(t, ['SCREENS']));
const load = async () => {
  failed.value = false;
  try {
    await run(async signal => {
      const { data } = await WhatsappFlowsAPI.list(
        {
          page: page.value,
          per_page: PAGE_SIZE,
          ...(search.value.trim() ? { search: search.value.trim() } : {}),
          ...(state.value !== 'all' ? { state: state.value } : {}),
          ...(category.value !== 'all' ? { category: category.value } : {}),
        },
        { signal }
      );
      if (signal.aborted) return;
      flows.value = data.payload;
      total.value = data.meta.total_count;
      facets.value = data.facets;
      hasLoaded.value = true;
      if (!flows.value.length && total.value && page.value > 1)
        page.value = Math.ceil(total.value / PAGE_SIZE);
    });
  } catch {
    failed.value = true;
    useAlert(t('WHATSAPP_FLOWS.LIST.LOAD_ERROR'));
  }
};
watch(
  [search, state, category],
  () => {
    page.value = 1;
  },
  { flush: 'sync' }
);
watch([page, search, state, category], useDebounceFn(load, 200));
onMounted(load);
let firstActivation = true;
onActivated(() => {
  if (firstActivation) firstActivation = false;
  else load();
});
onDeactivated(abort);
const edit = flow =>
  router.push({ name: 'settings_flow_edit', params: { flowId: flow.id } });
const askDelete = flow => {
  toDelete.value = flow;
  deleteDialog.value.open();
};
const confirmDelete = async () => {
  isDeleting.value = true;
  try {
    await WhatsappFlowsAPI.remove(toDelete.value.id);
    deleteDialog.value.close();
    useAlert(t('WHATSAPP_FLOWS.LIST.DELETED'));
    await load();
  } catch {
    useAlert(t('WHATSAPP_FLOWS.LIST.DELETE_ERROR'));
  } finally {
    isDeleting.value = false;
  }
};
const confirmDuplicate = async () => {
  isDuplicating.value = true;
  try {
    await WhatsappFlowsAPI.duplicate(toDuplicate.value.id);
    duplicateDialog.value.close();
    page.value = 1;
    await load();
  } catch {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.DUPLICATE_ERROR'));
  } finally {
    isDuplicating.value = false;
  }
};
const dateOf = seconds =>
  new Date(seconds * 1000).toLocaleDateString(locale.value);
const categoryLabel = flow => {
  const values = flow.categories.length ? flow.categories : ['OTHER'];
  const first = t(`WHATSAPP_FLOWS.CATEGORIES.${values[0]}`);
  return values.length > 1 ? `${first} +${values.length - 1}` : first;
};
</script>

<template>
  <div data-testid="flows-panel">
    <TemplatesToolbar
      v-model="search"
      :placeholder="$t('WHATSAPP_FLOWS.LIST.SEARCH')"
      :primary-action="createAction"
      data-testid="flows-toolbar"
    >
      <template #filters>
        <div>
          <FilterDropdown
            v-model="state"
            :options="stateOptions"
            :label="$t('WHATSAPP_FLOWS.LIST.STATE')"
            icon="i-lucide-circle-check"
            data-testid="flows-state"
          />
        </div>
        <div>
          <FilterDropdown
            v-model="category"
            :options="categoryOptions"
            :label="$t('WHATSAPP_FLOWS.NEW.CATEGORIES')"
            icon="i-lucide-folder"
            data-testid="flows-category"
          />
        </div>
      </template>
    </TemplatesToolbar>
    <div
      v-if="isPending && !hasLoaded"
      class="grid gap-3 animate-pulse"
      data-testid="flows-skeleton"
      aria-busy="true"
    >
      <div
        v-for="row in PAGE_SIZE"
        :key="row"
        class="h-12 rounded bg-n-alpha-2"
      />
    </div>
    <div v-else-if="failed && !hasLoaded">
      <Button
        type="button"
        faded
        slate
        :label="$t('WHATSAPP_FLOWS.META.RETRY')"
        @click="load"
      />
    </div>
    <p
      v-else-if="!total"
      class="py-8 text-center text-n-slate-11"
      data-testid="flows-empty"
    >
      {{
        $t(
          search || state !== 'all' || category !== 'all'
            ? 'WHATSAPP_FLOWS.LIST.NO_RESULTS'
            : 'WHATSAPP_FLOWS.LIST.EMPTY'
        )
      }}
    </p>
    <TemplatesTable
      v-else
      v-model:page="page"
      :columns="columns"
      :items="flows"
      :total="total"
      :page-size="PAGE_SIZE"
      @open="edit"
    >
      <template #NAME="{ item: flow }">
        <span class="block max-w-56 truncate text-heading-3 text-n-slate-12">{{
          flow.name
        }}</span>
        <span
          v-if="flow.unpublished_changes"
          class="block mt-1 text-xs text-n-amber-11"
          data-testid="flow-unpublished-badge"
          >{{ $t('WHATSAPP_FLOWS.META.UNPUBLISHED_CHANGES_BADGE') }}</span
        >
      </template>
      <template #CATEGORY="{ item: flow }">
        <span
          class="px-2 py-1 text-xs rounded-md whitespace-nowrap bg-n-alpha-2"
          >{{ categoryLabel(flow) }}</span
        >
      </template>
      <template #SCREENS="{ item: flow }">
        <span
          :aria-label="$t('WHATSAPP_FLOWS.LIST.SCREENS', { n: flow.screens })"
          >{{ flow.screens }}</span
        >
      </template>
      <template #INBOX>
        <span>{{ $t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_INBOXES') }}</span>
      </template>
      <template #UPDATED="{ item: flow }">
        {{ dateOf(flow.updated_at) }}
      </template>
      <template #STATUS="{ item: flow }">
        <FlowPublicationSummary
          v-if="isAdmin"
          :summary="flow.publication_summary"
          @click.stop
          @details="publicationPanel.open(flow)"
        />
      </template>
      <template #ACTIONS="{ item: flow }">
        <TemplateRowActions
          :labels="actionLabels"
          :can-manage="isAdmin"
          :can-edit="isAdmin"
          @edit="edit(flow)"
          @duplicate="askDuplicate(flow)"
          @delete="askDelete(flow)"
        />
      </template>
    </TemplatesTable>
    <Dialog
      v-if="isAdmin"
      ref="duplicateDialog"
      :title="$t('WHATSAPP_TEMPLATE_MGMT.DUPLICATE')"
      :confirm-button-label="$t('WHATSAPP_TEMPLATE_MGMT.DUPLICATE')"
      :is-loading="isDuplicating"
      @confirm="confirmDuplicate"
    >
      <p v-if="toDuplicate" class="text-sm text-n-slate-11">
        {{
          $t('WHATSAPP_TEMPLATE_MGMT.DUPLICATE_FLOW_BODY', {
            name: toDuplicate.name.slice(0, 92) + ' (copia)',
          })
        }}
      </p>
    </Dialog>
    <FlowPublicationPanel
      v-if="isAdmin"
      ref="publicationPanel"
      @updated="load"
    />
    <Dialog
      v-if="isAdmin"
      ref="deleteDialog"
      type="alert"
      :title="$t('WHATSAPP_FLOWS.LIST.DELETE_TITLE')"
      :confirm-button-label="$t('WHATSAPP_FLOWS.LIST.DELETE')"
      :is-loading="isDeleting"
      @confirm="confirmDelete"
    >
      <p v-if="toDelete" class="text-sm text-n-slate-11">
        {{ $t('WHATSAPP_FLOWS.LIST.DELETE_BODY', { name: toDelete.name }) }}
      </p>
    </Dialog>
  </div>
</template>
