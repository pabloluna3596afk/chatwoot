<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import ReportHeader from '../components/ReportHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SavedReportPanelsAPI from 'dashboard/api/savedReportPanels';
import fromUnixTime from 'date-fns/fromUnixTime';
import { formatPanelDate } from './panelConstants';

const { t } = useI18n();
const { resolvedLocale: locale } = useLocale();
const numberFormatter = computed(
  () => new Intl.NumberFormat(locale.value, { useGrouping: true })
);
const router = useRouter();
const { accountScopedRoute } = useAccount();

const loading = ref(true);
const panels = ref([]);

const sortedPanels = computed(() =>
  [...panels.value].sort((a, b) => Number(b.favorite) - Number(a.favorite))
);

const fetchPanels = async () => {
  loading.value = true;
  try {
    const { data } = await SavedReportPanelsAPI.get();
    panels.value = data;
  } catch {
    useAlert(t('REPORT_PANELS.ERRORS.LOAD'));
  } finally {
    loading.value = false;
  }
};

const openPanel = id => {
  router.push(accountScopedRoute('report_panels_show', { id }));
};

const editPanel = id => {
  router.push(accountScopedRoute('report_panels_edit', { id }));
};

const createPanel = () => {
  router.push(accountScopedRoute('report_panels_new'));
};

const periodLabel = panel => {
  const key = panel.date_preset?.toUpperCase();
  return key
    ? t(`REPORT_PANELS.DATE_PRESETS.${key}`)
    : t('REPORT_PANELS.DATE_PRESETS.LAST_7_DAYS');
};

const widgetCount = panel =>
  Array.isArray(panel.widgets) ? panel.widgets.length : 0;

const filterCount = panel =>
  Array.isArray(panel.filters) ? panel.filters.length : 0;

const updatedLabel = panel => {
  if (!panel.updated_at) return '—';
  return formatPanelDate(fromUnixTime(panel.updated_at), locale.value);
};

const toggleFavorite = async panel => {
  try {
    const { data } = await SavedReportPanelsAPI.update(panel.id, {
      saved_report_panel: { favorite: !panel.favorite },
    });
    panels.value = panels.value.map(item =>
      item.id === panel.id ? data : item
    );
  } catch {
    useAlert(t('REPORT_PANELS.ERRORS.SAVE'));
  }
};

onMounted(fetchPanels);
</script>

<template>
  <div class="w-full min-w-0">
    <ReportHeader
      :header-title="t('REPORT_PANELS.HEADER')"
      :header-description="t('REPORT_PANELS.DESCRIPTION')"
    >
      <Button
        :label="t('REPORT_PANELS.CREATE')"
        icon="i-lucide-plus"
        size="sm"
        @click="createPanel"
      />
    </ReportHeader>

    <p class="text-sm text-n-slate-11 mb-4 -mt-2 max-w-4xl">
      {{ t('REPORT_PANELS.LIST.SCOPE_HINT') }}
    </p>

    <div v-if="loading" class="flex justify-center py-16">
      <Spinner />
    </div>

    <div
      v-else-if="!sortedPanels.length"
      class="rounded-xl border border-dashed border-n-weak p-10 text-center text-n-slate-11"
    >
      <p class="mb-4">{{ t('REPORT_PANELS.EMPTY') }}</p>
      <Button
        :label="t('REPORT_PANELS.CREATE')"
        size="sm"
        @click="createPanel"
      />
    </div>

    <div
      v-else
      class="rounded-xl border border-n-weak bg-n-solid-2 overflow-x-auto min-w-0 max-w-full"
    >
      <table class="w-full min-w-[40rem] table-fixed divide-y divide-n-weak">
        <thead class="border-t border-n-weak">
          <tr>
            <th
              scope="col"
              class="py-4 px-4 text-start text-body-main font-medium text-n-slate-12 w-[32%] sticky start-0 z-20 bg-n-solid-2"
            >
              <span
                class="block truncate"
                :title="t('REPORT_PANELS.LIST.COLUMNS.NAME')"
              >
                {{ t('REPORT_PANELS.LIST.COLUMNS.NAME') }}
              </span>
            </th>
            <th
              scope="col"
              class="py-4 px-4 text-start text-body-main font-medium text-n-slate-12 w-[18%]"
            >
              <span
                class="block truncate"
                :title="t('REPORT_PANELS.LIST.COLUMNS.PERIOD')"
              >
                {{ t('REPORT_PANELS.LIST.COLUMNS.PERIOD') }}
              </span>
            </th>
            <th
              scope="col"
              class="py-4 px-4 text-end text-body-main font-medium text-n-slate-12 w-[10%]"
            >
              <span
                class="block truncate"
                :title="t('REPORT_PANELS.LIST.COLUMNS.WIDGETS')"
              >
                {{ t('REPORT_PANELS.LIST.COLUMNS.WIDGETS') }}
              </span>
            </th>
            <th
              scope="col"
              class="py-4 px-4 text-end text-body-main font-medium text-n-slate-12 w-[10%]"
            >
              <span
                class="block truncate"
                :title="t('REPORT_PANELS.LIST.COLUMNS.FILTERS')"
              >
                {{ t('REPORT_PANELS.LIST.COLUMNS.FILTERS') }}
              </span>
            </th>
            <th
              scope="col"
              class="py-4 px-4 text-start text-body-main font-medium text-n-slate-12 w-[14%]"
            >
              <span
                class="block truncate"
                :title="t('REPORT_PANELS.LIST.COLUMNS.UPDATED')"
              >
                {{ t('REPORT_PANELS.LIST.COLUMNS.UPDATED') }}
              </span>
            </th>
            <th
              scope="col"
              class="py-4 px-4 text-end text-body-main font-medium text-n-slate-12 w-[16%]"
            >
              <span
                class="block truncate"
                :title="t('REPORT_PANELS.LIST.COLUMNS.ACTIONS')"
              >
                {{ t('REPORT_PANELS.LIST.COLUMNS.ACTIONS') }}
              </span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr
            v-for="panel in sortedPanels"
            :key="panel.id"
            class="cursor-pointer hover:bg-n-alpha-2"
            @click="openPanel(panel.id)"
          >
            <td class="py-3 px-4 min-w-0 sticky start-0 z-10 bg-n-solid-2">
              <div class="flex flex-col gap-0.5 min-w-0">
                <div class="flex items-center gap-2 min-w-0">
                  <span
                    class="text-body-main text-n-slate-12 truncate font-medium"
                    :title="panel.name"
                  >
                    {{ panel.name }}
                  </span>
                  <span
                    v-if="panel.favorite"
                    class="shrink-0 text-xs text-n-amber-11"
                  >
                    {{ t('REPORT_PANELS.FAVORITE') }}
                  </span>
                </div>
                <span
                  v-if="panel.description"
                  class="text-sm text-n-slate-11 truncate"
                  :title="panel.description"
                >
                  {{ panel.description }}
                </span>
              </div>
            </td>
            <td class="py-3 px-4 text-body-main text-n-slate-12">
              <span class="line-clamp-2">{{ periodLabel(panel) }}</span>
            </td>
            <td
              class="py-3 px-4 text-body-main text-n-slate-12 text-end whitespace-nowrap"
            >
              {{ numberFormatter.format(widgetCount(panel)) }}
            </td>
            <td
              class="py-3 px-4 text-body-main text-n-slate-12 text-end whitespace-nowrap"
            >
              {{ numberFormatter.format(filterCount(panel)) }}
            </td>
            <td class="py-3 px-4 text-body-main text-n-slate-11">
              <span class="block truncate" :title="updatedLabel(panel)">{{
                updatedLabel(panel)
              }}</span>
            </td>
            <td class="py-3 px-4">
              <div class="flex items-center justify-end gap-1">
                <Button
                  variant="ghost"
                  size="sm"
                  icon="i-lucide-star"
                  :class="panel.favorite ? 'text-n-amber-11' : 'text-n-slate-9'"
                  :aria-label="t('REPORT_PANELS.FAVORITE')"
                  @click.stop="toggleFavorite(panel)"
                />
                <Button
                  variant="ghost"
                  size="sm"
                  icon="i-lucide-pencil"
                  :aria-label="t('REPORT_PANELS.EDIT')"
                  @click.stop="editPanel(panel.id)"
                />
                <Button
                  variant="ghost"
                  size="sm"
                  icon="i-lucide-arrow-right"
                  :aria-label="t('REPORT_PANELS.OPEN')"
                  @click.stop="openPanel(panel.id)"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
