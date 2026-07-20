<script>
  import { DISPATCH_MENU, DISPATCH_MUTED, DISPATCH_DISABLED, STATS, ALERT_POSITION, MAX_VISIBLE_ALERTS, THUMBS_ENABLED, MAP_IMAGE, processedDispatchMenu } from '@store/stores';
  import { fly } from 'svelte/transition';
  import { SendNUI } from '@utils/SendNUI'
  import CallRow from './CallRow.svelte'

  let activeCallId = null;
  let statsOpen = false;
  let settingsOpen = false;

  const ALERT_POSITIONS = [
    ['top-left', 'Top Left'], ['top-center', 'Top Center'], ['top-right', 'Top Right'],
    ['center-left', 'Center Left'], ['center-right', 'Center Right'],
    ['bottom-left', 'Bottom Left'], ['bottom-center', 'Bottom Center'], ['bottom-right', 'Bottom Right'],
  ];

  // Persist the modal's choices per player; AlwaysListener re-applies them
  // over the config defaults on every session start.
  function saveSettings() {
    try {
      localStorage.setItem('psd-settings', JSON.stringify({
        alertPosition: $ALERT_POSITION,
        maxVisibleAlerts: $MAX_VISIBLE_ALERTS,
        thumbsEnabled: $THUMBS_ENABLED,
      }));
    } catch (e) { /* storage unavailable — session-only */ }
  }

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
        <button class="pd-ctl" class:pd-ctl--active={settingsOpen} title="Settings" on:click={() => settingsOpen = true}>
          <i class="fas fa-gear"></i>
        </button>
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

  {#if settingsOpen}
    <!-- Settings modal — ImpoundForm anatomy: overlay, centered panel,
         13/20 header with hairline, label-over-control form groups. -->
    <div class="pd-modal-overlay" on:click|self={() => settingsOpen = false}>
      <div class="pd-modal">
        <div class="pd-modal-head">
          <div class="pd-icon"><i class="fas fa-gear"></i></div>
          <span class="pd-modal-title">Dispatch Settings</span>
          <button class="pd-ctl" title="Close" on:click={() => settingsOpen = false}>
            <i class="fas fa-xmark"></i>
          </button>
        </div>
        <div class="pd-modal-body">

          <div class="pd-form-group">
            <span class="pd-form-label">Alert Position</span>
            <select class="pd-select" value={$ALERT_POSITION} on:change={(e) => { ALERT_POSITION.set(e.target.value); saveSettings(); }}>
              {#each ALERT_POSITIONS as [value, label]}
                <option {value}>{label}</option>
              {/each}
            </select>
            <span class="pd-form-hint">Where incoming alert cards appear on screen</span>
          </div>

          <div class="pd-form-group">
            <span class="pd-form-label">Max Visible Alerts</span>
            <select class="pd-select" value={$MAX_VISIBLE_ALERTS} on:change={(e) => { MAX_VISIBLE_ALERTS.set(Number(e.target.value)); saveSettings(); }}>
              {#each [2, 3, 4, 5, 6] as n}
                <option value={n}>{n}</option>
              {/each}
            </select>
            <span class="pd-form-hint">Older alerts collapse into "+N more"</span>
          </div>

          {#if $MAP_IMAGE}
            <div class="pd-toggle-row">
              <div class="pd-form-group">
                <span class="pd-form-label">Map Thumbnails</span>
                <span class="pd-form-hint">Scene preview on alerts and expanded calls</span>
              </div>
              <div class="pd-toggle" class:pd-toggle--on={$THUMBS_ENABLED} on:click={() => { THUMBS_ENABLED.update(v => !v); saveSettings(); }}></div>
            </div>
          {/if}

          <div class="pd-toggle-row">
            <div class="pd-form-group">
              <span class="pd-form-label">Alert Sounds</span>
              <span class="pd-form-hint">Audio cue when a new alert arrives</span>
            </div>
            <div class="pd-toggle" class:pd-toggle--on={!$DISPATCH_MUTED} on:click={toggleMute}></div>
          </div>

          <div class="pd-toggle-row">
            <div class="pd-form-group">
              <span class="pd-form-label">Receive Alerts</span>
              <span class="pd-form-hint">Master switch — popups, sounds and blips</span>
            </div>
            <div class="pd-toggle" class:pd-toggle--on={!$DISPATCH_DISABLED} on:click={toggleAlerts}></div>
          </div>

        </div>
      </div>
    </div>
  {/if}
</div>
