<script>
// Copilot Loader Component
</script>

<template>
  <div class="flex justify-start" role="status" aria-live="polite">
    <div class="flex items-center space-x-2">
      <span class="text-n-slate-11 font-medium">
        {{ $t('CAPTAIN.COPILOT.LOADER') }}
      </span>
      <div class="flex space-x-1">
        <div
          class="size-2 rounded-full bg-n-blue-9 animate-bounce [animation-delay:-0.3s] motion-reduce:animate-none"
        />
        <div
          class="size-2 rounded-full bg-n-blue-9 animate-bounce [animation-delay:-0.15s] motion-reduce:animate-none"
        />
        <div
          class="size-2 rounded-full bg-n-blue-9 animate-bounce motion-reduce:animate-none"
        />
      </div>
    </div>
  </div>
</template>
