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
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import BaseTableRow from 'dashboard/components-next/table/BaseTableRow.vue';
import BaseTableCell from 'dashboard/components-next/table/BaseTableCell.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import FlowPublicationSummary from './FlowPublicationSummary.vue';
import FlowPublicationPanel from './FlowPublicationPanel.vue';
import { CATEGORIES } from './flowDefinition';

const PAGE_SIZE = 8;
const STATES = ['published', 'partial', 'error', 'none'];
const { t, locale } = useI18n();
const router = useRouter();
const { checkPermissions } = usePolicy();
const isAdmin = computed(() => checkPermissions(['administrator']));
const { run, abort, isPending } = useAbortableRequest();
const flows = ref([]);
const total = ref(0);
const search = ref('');
const state = ref('all');
const category = ref('all');
const page = ref(1);
const failed = ref(false);
const toDelete = ref(null);
const deleteDialog = ref(null);
const publicationPanel = ref(null);
const isDeleting = ref(false);
const stateOptions = computed(() => [
  { value: 'all', label: t('WHATSAPP_FLOWS.LIST.ALL_STATES') },
  ...STATES.map(value => ({
    value,
    label: t(`WHATSAPP_FLOWS.LIST.STATES.${value}`),
  })),
]);
const categoryOptions = computed(() => [
  { value: 'all', label: t('WHATSAPP_FLOWS.LIST.ALL_CATEGORIES') },
  ...CATEGORIES.map(value => ({
    value,
    label: t(`WHATSAPP_FLOWS.CATEGORIES.${value}`),
  })),
]);
const headers = computed(() =>
  [
    'NAME',
    'CATEGORIES',
    'SCREENS_HEADER',
    'UPDATED',
    'PUBLICATION',
    'ACTIONS',
  ].map(key => t(`WHATSAPP_FLOWS.LIST.${key}`))
);
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
const startNew = () => router.push({ name: 'settings_flow_new' });
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
const dateOf = seconds =>
  new Date(seconds * 1000).toLocaleDateString(locale.value);
const categoryLabel = flow => {
  const values = flow.categories.length ? flow.categories : ['OTHER'];
  const first = t(`WHATSAPP_FLOWS.CATEGORIES.${values[0]}`);
  return values.length > 1 ? `${first} +${values.length - 1}` : first;
};
</script>

<template>
  <div class="grid gap-4" data-testid="flows-panel">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="text-heading-2 text-n-slate-12">
          {{ $t('WHATSAPP_FLOWS.LIST.TITLE') }}
        </h2>
        <p class="mt-1 mb-0 text-body-main text-n-slate-11">
          {{ $t('WHATSAPP_FLOWS.LIST.DESCRIPTION') }}
        </p>
      </div>
      <Button
        v-if="isAdmin"
        type="button"
        sm
        icon="i-lucide-plus"
        :label="$t('WHATSAPP_FLOWS.LIST.NEW')"
        data-testid="flow-new"
        @click="startNew"
      />
    </div>
    <div class="flex flex-wrap gap-3">
      <Input
        v-model="search"
        type="search"
        class="flex-1 min-w-48"
        :placeholder="$t('WHATSAPP_FLOWS.LIST.SEARCH')"
        :aria-label="$t('WHATSAPP_FLOWS.LIST.SEARCH')"
        data-testid="flows-search"
      />
      <div class="w-48">
        <ComboBox
          v-model="state"
          teleport
          :options="stateOptions"
          :allow-deselect="false"
          :aria-label="$t('WHATSAPP_FLOWS.LIST.STATE')"
          data-testid="flows-state"
        />
      </div>
      <div class="w-48">
        <ComboBox
          v-model="category"
          teleport
          :options="categoryOptions"
          :allow-deselect="false"
          :aria-label="$t('WHATSAPP_FLOWS.NEW.CATEGORIES')"
          data-testid="flows-category"
        />
      </div>
    </div>
    <Spinner v-if="isPending" class="text-n-slate-11" />
    <div v-else-if="failed">
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
    <div v-else class="overflow-x-auto">
      <BaseTable :headers="headers" :items="flows">
        <template #row>
          <BaseTableRow
            v-for="flow in flows"
            :key="flow.id"
            :item="flow"
            data-testid="flow-row"
          >
            <BaseTableCell>
              <span
                class="block max-w-56 truncate text-heading-3 text-n-slate-12"
                >{{ flow.name }}</span
              >
              <span
                v-if="flow.unpublished_changes"
                class="block mt-1 text-xs text-n-amber-11"
                data-testid="flow-unpublished-badge"
                >{{ $t('WHATSAPP_FLOWS.META.UNPUBLISHED_CHANGES_BADGE') }}</span
              >
            </BaseTableCell>
            <BaseTableCell>
              <span
                class="px-2 py-1 text-xs rounded-md whitespace-nowrap bg-n-alpha-2"
                :title="
                  flow.categories
                    .map(value => $t(`WHATSAPP_FLOWS.CATEGORIES.${value}`))
                    .join(', ')
                "
                >{{ categoryLabel(flow) }}</span
              >
            </BaseTableCell>
            <BaseTableCell align="center">
              <span
                :aria-label="
                  $t('WHATSAPP_FLOWS.LIST.SCREENS', { n: flow.screens })
                "
                >{{ flow.screens }}</span
              >
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-xs whitespace-nowrap">{{
                dateOf(flow.updated_at)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <FlowPublicationSummary
                v-if="isAdmin"
                :summary="flow.publication_summary"
                @details="publicationPanel.open(flow)"
              />
            </BaseTableCell>
            <BaseTableCell>
              <div v-if="isAdmin" class="flex gap-1">
                <Button
                  type="button"
                  ghost
                  slate
                  sm
                  icon="i-lucide-pencil"
                  :aria-label="$t('WHATSAPP_FLOWS.LIST.EDIT')"
                  data-testid="flow-edit"
                  @click="edit(flow)"
                />
                <Button
                  type="button"
                  ghost
                  slate
                  sm
                  icon="i-lucide-trash-2"
                  :aria-label="$t('WHATSAPP_FLOWS.LIST.DELETE')"
                  data-testid="flow-delete"
                  @click="askDelete(flow)"
                />
              </div>
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
    <PaginationFooter
      v-if="total"
      v-model:current-page="page"
      :total-items="total"
      :items-per-page="PAGE_SIZE"
      class="!px-0"
    />
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
