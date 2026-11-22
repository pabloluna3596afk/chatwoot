<script setup>
import { computed, inject, ref } from 'vue';
import { useDropdownPosition } from 'dashboard/composables/useDropdownPosition';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const { trigger } = defineProps({
  trigger: {
    type: Function,
    required: true,
  },
});

const menuRef = ref(null);

// Inside a native <dialog> (top layer) a menu on <body> would render underneath it.
const dialogPortalTarget = inject('dialogPortalTarget', null);
const teleportTarget = computed(() => dialogPortalTarget?.value || 'body');

const { fixedPosition } = useDropdownPosition(trigger, menuRef, true, {
  align: 'start',
});
</script>

<template>
  <TeleportWithDirection :to="teleportTarget">
    <div
      data-dropdown-menu
      class="overflow-y-auto"
      :class="fixedPosition.class"
      :style="fixedPosition.style"
    >
      <div ref="menuRef" class="[&>*]:!static">
        <slot />
      </div>
    </div>
  </TeleportWithDirection>
</template>
