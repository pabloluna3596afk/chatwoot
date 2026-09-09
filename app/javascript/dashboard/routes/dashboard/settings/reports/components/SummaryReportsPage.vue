<script setup>
import { computed, ref } from 'vue';
import ReportHeader from './ReportHeader.vue';
import SummaryReports from './SummaryReports.vue';
import V4Button from 'dashboard/components-next/button/Button.vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

defineProps({
  headerTitle: { type: String, required: true },
  headerDescription: { type: String, required: true },
  downloadLabel: { type: String, required: true },
  actionKey: { type: String, required: true },
  getterKey: { type: String, required: true },
  fetchItemsKey: { type: String, required: true },
  summaryKey: { type: String, required: true },
  type: { type: String, required: true },
});

const summarReportsRef = ref(null);
const isDownloadMenuOpen = ref(false);

const { isCloudFeatureEnabled } = useAccount();
const canDownloadReports = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.REPORT_EXPORT)
);

const onDownloadClick = exportFormat => {
  isDownloadMenuOpen.value = false;
  summarReportsRef.value?.downloadReports(exportFormat);
};
</script>

<template>
  <ReportHeader
    :header-title="headerTitle"
    :header-description="headerDescription"
  >
    <div v-if="canDownloadReports" class="relative">
      <V4Button
        :label="downloadLabel"
        icon="i-ph-download-simple"
        size="sm"
        @click="isDownloadMenuOpen = !isDownloadMenuOpen"
      />
      <div
        v-if="isDownloadMenuOpen"
        v-on-clickaway="() => (isDownloadMenuOpen = false)"
        class="absolute top-full mt-1 ltr:right-0 rtl:left-0 z-50 flex flex-col min-w-[10rem] rounded-lg border border-n-weak bg-n-alpha-3 backdrop-blur-[100px] shadow-md overflow-hidden"
      >
        <button
          type="button"
          class="px-3 py-2 text-sm text-start text-n-slate-12 hover:bg-n-alpha-2"
          @click="onDownloadClick('csv')"
        >
          {{ $t('REPORT.DOWNLOAD_FORMAT_CSV') }}
        </button>
        <button
          type="button"
          class="px-3 py-2 text-sm text-start text-n-slate-12 hover:bg-n-alpha-2"
          @click="onDownloadClick('xlsx')"
        >
          {{ $t('REPORT.DOWNLOAD_FORMAT_EXCEL') }}
        </button>
      </div>
    </div>
  </ReportHeader>

  <SummaryReports
    ref="summarReportsRef"
    :action-key="actionKey"
    :getter-key="getterKey"
    :fetch-items-key="fetchItemsKey"
    :summary-key="summaryKey"
    :type="type"
  />
</template>
