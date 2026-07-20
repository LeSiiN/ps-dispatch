<script>
  import { DISPATCH_MENU, DISPATCH_MUTED, DISPATCH_DISABLED, STATS, ALERT_POSITION, MAX_VISIBLE_ALERTS, THUMBS_ENABLED, BLIPS_ENABLED, PRIORITY_ONLY, COMPACT_ALERTS, MAP_IMAGE, FOCUS_CALL, processedDispatchMenu } from '@store/stores';
  import { fly, fade, scale, slide } from 'svelte/transition';
  import { flip } from 'svelte/animate';
  import { DUR, EASE_IN, EASE_OUT } from '@utils/motion';
  import { SendNUI } from '@utils/SendNUI'
  import CallRow from './CallRow.svelte'
  import MapThumb from './MapThumb.svelte'
  import { tick } from 'svelte'

  let activeCallId = null;
  let statsOpen = false;
  let settingsOpen = false;

  // Enlarged map overlay (one instance, driven by whichever row was clicked).
  let mapCall = null;
  let mapZoom = 8;
  const MAP_ZOOM_MIN = 3;
  const MAP_ZOOM_MAX = 40;

  function openMap(dispatch) {
    mapCall = dispatch;
    mapZoom = 10;
  }

  function zoomMap(factor) {
    mapZoom = Math.min(MAP_ZOOM_MAX, Math.max(MAP_ZOOM_MIN, mapZoom * factor));
  }

  function onMapWheel(e) {
    e.preventDefault();
    zoomMap(e.deltaY < 0 ? 1.2 : 1 / 1.2);
  }

  // Opening the menu while an alert is up jumps straight to that call:
  // expanded and scrolled into view, so it isn't buried in the list.
  $: if ($FOCUS_CALL != null) focusCall($FOCUS_CALL);

  async function focusCall(id) {
    activeCallId = id;
    FOCUS_CALL.set(null); // consume — a later manual collapse must stick
    await tick();
    const el = document.querySelector(`[data-call-id="${id}"]`);
    if (el) el.scrollIntoView({ block: 'nearest' });
  }

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
        blipsEnabled: $BLIPS_ENABLED,
        priorityOnly: $PRIORITY_ONLY,
        compactAlerts: $COMPACT_ALERTS,
      }));
    } catch (e) { /* storage unavailable — session-only */ }
    // Blips and the priority filter gate work in Lua BEFORE the NUI is
    // involved, so those two have to travel to the client as well.
    SendNUI('setDispatchPrefs', { blips: $BLIPS_ENABLED, priorityOnly: $PRIORITY_ONLY });
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

<div class="w-screen h-screen flex items-center justify-end">

  <!-- Active Calls board: everything currently being worked, units inline.
       Only appears when there is something active. -->
  {#if activeCalls.length}
    <div
      class="pd-panel w-[330px] max-w-[26vw] h-[86%] mr-[10px]"
      in:fly={{ x: 26, duration: DUR.slow, easing: EASE_IN }}
      out:fly={{ x: 26, duration: DUR.exit, easing: EASE_OUT }}
    >
      <div class="pd-head">
        <div class="pd-icon pd-icon--green"><i class="fas fa-user-group"></i></div>
        <span class="pd-title">Active Calls</span>
        <span class="pd-badge pd-badge--green">{activeCalls.length}</span>
      </div>
      <div class="pd-scroll flex-1 overflow-y-auto p-[10px] flex flex-col gap-[6px]">
        {#each activeCalls as dispatch (dispatch.id)}
          <div animate:flip={{ duration: DUR.base, easing: EASE_OUT }}>
          <CallRow {dispatch} showUnitsInline expanded={activeCallId === dispatch.id} on:toggle={() => toggleDispatch(dispatch.id)} on:expandMap={() => openMap(dispatch)} />
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Main dispatch panel: pending calls + controls -->
  <div
    class="pd-panel w-[370px] max-w-[30vw] h-[86%] mr-[14px]"
    in:fly={{ x: 40, duration: DUR.slow, easing: EASE_IN }}
    out:fly={{ x: 40, duration: DUR.exit, easing: EASE_OUT }}
  >

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
        <button class="pd-ctl" title="Clear blips" on:click={() => SendNUI("clearBlips")}>
          <i class="fas fa-ban"></i>
        </button>
      </div>
    </div>

    {#if statsOpen && $STATS}
      <div class="pd-stats" transition:slide={{ duration: DUR.base, easing: EASE_OUT }}>
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
          <div animate:flip={{ duration: DUR.base, easing: EASE_OUT }}>
          <CallRow {dispatch} expanded={activeCallId === dispatch.id} on:toggle={() => toggleDispatch(dispatch.id)} on:expandMap={() => openMap(dispatch)} />
          </div>
        {/each}
        {#if !pendingCalls.length}
          <p class="pd-more" style="text-align:center; padding-top: 14px;" transition:fade={{ duration: DUR.fast }}>
            {activeCalls.length ? 'All calls are being handled' : 'No active calls'}
          </p>
        {/if}
      {/if}
    </div>
  </div>

  {#if mapCall}
    <!-- Enlarged map: same crop maths as the thumbnail, just bigger and with
         a zoom range. Scroll wheel or the buttons. -->
    <div class="pd-modal-overlay" on:click|self={() => mapCall = null} transition:fade={{ duration: DUR.fast }}>
      <div class="pd-map-modal" in:scale={{ start: 0.96, duration: DUR.base, easing: EASE_IN }} out:scale={{ start: 0.97, duration: DUR.exit, easing: EASE_OUT }}>
        <div class="pd-modal-head">
          <div class="pd-icon {mapCall.priority == 1 ? 'pd-icon--priority' : ''}">
            <i class={mapCall.icon}></i>
          </div>
          <span class="pd-modal-title">{mapCall.message}</span>
          {#if mapCall.street}<span class="pd-badge">{mapCall.street}</span>{/if}
          <button class="pd-ctl" title="Close" on:click={() => mapCall = null}>
            <i class="fas fa-xmark"></i>
          </button>
        </div>
        <div class="pd-map-stage" on:wheel|preventDefault={onMapWheel}>
          <MapThumb
            coords={mapCall.displayCoords || mapCall.coords}
            radius={mapCall.mapRadius || 0}
            priority={mapCall.priority}
            src={$MAP_IMAGE}
            zoom={mapZoom}
            height={520}
          />
          <div class="pd-map-controls">
            <button class="pd-ctl" title="Zoom in" on:click={() => zoomMap(1.35)}><i class="fas fa-plus"></i></button>
            <button class="pd-ctl" title="Zoom out" on:click={() => zoomMap(1 / 1.35)}><i class="fas fa-minus"></i></button>
          </div>
          <span class="pd-map-hint">Scroll to zoom</span>
        </div>
      </div>
    </div>
  {/if}

  {#if settingsOpen}
    <!-- Settings modal — ImpoundForm anatomy: overlay, centered panel,
         13/20 header with hairline, label-over-control form groups. -->
    <div class="pd-modal-overlay" on:click|self={() => settingsOpen = false} transition:fade={{ duration: DUR.fast }}>
      <div class="pd-modal" in:scale={{ start: 0.96, duration: DUR.base, easing: EASE_IN }} out:scale={{ start: 0.97, duration: DUR.exit, easing: EASE_OUT }}>
        <div class="pd-modal-head">
          <div class="pd-icon"><i class="fas fa-gear"></i></div>
          <span class="pd-modal-title">Dispatch Settings</span>
          <button class="pd-ctl" title="Close" on:click={() => settingsOpen = false}>
            <i class="fas fa-xmark"></i>
          </button>
        </div>
        <div class="pd-modal-body pd-scroll">

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
              <span class="pd-form-label">Compact Alerts</span>
              <span class="pd-form-hint">Header, location and note only — no vehicle or suspect details</span>
            </div>
            <div class="pd-toggle" class:pd-toggle--on={$COMPACT_ALERTS} on:click={() => { COMPACT_ALERTS.update(v => !v); saveSettings(); }}></div>
          </div>

          <div class="pd-toggle-row">
            <div class="pd-form-group">
              <span class="pd-form-label">Map Blips</span>
              <span class="pd-form-hint">Place a blip and search radius on the game map</span>
            </div>
            <div class="pd-toggle" class:pd-toggle--on={$BLIPS_ENABLED} on:click={() => { BLIPS_ENABLED.update(v => !v); saveSettings(); }}></div>
          </div>

          <div class="pd-toggle-row">
            <div class="pd-form-group">
              <span class="pd-form-label">Priority Alerts Only</span>
              <span class="pd-form-hint">Mute routine calls entirely — assignments always come through</span>
            </div>
            <div class="pd-toggle" class:pd-toggle--on={$PRIORITY_ONLY} on:click={() => { PRIORITY_ONLY.update(v => !v); saveSettings(); }}></div>
          </div>

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
