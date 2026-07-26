<script>
  import { SendNUI } from '@utils/SendNUI'
  import Plate from './Plate.svelte'
  import { timeAgo } from '@utils/timeAgo'
  import { slide } from 'svelte/transition'
  import { DUR, EASE_OUT } from '@utils/motion'

  export let hit;
  export let expanded = false;

  // Backup is the one action here that leaves this client, so it gets a
  // two-step confirm — an accidental click would put a priority call on
  // everyone's board.
  // Copying the plate: navigator.clipboard needs a secure context, which the
  // NUI is not, so the old textarea trick is the one that actually works here.
  let copied = false;
  function copyPlate() {
    const text = hit.plate;
    try {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.cssText = 'position:fixed;opacity:0;pointer-events:none;';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      ta.remove();
      copied = true;
      setTimeout(() => (copied = false), 1400);
    } catch { /* nothing sensible to say if the host blocks it */ }
  }

  let confirmBackup = false;
  let backupSent = false;
  let backupError = '';

  // Collapsing the row resets the pending confirm, otherwise it silently
  // waits armed for the next time the row is opened.
  $: if (!expanded) confirmBackup = false;

  async function requestBackup() {
    if (!confirmBackup) { confirmBackup = true; return; }
    confirmBackup = false;
    const res = await SendNUI('plateBackup', { id: hit.id });
    if (res && res.ok === false) {
      backupError = res.message || 'Could not request backup';
      setTimeout(() => backupError = '', 2600);
    } else {
      backupSent = true;
      setTimeout(() => backupSent = false, 6000);
    }
  }
</script>

<div class="pd-plate-hit {hit.tone === 'alert' ? 'pd-plate-hit--alert' : ''}">
  <button class="pd-row {hit.tone === 'alert' ? 'pd-row--priority' : ''}" class:pd-row--open={expanded} on:click>
    <div class="pd-icon {hit.tone === 'alert' ? 'pd-icon--priority' : ''}">
      <i class="fas fa-car-side"></i>
    </div>

    <div class="flex flex-col min-w-0 flex-1 gap-[2px]">
      <div class="flex items-center gap-[6px]">
        <Plate plate={hit.plate} index={hit.plateIndex} />
        <!-- Sits with the plate rather than among the actions below: it acts on
             the plate, and it is a convenience, not a decision. -->
        <span
          class="pd-copy"
          class:pd-copy--done={copied}
          role="button"
          tabindex="-1"
          title={copied ? 'Copied' : 'Copy plate'}
          on:click|stopPropagation={copyPlate}
          on:keydown|stopPropagation
        >
          <i class="fas {copied ? 'fa-check' : 'fa-copy'}"></i>
        </span>
        {#if hit.footerText}
          <!-- The MDT already phrased the verdict; echo it rather than
               re-deciding what "flagged" means here. -->
          <span class="pd-badge {hit.tone === 'alert' ? 'pd-badge--red' : 'pd-badge--green'} truncate">
            {#if hit.footerIcon}<i class="{hit.footerIcon} mr-[3px]"></i>{/if}{hit.footerText}
          </span>
        {/if}
      </div>
      <div class="flex items-center gap-[8px]">
        {#if hit.vehicle}
          <span class="text-[10px] opacity-50 truncate">{hit.vehicle}</span>
        {/if}
        <span class="pd-time">{timeAgo(hit.stamp)}</span>
      </div>
    </div>

    <i class="fas fa-chevron-{expanded ? 'up' : 'down'} text-[9px] opacity-35 flex-shrink-0"></i>
  </button>

  {#if expanded}
    <div class="pd-detail" transition:slide={{ duration: DUR.base, easing: EASE_OUT }}>
      {#if hit.street}
        <div class="pd-strip">
          <div class="pd-strip-row">
            <i class="fas fa-location-dot text-[10px] opacity-50"></i>
            <span class="pd-strip-title">{hit.street}</span>
          </div>
        </div>
      {/if}

      {#if hit.vehicle || hit.owner}
        <div class="pd-strip">
          <div class="pd-strip-row">
            <i class="fas fa-car text-[10px] opacity-50"></i>
            <span class="pd-strip-title">{hit.vehicle || 'Unknown vehicle'}</span>
          </div>
          {#if hit.owner}
            <div class="pd-strip-badges">
              <span class="pd-badge"><i class="fas fa-user mr-[3px]"></i>{hit.owner}</span>
            </div>
          {/if}
        </div>
      {/if}

      {#if hit.summary}
        <div class="pd-note">{hit.summary}</div>
      {/if}

      {#if backupError}
        <div class="pd-note pd-note--dispatch">{backupError}</div>
      {/if}

      <div class="flex gap-[5px] mt-[8px]">
        <button
          class="pd-btn {backupSent ? 'pd-btn--green' : confirmBackup ? 'pd-btn--red' : ''} flex-1"
          disabled={backupSent}
          on:click|stopPropagation={requestBackup}
        >
          {#if backupSent}
            <i class="fas fa-circle-check"></i> Backup requested
          {:else if confirmBackup}
            <i class="fas fa-triangle-exclamation"></i> Confirm — alert all units
          {:else}
            <i class="fas fa-users-line"></i> Request backup
          {/if}
        </button>
        <button class="pd-btn" on:click|stopPropagation={() => SendNUI('clearPlateHits', { id: hit.id })}>
          <i class="fas fa-xmark"></i> Dismiss
        </button>
      </div>
    </div>
  {/if}
</div>