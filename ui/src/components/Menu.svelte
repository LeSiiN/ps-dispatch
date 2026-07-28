<script>
  import { DISPATCH_MENU, DISPATCH_MUTED, DISPATCH_DISABLED, STATS, ALERT_POSITION, MAX_VISIBLE_ALERTS, THUMBS_ENABLED, BLIPS_ENABLED, PRIORITY_ONLY, COMPACT_ALERTS, MAP_IMAGE, FOCUS_CALL, OVERLAY_OPEN, ALERT_TYPES, MUTED_CODES, ALERT_DURATION, REDUCED_MOTION, processedDispatchMenu, PLATE_HITS, MENU_TAB, PLATES_ENABLED, INCIDENTS, MAY_DECLARE, PLAYER, UI_SCALE } from '@store/stores';
  import { fly, fade, scale, slide } from 'svelte/transition';
  import { flip } from 'svelte/animate';
  import { DUR, EASE_IN, EASE_OUT } from '@utils/motion';
  import { SendNUI } from '@utils/SendNUI'
  import CallRow from './CallRow.svelte'
  import PlateRow from './PlateRow.svelte'
  import MapThumb from './MapThumb.svelte'
  import { tick } from 'svelte'

  // Fixed steps rather than a slider: the control sits in the dialog you are
  // adjusting, so anything that needs dragging fights you. The ceiling is
  // deliberate too — beyond about 1.3 the panel walks off a 1080p screen, and
  // the way back in is this dialog.
  const SCALES = [[0.9, 'Small'], [1.0, 'Default'], [1.15, 'Large'], [1.3, 'Huge']];

  let activeCallId = null;
  let activePlateId = null;

  // An alert arriving for a call must not leave the operator staring at the
  // plate log wondering where it went.
  $: if ($FOCUS_CALL != null) MENU_TAB.set('calls');

  function togglePlate(id) {
    activePlateId = activePlateId === id ? null : id;
  }

  $: alertHits = $PLATE_HITS.filter(h => h.tone === 'alert').length;

  // Declared calls float to the top of the list regardless of the usual order —
  // that pinning is most of the point of declaring one.
  $: incidentIds = new Set($INCIDENTS.map(i => i.id));

  // Which of them is this player actually working. Only those units are
  // quieted, so only they may be told that traffic is being held back —
  // claiming it on every board would be plainly untrue for most of them.
  $: myIncidentIds = new Set(
    ($DISPATCH_MENU || [])
      .filter(c => incidentIds.has(c.id)
        && (c.units || []).some(u => u?.citizenid === $PLAYER?.citizenid))
      .map(c => c.id)
  );
  // Critical first, then declared incidents, then everything else in its usual
  // order. An officer down outranks a supervisor's declaration — the supervisor
  // can look up, the officer cannot.
  const rank = (c) => (c.priority ?? 3) <= 0 ? 0 : incidentIds.has(c.id) ? 1 : 2;
  const pinIncidents = (list) => [...list].sort((a, b) => rank(a) - rank(b));
  $: sortedPending = pinIncidents(pendingCalls);
  // The active board needs the same treatment: a declared incident always has
  // units on it, so that board is where it actually lives.
  $: sortedActive = pinIncidents(activeCalls);
  let statsOpen = false;
  let settingsOpen = false;

  // Enlarged map overlay (one instance, driven by whichever row was clicked).
  let mapCall = null;
  let mapZoom = 8;
  const MAP_ZOOM_MIN = 3;
  const MAP_ZOOM_MAX = 40;

  // Tell the global Escape handler to stand down while a dialog is up.
  $: OVERLAY_OPEN.set(settingsOpen || mapCall != null);

  function onKeydown(e) {
    if (e.code !== 'Escape') return;
    if (mapCall) { mapCall = null; return; }      // topmost first
    if (settingsOpen) settingsOpen = false;
  }

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
  let typesOpen = false;

  function toggleMuted(code) {
    MUTED_CODES.update(list =>
      list.includes(code) ? list.filter(c => c !== code) : [...list, code]);
    saveSettings();
  }

  // 'vehicleshots' -> 'Vehicle shots'
  function prettyCode(code) {
    const spaced = code.replace(/([a-z])([A-Z])/g, '$1 $2').replace(/_/g, ' ');
    return spaced.charAt(0).toUpperCase() + spaced.slice(1);
  }

  function saveSettings() {
    try {
      // Persisted through Lua (SetResourceKvp) so a CEF cache clear doesn't
      // take the player's settings with it.
      SendNUI('saveDispatchSettings', JSON.stringify({
        uiScale: $UI_SCALE,
        alertPosition: $ALERT_POSITION,
        maxVisibleAlerts: $MAX_VISIBLE_ALERTS,
        thumbsEnabled: $THUMBS_ENABLED,
        blipsEnabled: $BLIPS_ENABLED,
        priorityOnly: $PRIORITY_ONLY,
        compactAlerts: $COMPACT_ALERTS,
        mutedCodes: $MUTED_CODES,
        alertDuration: $ALERT_DURATION,
        reducedMotion: $REDUCED_MOTION,
      }));
    } catch (e) { /* client unreachable — session-only */ }
    // Blips, the priority filter, per-type mutes and volume all gate work in
    // Lua BEFORE the NUI is involved, so they travel to the client as well.
    SendNUI('setDispatchPrefs', {
      blips: $BLIPS_ENABLED,
      priorityOnly: $PRIORITY_ONLY,
      mutedCodes: $MUTED_CODES,
    });
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

<svelte:window on:keydown={onKeydown} />

<!-- One transform on the wrapper scales the whole panel: every inner size is
     in px, so a font-size change alone would leave the layout behind. -->
<div
  class="w-screen h-screen flex items-center justify-end"
  style="transform:scale({$UI_SCALE});transform-origin:right center;"
>

  <!-- Active Calls board: everything currently being worked, units inline.
       Only appears when there is something active. -->
  {#if activeCalls.length}
    <div
      class="pd-panel w-[330px] max-w-[26vw] mr-[10px]" style="height:calc(86% / {$UI_SCALE});"
      in:fly={{ x: 26, duration: DUR.slow, easing: EASE_IN }}
      out:fly={{ x: 26, duration: DUR.exit, easing: EASE_OUT }}
    >
      <div class="pd-head">
        <div class="pd-icon pd-icon--green"><i class="fas fa-user-group"></i></div>
        <span class="pd-title">Active Calls</span>
        <span class="pd-badge pd-badge--green">{activeCalls.length}</span>
      </div>
      <div class="pd-scroll flex-1 overflow-y-auto p-[10px] flex flex-col gap-[6px]">
        {#each sortedActive as dispatch (dispatch.id)}
          <div animate:flip={{ duration: DUR.base, easing: EASE_OUT }}>
          <CallRow {dispatch} showUnitsInline expanded={activeCallId === dispatch.id} isIncident={incidentIds.has(dispatch.id)} mayDeclare={$MAY_DECLARE} on:toggle={() => toggleDispatch(dispatch.id)} on:expandMap={() => openMap(dispatch)} />
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Main dispatch panel: pending calls + controls -->
  <div
    class="pd-panel w-[370px] max-w-[30vw] mr-[14px]" style="height:calc(86% / {$UI_SCALE});"
    in:fly={{ x: 40, duration: DUR.slow, easing: EASE_IN }}
    out:fly={{ x: 40, duration: DUR.exit, easing: EASE_OUT }}
  >

    <div class="pd-head">
      <div class="pd-icon"><i class="fas fa-tower-broadcast"></i></div>
      <span class="pd-title">Dispatch</span>
      {#if $DISPATCH_MENU && ($MENU_TAB === 'calls' || !$PLATES_ENABLED)}
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

    <!-- Calls are the shared board; plate hits are this officer's own scanner
         log. Two different things, so they get two tabs rather than being
         mixed into one list. With the scanner disabled there is only one panel
         left, so the whole bar goes rather than leaving a lone tab. -->
    {#if $PLATES_ENABLED}
    <div class="pd-tabs">
      <button class="pd-tab" class:pd-tab--active={$MENU_TAB === 'calls'} on:click={() => MENU_TAB.set('calls')}>
        <i class="fas fa-tower-broadcast"></i>
        Calls
        {#if pendingCalls.length}
          <span class="pd-tab-count">{pendingCalls.length}</span>
        {/if}
      </button>
      <button class="pd-tab" class:pd-tab--active={$MENU_TAB === 'plates'} on:click={() => MENU_TAB.set('plates')}>
        <i class="fas fa-car-side"></i>
        Plates
        {#if $PLATE_HITS.length}
          <span class="pd-tab-count" class:pd-tab-count--alert={alertHits > 0}>{$PLATE_HITS.length}</span>
        {/if}
      </button>
      {#if $MENU_TAB === 'plates' && $PLATE_HITS.length}
        <button class="pd-tab-action" title="Clear the whole log" on:click={() => SendNUI('clearPlateHits', {})}>
          <i class="fas fa-trash-can"></i>
        </button>
      {/if}
    </div>
    {/if}

    {#if statsOpen && $STATS}
      <div class="pd-stats" transition:slide={{ duration: DUR.base, easing: EASE_OUT }}>
        <span><b>{$STATS.calls}</b> calls</span>
        {#if $STATS.mergedReports}<span><b>{$STATS.mergedReports}</b> merged</span>{/if}
        <span><b>{$STATS.calls ? Math.round(($STATS.answered / $STATS.calls) * 100) : 0}%</b> answered</span>
        <span>avg response <b class="pd-mono">{fmtAvg($STATS.avgResponseMs)}</b></span>
        {#if $STATS.topCode}<span>top: <b>{$STATS.topCode}</b> ×{$STATS.topCount}</span>{/if}
      </div>
    {/if}

    {#if $INCIDENTS.length && ($MENU_TAB === 'calls' || !$PLATES_ENABLED)}
      <!-- One strip per incident. Saying that routine traffic is being held
           back matters as much as naming the incident: without it the quiet
           board just looks broken. -->
      <div class="pd-incidents">
        {#each $INCIDENTS as inc (inc.id)}
          <div class="pd-incident" transition:slide={{ duration: DUR.fast, easing: EASE_OUT }}>
            <i class="fas fa-triangle-exclamation pd-incident-icon"></i>
            <div class="flex flex-col min-w-0 flex-1">
              <span class="pd-incident-title truncate">
                {inc.code ? inc.code + ' · ' : ''}{inc.title}
              </span>
              <span class="pd-incident-sub truncate">
                declared by {inc.declaredByName}{myIncidentIds.has(inc.id) ? ' · routine traffic held back' : ''}
              </span>
            </div>
            {#if $MAY_DECLARE}
              <button class="pd-incident-end" title="Stand down" on:click={() => SendNUI('standDownIncident', { id: inc.id })}>
                <i class="fas fa-xmark"></i>
              </button>
            {/if}
          </div>
        {/each}
      </div>
    {/if}

    <div class="pd-scroll flex-1 overflow-y-auto p-[10px] flex flex-col gap-[6px]">
      {#if $MENU_TAB === 'calls' || !$PLATES_ENABLED}
        {#if $DISPATCH_MENU}
          {#each sortedPending as dispatch (dispatch.id)}
            <div animate:flip={{ duration: DUR.base, easing: EASE_OUT }}>
            <CallRow {dispatch} expanded={activeCallId === dispatch.id} isIncident={incidentIds.has(dispatch.id)} mayDeclare={$MAY_DECLARE} on:toggle={() => toggleDispatch(dispatch.id)} on:expandMap={() => openMap(dispatch)} />
            </div>
          {/each}
          {#if !pendingCalls.length}
            <p class="pd-more" style="text-align:center; padding-top: 14px;" transition:fade={{ duration: DUR.fast }}>
              {activeCalls.length ? 'All calls are being handled' : 'No active calls'}
            </p>
          {/if}
        {/if}
      {:else}
        {#each $PLATE_HITS as hit (hit.id)}
          <div animate:flip={{ duration: DUR.base, easing: EASE_OUT }}>
            <PlateRow {hit} expanded={activePlateId === hit.id} on:click={() => togglePlate(hit.id)} />
          </div>
        {/each}
        {#if !$PLATE_HITS.length}
          <p class="pd-more" style="text-align:center; padding-top: 14px;" transition:fade={{ duration: DUR.fast }}>
            No plate checks run this session
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
          <div class="pd-icon {(mapCall.priority ?? 3) <= 1 ? 'pd-icon--priority' : ''} {(mapCall.priority ?? 3) <= 0 ? 'pd-icon--critical' : ''}">
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

</div>

<!-- Outside the scaled wrapper on purpose: the settings dialog is where you
     change the scale, so it must not move or resize while you do. Inside it,
     a large scale pushed the panel off screen with no way back in. -->
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
            <span class="pd-form-label">Interface Scale</span>
            <div class="pd-scale-row">
              {#each SCALES as [value, label]}
                <button
                  class="pd-scale-btn"
                  class:pd-scale-btn--active={Math.abs($UI_SCALE - value) < 0.001}
                  on:click={() => { UI_SCALE.set(value); saveSettings(); }}
                >{label}</button>
              {/each}
            </div>
            <span class="text-[10px] opacity-35">Sized for 1080p — 1440p usually wants Large, 4K Huge</span>
          </div>

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

          <div class="pd-form-group">
            <span class="pd-form-label">Alert Duration</span>
            <select class="pd-select" value={$ALERT_DURATION} on:change={(e) => { ALERT_DURATION.set(Number(e.target.value)); saveSettings(); }}>
              <option value={0.5}>Short (0.5×)</option>
              <option value={1}>Normal (1×)</option>
              <option value={1.5}>Long (1.5×)</option>
              <option value={2}>Very long (2×)</option>
            </select>
            <span class="pd-form-hint">How long alert cards stay on screen</span>
          </div>

          <div class="pd-toggle-row">
            <div class="pd-form-group">
              <span class="pd-form-label">Reduced Motion</span>
              <span class="pd-form-hint">Disable animations — calmer, and lighter on weak PCs</span>
            </div>
            <div class="pd-toggle" class:pd-toggle--on={$REDUCED_MOTION} on:click={() => { REDUCED_MOTION.update(v => !v); saveSettings(); }}></div>
          </div>

          {#if $ALERT_TYPES.length}
            <div class="pd-form-group">
              <button class="pd-btn w-full" on:click={() => typesOpen = !typesOpen}>
                <i class="fas fa-filter"></i>
                Alert Types
                {#if $MUTED_CODES.length}<span class="pd-badge pd-badge--amber">{$MUTED_CODES.length} muted</span>{/if}
                <i class="fas fa-chevron-{typesOpen ? 'up' : 'down'} ml-auto text-[9px] opacity-50"></i>
              </button>
              {#if typesOpen}
                <div class="pd-types pd-scroll">
                  {#each $ALERT_TYPES as code}
                    <div class="pd-type-row">
                      <span class="truncate">{prettyCode(code)}</span>
                      <div class="pd-toggle pd-toggle--sm" class:pd-toggle--on={!$MUTED_CODES.includes(code)} on:click={() => toggleMuted(code)}></div>
                    </div>
                  {/each}
                </div>
                <span class="pd-form-hint">Muted types produce no popup, sound or blip for you</span>
              {/if}
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