<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Label from 'dashboard/components-next/label/Label.vue';

const props = defineProps({
  item: { type: Object, required: true },
  group: { type: Object, required: true },
});
const emit = defineEmits(['focusTemplatesToggle']);
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const expanded = ref(false);

const title = computed(() => {
  const base = t(
    `CAPTAIN.ASSISTANTS.CAPABILITIES.ITEMS.${props.item.id}.TITLE`
  );
  return props.item.count > 0
    ? `${base} ${t('CAPTAIN.ASSISTANTS.CAPABILITIES.COUNT_SUFFIX', { count: props.item.count })}`
    : base;
});
const isMixed = computed(() => {
  const inboxes = props.item.inboxes || [];
  return (
    props.item.status === 'ready' &&
    inboxes.length > 1 &&
    inboxes.some(inbox => inbox.status !== inboxes[0].status)
  );
});
const readyInboxes = computed(
  () =>
    (props.item.inboxes || []).filter(inbox => inbox.status === 'ready').length
);
const description = computed(() => {
  if (isMixed.value)
    return t('CAPTAIN.ASSISTANTS.CAPABILITIES.INBOXES.SUMMARY', {
      ready: readyInboxes.value,
      total: props.item.inboxes.length,
    });
  if (props.item.reason)
    return t(`CAPTAIN.ASSISTANTS.CAPABILITIES.REASONS.${props.item.reason}`);
  return t(
    `CAPTAIN.ASSISTANTS.CAPABILITIES.ITEMS.${props.item.id}.DESCRIPTION`
  );
});
const stateColor = computed(
  () =>
    ({
      ready: 'teal',
      needs_setup: 'amber',
      not_connected: 'blue',
      off: 'slate',
    })[props.item.status]
);
const stateIcon = computed(
  () =>
    ({
      ready: 'i-lucide-circle-check',
      needs_setup: 'i-lucide-wrench',
      not_connected: 'i-lucide-plug',
      off: 'i-lucide-power-off',
    })[props.item.status]
);
const actionKey = computed(
  () =>
    ({ not_connected: 'connect', off: 'turn_on' })[props.item.status] ||
    'configure'
);
const actionLabel = computed(() =>
  t('CAPTAIN.ASSISTANTS.CAPABILITIES.ACTION_LABEL', {
    action: t(`CAPTAIN.ASSISTANTS.CAPABILITIES.ACTIONS.${actionKey.value}`),
    title: title.value,
  })
);
const inboxes = computed(() => props.item.inboxes || []);
const inboxStatusColor = status =>
  ({
    ready: 'teal',
    needs_setup: 'amber',
    not_connected: 'blue',
    off: 'slate',
  })[status];
const inboxStatusIcon = status =>
  ({
    ready: 'i-lucide-circle-check',
    needs_setup: 'i-lucide-wrench',
    not_connected: 'i-lucide-plug',
    off: 'i-lucide-power-off',
  })[status];

const focusAnchor = async () => {
  await new Promise(resolve => {
    requestAnimationFrame(resolve);
  });
  const target = document.querySelector(
    `[data-testid="${props.item.configure_anchor}"]`
  );
  target?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  target?.focus();
};
const navigate = async routeName => {
  if (!routeName) return;
  await router.push({
    name: routeName,
    params: {
      accountId: route.params.accountId,
      assistantId: route.params.assistantId,
    },
  });
  if (props.item.configure_anchor) await focusAnchor();
};
const onAction = async () => {
  if (props.item.reason === 'templates_off') {
    emit('focusTemplatesToggle');
    return;
  }
  const routeName =
    props.item.status === 'not_connected'
      ? props.group.connect_route
      : props.item.configure_route;
  await navigate(routeName);
};
</script>

<template>
  <li
    class="grid grid-cols-1 gap-1.5 p-3 md:grid-cols-[minmax(0,1fr)_auto_auto_auto] md:items-center md:gap-x-3"
    :class="item.status === 'ready' ? '' : 'bg-n-alpha-1'"
    data-testid="capability-row"
  >
    <span class="min-w-0 text-sm font-medium text-n-slate-12">
      {{ title }}
    </span>
    <span
      v-if="item.status !== 'not_connected'"
      class="text-xs text-n-slate-11 md:text-right"
      data-testid="capability-kind"
    >
      {{ t(`CAPTAIN.ASSISTANTS.CAPABILITIES.KIND.${item.kind}`) }}
    </span>
    <Label
      :label="t(`CAPTAIN.ASSISTANTS.CAPABILITIES.STATUS.${item.status}`)"
      :color="stateColor"
      compact
      class="w-fit"
    >
      <template #icon>
        <Icon :icon="stateIcon" class="size-3.5" aria-hidden="true" />
      </template>
    </Label>
    <button
      type="button"
      class="w-fit px-0 py-1 text-sm font-medium text-n-brand hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
      :aria-label="actionLabel"
      data-testid="capability-action"
      @click="onAction"
    >
      {{ t(`CAPTAIN.ASSISTANTS.CAPABILITIES.ACTIONS.${actionKey}`) }}
    </button>
    <p class="min-w-0 mb-0 text-xs text-n-slate-11 md:col-span-full">
      {{ description }}
    </p>
    <template v-if="isMixed">
      <button
        type="button"
        class="w-fit px-0 py-1 text-sm text-n-brand hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
        :aria-expanded="expanded"
        :aria-controls="`capability-inboxes-${item.id}`"
        @click="expanded = !expanded"
      >
        {{
          t(
            `CAPTAIN.ASSISTANTS.CAPABILITIES.INBOXES.${expanded ? 'HIDE' : 'SHOW'}`
          )
        }}
      </button>
      <ul
        v-if="expanded"
        :id="`capability-inboxes-${item.id}`"
        class="flex flex-col gap-2 p-0 m-0 list-none md:col-span-full"
      >
        <li
          v-for="inbox in inboxes"
          :key="inbox.inbox_id"
          class="flex flex-wrap items-center gap-2 text-sm text-n-slate-11"
        >
          <span class="min-w-28 font-medium text-n-slate-12">{{
            inbox.inbox_name
          }}</span>
          <Label
            :label="t(`CAPTAIN.ASSISTANTS.CAPABILITIES.STATUS.${inbox.status}`)"
            :color="inboxStatusColor(inbox.status)"
            compact
          >
            <template #icon>
              <Icon
                :icon="inboxStatusIcon(inbox.status)"
                class="size-3.5"
                aria-hidden="true"
              />
            </template>
          </Label>
          <span v-if="inbox.status !== 'ready' && inbox.reason">
            {{ t(`CAPTAIN.ASSISTANTS.CAPABILITIES.REASONS.${inbox.reason}`) }}
          </span>
        </li>
      </ul>
    </template>
  </li>
</template>
