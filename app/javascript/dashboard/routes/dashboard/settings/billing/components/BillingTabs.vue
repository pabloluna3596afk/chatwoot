<script setup>
import { computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import TabBar from 'next/tabbar/TabBar.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const tabKeys = ['uso', 'facturacion'];
const tabs = computed(() => [
  {
    key: 'uso',
    label: t('BILLING_SETTINGS.TABS.USO'),
    id: 'billing-tab-uso',
    controls: 'billing-panel-uso',
  },
  {
    key: 'facturacion',
    label: t('BILLING_SETTINGS.TABS.FACTURACION'),
    id: 'billing-tab-facturacion',
    controls: 'billing-panel-facturacion',
  },
]);
const selectTab = tab => {
  router.replace({ query: { ...route.query, tab } });
};

const activeTab = computed(() =>
  tabKeys.includes(route.query.tab) ? route.query.tab : 'uso'
);
onMounted(() => {
  if (!tabKeys.includes(route.query.tab)) selectTab('uso');
});
</script>

<template>
  <TabBar
    :tabs="tabs"
    :initial-active-tab="tabKeys.indexOf(activeTab)"
    :tab-list-label="$t('BILLING_SETTINGS.TABS.LABEL')"
    @tab-changed="selectTab($event.key)"
  />
</template>
