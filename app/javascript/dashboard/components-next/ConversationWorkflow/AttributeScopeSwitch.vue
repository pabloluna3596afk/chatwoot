<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const props = defineProps({
  conversationCount: {
    type: Number,
    default: 0,
  },
  contactCount: {
    type: Number,
    default: 0,
  },
});

const scope = defineModel({ type: String, default: 'conversation' });

const { t } = useI18n();

const tabs = computed(() => [
  {
    key: 'conversation',
    label: t('BUSINESS_RULES.FIELDS.SECTION_CONVERSATION'),
    count: props.conversationCount || undefined,
  },
  {
    key: 'contact',
    label: t('BUSINESS_RULES.FIELDS.SECTION_CONTACT'),
    count: props.contactCount || undefined,
  },
]);

const activeTabIndex = computed(() =>
  tabs.value.findIndex(tab => tab.key === scope.value)
);

const onTabChanged = tab => {
  scope.value = tab.key;
};
</script>

<template>
  <TabBar
    :tabs="tabs"
    :initial-active-tab="activeTabIndex"
    @tab-changed="onTabChanged"
  />
</template>
