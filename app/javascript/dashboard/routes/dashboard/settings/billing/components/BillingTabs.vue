<script setup>
import { computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';

const route = useRoute();
const router = useRouter();
const tabs = ['uso', 'facturacion'];
const selectTab = tab => {
  router.replace({ query: { ...route.query, tab } });
};

const activeTab = computed(() =>
  tabs.includes(route.query.tab) ? route.query.tab : 'uso'
);
onMounted(() => {
  if (!tabs.includes(route.query.tab)) selectTab('uso');
});

const onKeydown = event => {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
  event.preventDefault();
  const current = tabs.indexOf(activeTab.value);
  let next =
    (current + (event.key === 'ArrowRight' ? 1 : tabs.length - 1)) %
    tabs.length;
  if (event.key === 'Home') next = 0;
  if (event.key === 'End') next = tabs.length - 1;
  selectTab(tabs[next]);
  requestAnimationFrame(() =>
    document.getElementById(`billing-tab-${tabs[next]}`)?.focus()
  );
};
</script>

<template>
  <div
    class="mb-5 border-b border-n-weak"
    role="tablist"
    :aria-label="$t('BILLING_SETTINGS.TABS.LABEL')"
    @keydown="onKeydown"
  >
    <button
      v-for="tab in tabs"
      :id="`billing-tab-${tab}`"
      :key="tab"
      type="button"
      role="tab"
      class="me-5 border-b-2 px-1 py-3 text-sm font-medium focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
      :class="
        activeTab === tab
          ? 'border-n-blue-9 text-n-blue-11'
          : 'border-transparent text-n-slate-11'
      "
      :aria-selected="activeTab === tab"
      :aria-controls="`billing-panel-${tab}`"
      :tabindex="activeTab === tab ? 0 : -1"
      @click="selectTab(tab)"
    >
      {{
        tab === 'uso'
          ? $t('BILLING_SETTINGS.TABS.USO')
          : $t('BILLING_SETTINGS.TABS.FACTURACION')
      }}
    </button>
  </div>
</template>
