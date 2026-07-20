<script>
  import { DISPATCH_MENU, DISPATCH_MUTED, DISPATCH_DISABLED, STATS, processedDispatchMenu } from '@store/stores';
  import { fly } from 'svelte/transition';
  import { SendNUI } from '@utils/SendNUI'
  import CallRow from './CallRow.svelte'

  let activeCallId = null;
  let statsOpen = false;

  // Dispatch board split: calls being worked (≥1 unit) live on the Active
  // Calls panel to the left; the main list keeps only what still needs
  // someone. `unitsLive` comes from unitCount pushes, so a call wanders over
  // the moment ANYONE attaches — no list refresh needed.
  // unitsLive (when a push has arrived) beats the possibly stale units array
  // in BOTH directions — a remote detach to zero must move the call back.
  $: hasUnits = (d) => d.unitsLive !== undefined ? d.unitsLive > 0 : (d.units?.length || 0) > 0;
  $: pendingCalls = $processedDispatchMenu.filter(d => !hasUnits(d));
  $: activeCalls = $processedDispatchMenu.filter(d => hasUnits(d));

  function toggleStats() {
    statsOpen = !statsOpen;
    if (statsOpen) SendNUI('getStats'); // response arrives as a 'stats' push
  }

  function fmtAvg(ms) {
    const sec = Math.round((ms || 0) / 1000);
    if (sec < 60) return sec + 's';
    return Math.floor(sec / 60) + 'm ' + String(sec % 60).padStart(2, '0') + 's';
  }

  function toggleDispatch(id) {
    activeCallId = activeCallId === id ? null : id;
  }

  function toggleMute() {
    DISPATCH_MUTED.update(value => !value);
    SendNUI("toggleMute", { boolean: $DISPATCH_MUTED });
  }

  function toggleAlerts() {
    DISPATCH_DISABLED.update(value => !value);
    SendNUI("toggleAlerts", { boolean: $DISPATCH_DISABLED });
  }
</script>

<div class="w-screen h-screen flex items-center justify-end" transition:fly="{{ x: 400 }}">

  <!-- Active Calls board: everything currently being worked, units inline.
       Only appears when there is something active. -->
  {#if activeCalls.length}
    <div class="pd-panel w-[330px] max-w-[26vw] h-[86%] mr-[10px]">
      <div class="pd-head">
        <div class="pd-icon pd-icon--green"><i class="fas fa-user-group"></i></div>
        <span class="pd-title">Active Calls</span>
        <span class="pd-badge pd-badge--green">{activeCalls.length}</span>
      </div>
      <div class="pd-scroll flex-1 overflow-y-auto p-[10px] flex flex-col gap-[6px]">
        {#each activeCalls as dispatch (dispatch.id)}
          <CallRow {dispatch} showUnitsInline expanded={activeCallId === dispatch.id} on:toggle={() => toggleDispatch(dispatch.id)} />
        {/each}
      </div>
    </div>
  {/if}

  <!-- Main dispatch panel: pending calls + controls -->
  <div class="pd-panel w-[370px] max-w-[30vw] h-[86%] mr-[14px]">

    <div class="pd-head">
      <div class="pd-icon"><i class="fas fa-tower-broadcast"></i></div>
      <span class="pd-title">Dispatch</span>
      {#if $DISPATCH_MENU}
        <span class="pd-badge">{pendingCalls.length} pending</span>
      {/if}
      <div class="flex items-center gap-[4px] ml-auto">
        <button class="pd-ctl" class:pd-ctl--active={statsOpen} title="Session stats" on:click={toggleStats}>
          <i class="fas fa-chart-simple"></i>
        </button>
        <button class="pd-ctl" title="Refresh" on:click={() => SendNUI("refreshAlerts")}>
          <i class="fas fa-arrows-rotate"></i>
        </button>
        <button class="pd-ctl" class:pd-ctl--active={$DISPATCH_MUTED} title="Mute sounds" on:click={toggleMute}>
          <i class="fas fa-volume-{$DISPATCH_MUTED ? "xmark" : "high"}"></i>
        </button>
        <button class="pd-ctl" class:pd-ctl--active={$DISPATCH_DISABLED} title="Toggle alerts" on:click={toggleAlerts}>
          <i class="fas fa-{$DISPATCH_DISABLED ? "bell-slash" : "bell"}"></i>
        </button>
        <button class="pd-ctl" title="Clear blips" on:click={() => SendNUI("clearBlips")}>
          <i class="fas fa-ban"></i>
        </button>
      </div>
    </div>

    {#if statsOpen && $STATS}
      <div class="pd-stats">
        <span><b>{$STATS.calls}</b> calls</span>
        {#if $STATS.mergedReports}<span><b>{$STATS.mergedReports}</b> merged</span>{/if}
        <span><b>{$STATS.calls ? Math.round(($STATS.answered / $STATS.calls) * 100) : 0}%</b> answered</span>
        <span>avg response <b class="pd-mono">{fmtAvg($STATS.avgResponseMs)}</b></span>
        {#if $STATS.topCode}<span>top: <b>{$STATS.topCode}</b> ×{$STATS.topCount}</span>{/if}
      </div>
    {/if}

    <div class="pd-scroll flex-1 overflow-y-auto p-[10px] flex flex-col gap-[6px]">
      {#if $DISPATCH_MENU}
        {#each pendingCalls as dispatch (dispatch.id)}
          <CallRow {dispatch} expanded={activeCallId === dispatch.id} on:toggle={() => toggleDispatch(dispatch.id)} />
        {/each}
        {#if !pendingCalls.length}
          <p class="pd-more" style="text-align:center; padding-top: 14px;">
            {activeCalls.length ? 'All calls are being handled' : 'No active calls'}
          </p>
        {/if}
      {/if}
    </div>
  </div>
</div>
