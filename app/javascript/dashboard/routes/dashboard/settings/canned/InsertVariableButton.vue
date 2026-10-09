<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { MESSAGE_VARIABLES } from 'shared/constants/messages';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import { useMapGetter } from 'dashboard/composables/store';

defineProps({
  label: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['insert']);

const { t, te } = useI18n();
const store = useStore();
const customAttributes = useMapGetter('attributes/getAttributes');

const resolveLabel = variable => {
  const labelKey = `VARIABLES.LABELS.${variable.key}`;
  return te(labelKey) ? t(labelKey) : variable.label;
};

const menuItems = computed(() => {
  const standard = MESSAGE_VARIABLES.map(variable => ({
    key: variable.key,
    label: resolveLabel(variable),
    description: variable.label,
  }));

  const custom = (customAttributes.value || []).map(attribute => {
    const prefix =
      attribute.attribute_model === 'conversation_attribute'
        ? 'conversation'
        : 'contact';
    const key = `${prefix}.custom_attribute.${attribute.attribute_key}`;
    return {
      key,
      label: attribute.attribute_display_name || attribute.attribute_key,
      description:
        attribute.attribute_description ||
        attribute.attribute_display_name ||
        attribute.attribute_key,
    };
  });

  return [...standard, ...custom].map(variable => ({
    action: variable.key,
    label: `${variable.label} ({{${variable.key}}})`,
    value: variable.key,
  }));
});

const showMenu = ref(false);

const toggleMenu = () => {
  showMenu.value = !showMenu.value;
};

const closeMenu = () => {
  showMenu.value = false;
};

const onAction = item => {
  emit('insert', item.action);
  closeMenu();
};

onMounted(() => {
  if (!customAttributes.value?.length) {
    store.dispatch('attributes/get');
  }
});
</script>

<template>
  <MenuPopover
    v-model:open="showMenu"
    :menu-items="menuItems"
    show-search
    :search-placeholder="t('VARIABLES.SEARCH_PLACEHOLDER')"
    panel-class="min-w-[16rem] max-w-[calc(100vw-2rem)]"
    :restore-focus-on-select="false"
    align="start"
    @action="onAction"
  >
    <template #trigger>
      <NextButton
        type="button"
        sm
        slate
        faded
        icon="i-lucide-braces"
        :label="label || t('VARIABLES.INSERT')"
        @click.prevent="toggleMenu"
      />
    </template>
  </MenuPopover>
</template>
