<script setup>
import { computed, ref, watch } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import { errorLines } from './useFlowPublications';

const props = defineProps({
  api: { type: Object, default: () => WhatsappFlowsAPI },
});
const emit = defineEmits(['updated']);
const { t } = useI18n();
const PAGE_SIZE = 5;
const ERROR_STATES = ['error', 'blocked', 'throttled'];
const STATES = ['published', 'error', 'none', 'draft', 'deprecated'];
const panel = ref(null);
const flow = ref(null);
const rows = ref([]);
const total = ref(0);
const summary = ref(null);
const page = ref(1);
const search = ref('');
const state = ref('all');
const refresh = ref(0);
const failed = ref(false);
const retrying = ref(null);
const { run, abort, isPending } = useAbortableRequest();
const stateOptions = computed(() => [
  { value: 'all', label: t('WHATSAPP_FLOWS.LIST.ALL_STATES') },
  ...STATES.map(value => ({
    value,
    label: t(`WHATSAPP_FLOWS.META.STATE.${value}`),
  })),
]);
const tones = {
  published: 'bg-n-teal-3 text-n-teal-11',
  none: 'bg-n-alpha-2 text-n-slate-11',
  draft: 'bg-n-amber-3 text-n-amber-11',
  error: 'bg-n-ruby-3 text-n-ruby-11',
  blocked: 'bg-n-ruby-3 text-n-ruby-11',
  throttled: 'bg-n-ruby-3 text-n-ruby-11',
  deprecated: 'bg-n-alpha-2 text-n-slate-11',
};
const load = async () => {
  if (!flow.value) return;
  failed.value = false;
  try {
    await run(async signal => {
      const { data } = await props.api.publicationStatus(
        flow.value.id,
        {
          page: page.value,
          per_page: PAGE_SIZE,
          ...(search.value.trim() ? { search: search.value.trim() } : {}),
          ...(state.value !== 'all' ? { state: state.value } : {}),
        },
        { signal }
      );
      if (signal.aborted) return;
      rows.value = data.rows;
      total.value = data.meta.total_count;
      summary.value = data.publication_summary;
      emit('updated');
      if (!rows.value.length && total.value && page.value > 1)
        page.value = Math.ceil(total.value / PAGE_SIZE);
    });
  } catch {
    failed.value = true;
  }
};
watch(
  [search, state],
  () => {
    page.value = 1;
  },
  { flush: 'sync' }
);
watch([flow, page, search, state, refresh], useDebounceFn(load, 200));
const open = selected => {
  rows.value = [];
  total.value = 0;
  summary.value = selected.publication_summary;
  search.value = '';
  state.value = 'all';
  page.value = 1;
  flow.value = selected;
  refresh.value += 1;
  panel.value.open();
};
const close = () => {
  flow.value = null;
  abort();
};
const retry = async row => {
  retrying.value = row.waba_id;
  try {
    await props.api.retryPublication(flow.value.id, row.waba_id);
    useAlert(t('WHATSAPP_FLOWS.META.DETAIL.RETRY_QUEUED'));
    await load();
  } catch {
    useAlert(t('WHATSAPP_FLOWS.META.PUBLISH_ERROR'));
  } finally {
    retrying.value = null;
  }
};
defineExpose({ open });
</script>

<template>
  <SidePanel
    ref="panel"
    width="xl"
    :title="$t('WHATSAPP_FLOWS.META.DETAIL.TITLE')"
    :description="flow?.name"
    @close="close"
  >
    <div class="grid gap-4" data-testid="flow-publication-panel">
      <p v-if="summary" class="m-0 text-xs text-n-slate-11">
        {{ $t('WHATSAPP_FLOWS.META.DETAIL.COUNTS', summary) }}
      </p>
      <p class="m-0 text-xs text-n-slate-11">
        {{ $t('WHATSAPP_FLOWS.META.DETAIL.UNIT') }}
      </p>
      <div class="flex gap-2">
        <Input
          v-model="search"
          type="search"
          :placeholder="$t('WHATSAPP_FLOWS.META.DETAIL.SEARCH')"
          :aria-label="$t('WHATSAPP_FLOWS.META.DETAIL.SEARCH')"
          class="flex-1 min-w-0"
          data-testid="waba-search"
        />
        <div class="w-44 shrink-0">
          <ComboBox
            v-model="state"
            teleport
            :options="stateOptions"
            :allow-deselect="false"
            :aria-label="$t('WHATSAPP_FLOWS.LIST.STATE')"
            data-testid="waba-state"
          />
        </div>
      </div>
      <Spinner v-if="isPending" class="text-n-slate-11" />
      <div v-else-if="failed" class="grid gap-3">
        <p class="m-0 text-sm text-n-ruby-11">
          {{ $t('WHATSAPP_FLOWS.LIST.LOAD_ERROR') }}
        </p>
        <Button
          type="button"
          faded
          slate
          :label="$t('WHATSAPP_FLOWS.META.RETRY')"
          @click="load"
        />
      </div>
      <div v-else class="border-t divide-y border-n-weak divide-n-weak">
        <div
          v-for="row in rows"
          :key="row.waba_id"
          class="grid gap-2 py-4"
          data-testid="waba-row"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <h4 class="m-0 text-sm font-medium truncate">
                {{ row.numbers[0].inbox_name || row.waba_id }}
              </h4>
              <p class="m-0 mt-1 text-xs text-n-slate-11">
                {{
                  $t('WHATSAPP_FLOWS.META.DETAIL.WABA_ID', { id: row.waba_id })
                }}
              </p>
            </div>
            <span
              class="px-2.5 py-1 text-xs rounded-full shrink-0"
              :class="tones[row.state]"
            >
              {{ $t(`WHATSAPP_FLOWS.META.STATE.${row.state}`) }}
            </span>
          </div>
          <p
            v-for="number in row.numbers"
            :key="number.channel_id"
            class="m-0 text-xs text-n-slate-11"
          >
            {{ number.inbox_name }} · {{ number.phone_number }}
          </p>
          <ul
            v-if="row.validation_errors.length"
            class="grid gap-1 p-0 m-0 text-xs list-none text-n-ruby-11"
          >
            <li
              v-for="(error, index) in errorLines(row.validation_errors)"
              :key="index"
            >
              <code v-if="error.path">{{ error.path }}: </code
              >{{ error.message }}
            </li>
          </ul>
          <Button
            v-if="ERROR_STATES.includes(row.state)"
            type="button"
            ghost
            slate
            xs
            icon="i-lucide-rotate-cw"
            :label="$t('WHATSAPP_FLOWS.META.RETRY')"
            :is-loading="retrying === row.waba_id"
            :disabled="retrying !== null"
            class="justify-self-end"
            data-testid="waba-retry"
            @click="retry(row)"
          />
        </div>
        <p v-if="!rows.length" class="py-6 text-sm text-center text-n-slate-11">
          {{ $t('WHATSAPP_FLOWS.META.DETAIL.EMPTY') }}
        </p>
      </div>
    </div>
    <template #footer>
      <PaginationFooter
        v-if="total"
        v-model:current-page="page"
        :total-items="total"
        :items-per-page="PAGE_SIZE"
        class="!px-0"
      />
      <div class="flex items-center justify-between gap-3 mt-3">
        <p class="m-0 text-xs text-n-slate-11">
          {{ $t('WHATSAPP_FLOWS.META.DETAIL.ALL_WABAS') }}
        </p>
        <Button
          type="button"
          faded
          slate
          sm
          icon="i-lucide-refresh-cw"
          :label="$t('WHATSAPP_FLOWS.META.DETAIL.REFRESH')"
          :disabled="isPending"
          @click="load"
        />
      </div>
    </template>
  </SidePanel>
</template>
